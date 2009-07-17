(* Ocsimore
 * Copyright (C) 2005
 * Laboratoire PPS - Université Paris Diderot - CNRS
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)
(**
   @author Piero Furiesi
   @author Jaap Boender
   @author Vincent Balat
*)

let (>>=)= Lwt.bind

open Sql.PGOCaml
open Ocsimore_lib
open CalendarLib
open Sql

module Types = struct

  type userid = [`User ] Opaque.int32_t

  let userid_from_sql (u : int32) = (Opaque.int32_t u : userid)
  let sql_from_userid (u : userid) = Opaque.t_int32 u

  let string_from_userid i = Int32.to_string (Opaque.t_int32 i)


  type pwd =
    | Connect_forbidden
    | Ocsimore_user_plain of string
    | Ocsimore_user_crypt of string
    | External_Auth

  type userdata = {
    user_id: userid;
    user_login: string;
    mutable user_pwd: pwd;
    mutable user_fullname: string;
    mutable user_email: string option;
    user_dyn: bool;
    user_kind: [`BasicUser | `ParameterizedGroup | `NonParameterizedGroup];
  }


  (* 'a is a phantome type, used to represent the type of the argument
     of the user *)
  type 'a parameterized_group = userid

  type user =
    | BasicUser of userid
    | AppliedParameterizedGroup of userid * int32
    | NonParameterizedGroup of userid


  let apply_parameterized_group g v =
    AppliedParameterizedGroup (g, Opaque.t_int32 v)

  let ($) = apply_parameterized_group

  let basic_user v = BasicUser v

  let userid_from_user = function
    | BasicUser u | NonParameterizedGroup u -> u
    | AppliedParameterizedGroup (u, _) -> u


  type 'a admin_writer_reader = {
    grp_admin: 'a parameterized_group;
    grp_writer: 'a parameterized_group;
    grp_reader: 'a parameterized_group;
  }

end
open Types


(* Constant used in the database to detect parameterized edge. Must
   of course be different from all other parameters. This must be
   enforced in all the modules using parameterized groups, for example
   by using serial types that statr at 0 *)
let ct_parameterized_edge = -1l

(* Same kind of things for non parameterized groups *)
let ct_non_parameterized_group = -2l

let sql_from_user = function
  | BasicUser u -> (sql_from_userid u, None)
  | AppliedParameterizedGroup (u, v) -> (sql_from_userid u, Some v)
  | NonParameterizedGroup u ->
      (sql_from_userid u, Some ct_non_parameterized_group)

let user_from_sql = function
  | (u, None) -> BasicUser (userid_from_sql u)
  | (u, Some v) ->
      if v = ct_non_parameterized_group
      then NonParameterizedGroup (userid_from_sql u)
      else AppliedParameterizedGroup (userid_from_sql u, v)


(* Transforms an incoming value of type [pwd], in which
   [Ocsimore_user_crypt] is supposed to contain the unencrypted password,
   into the outgoing value of type [pwd] ([Ocsimore_user_crypt] contains the
   encrypted password) and the database representation of this value,
   for the columns password and authtype respectively *)
(* Notice that "g" and "h" are used in the database for parametrized groups.
   However they are still translated as having authtype [Connect_forbidden] *)
let pass_authtype_from_pass pwd = match pwd with
  | Connect_forbidden ->
      Lwt.return (pwd, (None, "l"))

  | External_Auth ->
      Lwt.return (pwd, (None, "p"))

  | Ocsimore_user_plain p ->
      Lwt.return (pwd, (Some p, "l"))

  | Ocsimore_user_crypt pass ->
      Nis_chkpwd.crypt_passwd pass >>=
      fun crypt ->
      Lwt.return (Ocsimore_user_crypt crypt, (Some crypt, "c"))


let remove_from_group_aux db (u, vu) (g, vg) =
  match vu, vg with
    | None, None ->
        PGSQL(db) "DELETE FROM userrights
                   WHERE id = $u AND groupid = $g
                   AND   idarg IS NULL AND groupidarg IS NULL"
    | Some vu, None ->
        PGSQL(db) "DELETE FROM userrights
                   WHERE id = $u AND groupid = $g
                   AND   idarg = $vu AND groupidarg IS NULL"
    | Some vu, Some vg ->
        PGSQL(db) "DELETE FROM userrights
                   WHERE id = $u AND groupid = $g
                   AND   idarg = $vu AND groupidarg = $vg"
    | None, Some vg ->
        PGSQL(db) "DELETE FROM userrights
                   WHERE id = $u AND groupid = $g
                   AND   idarg IS NULL AND groupidarg = $vg"

let remove_from_group_ ~user ~group =
  Lwt_pool.use Sql.pool (fun db -> remove_from_group_aux db
                           (sql_from_user user) (sql_from_user group))

let add_to_group_aux db (u, vu) (g, vg) =
  remove_from_group_aux db (u, vu) (g, vg) >>= fun () ->
  PGSQL(db) "INSERT INTO userrights (id, groupid, idarg, groupidarg)
             VALUES ($u, $g, $?vu, $?vg)"

let populate_groups db user groups =
  let (u, vu) = sql_from_user user in
  Lwt_util.iter_serial (fun g -> add_to_group_aux db (u, vu) (sql_from_user g))
    groups

let add_to_group_ ~user ~group =
  Lwt_pool.use Sql.pool
    (fun db ->
       add_to_group_aux db (sql_from_user user) (sql_from_user group))


let add_generic_inclusion_ ~subset ~superset =
  Lwt_pool.use Sql.pool
    (fun db ->
       let subset = sql_from_userid subset
       and superset = sql_from_userid superset in
       add_to_group_aux db (subset, Some ct_parameterized_edge)
         (superset, Some ct_parameterized_edge)
    )


let new_user ~name ~password ~fullname ~email ~dyn =
  pass_authtype_from_pass password
  >>= fun (pwd, (password, authtype)) ->
  Sql.full_transaction_block
    (fun db ->
       (match password, email with
          | None, None ->
              PGSQL(db) "INSERT INTO users (login, fullname, dyn, authtype)\
                    VALUES ($name, $fullname, $dyn, $authtype)"
          | Some pwd, None ->
              PGSQL(db) "INSERT INTO users (login, password, fullname, dyn, authtype) \
                    VALUES ($name, $pwd, $fullname, $dyn, $authtype)"
          | None, Some email ->
              PGSQL(db) "INSERT INTO users (login, fullname, email, dyn, authtype) \
                    VALUES ($name, $fullname, $email, $dyn, $authtype)"
          | Some pwd, Some email ->
              PGSQL(db) "INSERT INTO users (login, password, fullname, email, dyn, authtype) \
                    VALUES ($name, $pwd, $fullname, $email, $dyn, $authtype)"
       ) >>= fun () ->
       serial4 db "users_id_seq"
       >>= fun id ->
       let id = userid_from_sql id in
       Lwt.return (id, pwd)
    )

let find_userid_by_name_aux_ db name =
  PGSQL(db) "SELECT id FROM users WHERE login = $name"
  >>= function
    | [] -> Lwt.fail Not_found
    | r :: _ -> Lwt.return (userid_from_sql r)


let new_group authtype ~prefix ~name ~fullname =
  let name = "#" ^ prefix ^ "." ^ name in
  Sql.full_transaction_block
    (fun db ->
       Lwt.catch
         (fun () -> find_userid_by_name_aux_ db name)
         (function
            | Not_found ->
                PGSQL(db) "INSERT INTO users (login, fullname, dyn, authtype)\
                           VALUES ($name, $fullname, FALSE, $authtype)"
                >>= fun () ->
                serial4 db "users_id_seq"
                >>= fun id -> Lwt.return (userid_from_sql id)
            | e -> Lwt.fail e
         ))

let new_parameterized_group = new_group "g"
let new_nonparameterized_group ~prefix ~name ~fullname =
  new_group "h" ~prefix ~name ~fullname >>= fun id ->
  Lwt.return (NonParameterizedGroup id)

let wrap_userdata (id, login, pwd, name, email, dyn, authtype) =
  let password = match authtype, pwd with
    | "p", _ -> External_Auth
    | "c", Some p -> Ocsimore_user_crypt p
    | "l", Some p -> Ocsimore_user_plain p
    | _ -> Connect_forbidden
  in
  { user_id = userid_from_sql id; user_login = login;
    user_pwd = password; user_fullname = name;
    user_email = email; user_dyn = dyn;
    user_kind =
      match authtype with
        | "g" -> `ParameterizedGroup
        | "h" -> `NonParameterizedGroup
        | _ -> `BasicUser}


let find_user_by_name_ name =
  Lwt_pool.use Sql.pool
    (fun db ->
       PGSQL(db) "SELECT id, login, password, fullname, email, dyn, authtype \
                  FROM users WHERE login = $name"
       >>= function
         | [] -> Lwt.fail Not_found
         | r :: _ -> Lwt.return (wrap_userdata r))

let find_userid_by_name_ name =
  Lwt_pool.use Sql.pool (fun db -> find_userid_by_name_aux_ db name)


let find_user_by_id_ id =
  let id = sql_from_userid id in
  Lwt_pool.use Sql.pool
    (fun db ->
       PGSQL(db) "SELECT id, login, password, fullname, email, dyn, authtype \
                  FROM users WHERE id = $id"
       >>= function
         | [] -> Lwt.fail Not_found
         | r :: _ -> Lwt.return (wrap_userdata r))

let all_groups () =
  Lwt_pool.use Sql.pool
    (fun db ->
       PGSQL(db) "SELECT id, login, password, fullname, email, dyn, authtype \
                  FROM users"
       >>= fun l -> Lwt.return (List.map wrap_userdata l))


let delete_user_ ~userid =
  let userid = sql_from_userid userid in
  Lwt_pool.use Sql.pool (fun db ->
  PGSQL(db) "DELETE FROM users WHERE id = $userid")


let update_data_ ~userid ?password ?fullname ?email ?dyn () =
  let userid = sql_from_userid userid in
  Sql.full_transaction_block
    (fun db ->
       (match password with
          | None -> Lwt.return ()
          | Some pwd ->
              pass_authtype_from_pass pwd
              >>= fun (_pwd, (password, authtype)) ->
              PGSQL(db) "UPDATE users
                         SET password = $?password, authtype = $authtype
                         WHERE id = $userid"
       ) >>= fun () ->
       (match fullname with
          | None -> Lwt.return ()
          | Some fullname -> PGSQL(db)
              "UPDATE users SET fullname = $fullname WHERE id = $userid"
       ) >>= fun () ->
       (match email with
          | None -> Lwt.return ()
          | Some email -> PGSQL(db)
              "UPDATE users SET email = $email WHERE id = $userid"
       ) >>= fun () ->
       (match dyn with
          | Some dyn -> PGSQL(db)
              "UPDATE users SET dyn = $dyn WHERE id = $userid"
          | None -> Lwt.return ()
       )
    )

(* Auxiliary functions to read permissions from the userrights table *)
let convert_group_list = List.map user_from_sql

let convert_generic_lists r1 r2 v =
  let l1 = convert_group_list r1
  and l2 = List.map (fun g ->
                       AppliedParameterizedGroup (userid_from_sql g, v)) r2 in
  l1 @ l2


let groups_of_user_ ~user =
  let u, vu = sql_from_user user in
  Lwt_pool.use Sql.pool
    (fun db ->
       (match vu with
          | None ->
              PGSQL(db) "SELECT groupid, groupidarg FROM userrights
                         WHERE id = $u AND idarg IS NULL"
              >>= fun l -> Lwt.return (convert_group_list l)
          | Some vu ->
              (* Standard inclusions *)
              PGSQL(db) "SELECT groupid, groupidarg FROM userrights
                         WHERE id = $u AND idarg = $vu"
              >>= fun r1 ->
              (* Generic edges. If the database is correct, groupidarg
                 is always [ct_parameterized_edge] *)
              PGSQL(db) "SELECT groupid FROM userrights
                         WHERE id = $u AND idarg = $ct_parameterized_edge"
              >>= fun r2 ->
              Lwt.return (convert_generic_lists r1 r2 vu)
       )
    )

(* as above *)
let users_in_group_ ?(generic=true) ~group =
  let g, vg = sql_from_user group in
  Lwt_pool.use Sql.pool
    (fun db ->
       (match vg with
          | None ->
              PGSQL(db) "SELECT id, idarg FROM userrights
                         WHERE groupid = $g AND groupidarg IS NULL"
              >>= fun l -> Lwt.return (convert_group_list l)
          | Some vg ->
              PGSQL(db) "SELECT id, idarg FROM userrights
                         WHERE groupid = $g AND groupidarg = $vg"
              >>= fun r1 ->
              (if generic then
                 PGSQL(db) "SELECT id FROM userrights
                            WHERE groupid = $g AND groupidarg = $ct_parameterized_edge"
               else
                 Lwt.return []
              )
              >>= fun r2 ->
              Lwt.return (convert_generic_lists r1 r2 vg)
       )
    )


(** Cached version of the functions above *)

let debug_print_cache = ref false

let print_cache s =
  if !debug_print_cache then print_endline s


(* Find user info by id *)

module IUserCache = Cache.Make (struct
                          type key = userid
                          type value = userdata
                        end)

let iusercache = IUserCache.create
  (fun id -> find_user_by_id_ id) 64

let get_basicuser_data i =
  print_cache "cache iuser ";
  IUserCache.find iusercache i

let get_parameterized_user_data = get_basicuser_data

let get_user_data = function
  | AppliedParameterizedGroup (i, _) | BasicUser i | NonParameterizedGroup i ->
      get_basicuser_data i


(* Find userid by login *)

module NUseridCache = Cache.Make (struct
                          type key = string
                          type value = userid
                        end)

exception NotBasicUser of userdata

let nuseridcache = NUseridCache.create
  (fun name ->
     find_user_by_name_ name
     >>= fun u ->
     if u.user_kind <> `BasicUser then
       Lwt.fail (NotBasicUser u)
     else (
       Lwt.return u.user_id)
  ) 64

let get_basicuser_by_login n =
  print_cache "cache nuserid ";
  NUseridCache.find nuseridcache n


(* Find user from string *)

module NUserCache = Cache.Make (struct
                          type key = string
                          type value = user
                        end)

let nusercache = NUserCache.create
  (fun s ->
     if String.length s > 0 && s.[0] = '#' then
       try
         Scanf.sscanf s "%s@(%ld)"
           (fun g v ->
              find_user_by_name_ g
              >>= fun u ->
              if u.user_kind = `ParameterizedGroup then
                Lwt.return (AppliedParameterizedGroup (u.user_id, v))
              else
                Lwt.fail Not_found
           )
       with _ ->
         try
           find_user_by_name_ s
           >>= fun u ->
           if u.user_kind = `NonParameterizedGroup then
             Lwt.return (NonParameterizedGroup u.user_id)
           else
             Lwt.fail Not_found
         with _ -> Lwt.fail Not_found

     else
       get_basicuser_by_login s >>= fun u ->
         Lwt.return (basic_user u)
  ) 64

let get_user_by_name name =
  print_cache "cache nuser ";
  NUserCache.find nusercache name



let update_data ~userid ?password ?fullname ?email ?dyn () =
  IUserCache.clear iusercache;
  NUserCache.clear nusercache;
  update_data_ ~userid ?password ?fullname ?email ?dyn ()



(* Groups-related functions *)

module GroupUsersCache = Cache.Make (struct
                             type key = user
                             type value = user list
                           end)

module UsersGroupCache = Cache.Make (struct
                             type key = user * bool
                             type value = user list
                           end)

let group_of_users_cache = GroupUsersCache.create
  (fun u -> groups_of_user_ u) 8777
let users_in_group_cache = UsersGroupCache.create
  (fun (g, b) -> users_in_group_ ~generic:b ~group:g) 8777

let groups_of_user ~user =
  print_cache "cache groups_of_user ";
  GroupUsersCache.find group_of_users_cache user

let users_in_group ?(generic=true) ~group =
  print_cache "cache users_in_group ";
  UsersGroupCache.find users_in_group_cache (group, generic)

let add_to_group ~user ~group =
  GroupUsersCache.remove group_of_users_cache user;
  UsersGroupCache.clear users_in_group_cache;
  add_to_group_ ~user ~group

let add_generic_inclusion ~subset ~superset =
  GroupUsersCache.clear group_of_users_cache;
  add_generic_inclusion_ ~subset ~superset

let add_to_group_generic ~user ~group =
  add_generic_inclusion ~subset:user ~superset:group

let remove_from_group ~user ~group =
  GroupUsersCache.remove group_of_users_cache user;
  UsersGroupCache.clear users_in_group_cache;
  remove_from_group_ ~user ~group


(* Deletion *)

let delete_user ~userid =
  (* We clear all the caches, as we should iterate over all the
     parameters if [userid] is a parametrized group *)
  IUserCache.clear iusercache;
  NUseridCache.clear nuseridcache;
  NUserCache.clear nusercache;
  GroupUsersCache.clear group_of_users_cache;
  UsersGroupCache.clear users_in_group_cache;
  delete_user_ ~userid


(* Conversion to string *)

let userid_to_string u =
  get_basicuser_data u
  >>= fun { user_login = r } -> Lwt.return r

let user_to_string = function
  | BasicUser u | NonParameterizedGroup u -> userid_to_string u
  | AppliedParameterizedGroup (u, v) ->
      userid_to_string u >>= fun s ->
      Lwt.return (Printf.sprintf "%s(%ld)" s v)
