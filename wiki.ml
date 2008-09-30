(* Ocsimore
 * Copyright (C) 2005 Piero Furiesi Jaap Boender Vincent Balat
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
This is the wiki component of Ocsimore.

@author Jaap Boender
@author Piero Furiesi
@author Vincent Balat
*)


let (>>=) = Lwt.bind

(** Role of user in the wiki (for one box) *)
type role = Admin | Author | Lurker | Nonauthorized;;
(* Admin can changes the permissions on boxes *)


type wiki_info = {
  id : Wiki_sql.wiki;
  title : string;
  descr : string;
  boxrights : bool;
  pages : bool;
  last : int32 ref;
  container_id : int32 option;
  staticdir : string option; (* if static dir is given, 
                                ocsimore will serve static pages if present,
                                instead of wiki pages *)
}



let get_wiki_by_id id =
  Wiki_cache.find_wiki id >>= fun (id, title, descr, pages, br, last, ci, stat) -> 
  Lwt.return { id = id; 
               title = title; 
               descr = descr;
               boxrights = br;
               pages = pages;
               last = last;
               container_id = ci;
               staticdir = stat;
             }

let get_wiki_by_name name =
  Wiki_sql.find_wiki_id_by_name name >>= fun id -> 
  get_wiki_by_id id


let get_sthg_ f ?wiki ((w, i) as k) =
  (match wiki with
    | Some w -> Lwt.return w
    | None -> get_wiki_by_id w)
  >>= fun wiki_info ->
  if wiki_info.boxrights
  then
    f k >>= fun r -> Lwt.return (Some r)
  else Lwt.return None

let get_readers =
  get_sthg_ Wiki_cache.get_readers_

let get_writers =
  get_sthg_ Wiki_cache.get_writers_

let get_rights_adm =
  get_sthg_ Wiki_cache.get_rights_adm_

let get_wikiboxes_creators =
  get_sthg_ Wiki_cache.get_wikiboxes_creators_


let readers_group_name i = "wiki"^Int32.to_string i^"_readers"
let writers_group_name i = "wiki"^Int32.to_string i^"_writers"
let rights_adm_group_name i = "wiki"^Int32.to_string i^"_rights_givers"
let page_creators_group_name i = "wiki"^Int32.to_string i^"_page_creators"
let css_editors_group_name i = "wiki"^Int32.to_string i^"_css_editors"
let wikiboxes_creators_group_name i = "wiki"^Int32.to_string i^"_wikiboxes_creators"
let container_adm_group_name i = "wiki"^Int32.to_string i^"_container_adm"
let admin_group_name i = "wiki"^Int32.to_string i^"_admin"

let readers_group i = Users.get_user_id_by_name (readers_group_name i)
let writers_group i = Users.get_user_id_by_name (writers_group_name i)
let rights_adm_group  i = Users.get_user_id_by_name (rights_adm_group_name  i)
let page_creators_group i = 
                      Users.get_user_id_by_name (page_creators_group_name i)
let css_editors_group i = 
                      Users.get_user_id_by_name (css_editors_group_name i)
let wikiboxes_creators_group i = 
                      Users.get_user_id_by_name
                        (wikiboxes_creators_group_name i)
let container_adm_group i =
                      Users.get_user_id_by_name (container_adm_group_name i)
let admin_group i =   Users.get_user_id_by_name (admin_group_name i)


exception Found of int32

let new_wikibox ?boxid ~wiki ~author ~comment ~content
    ?readers ?writers ?rights_adm ?wikiboxes_creators () =
  (if wiki.boxrights
  then (
    (match readers with 
       | Some r -> Lwt.return r
       | None -> 
           readers_group wiki.id >>= fun r -> 
           Lwt.return [r]) >>= fun readers ->
    (match writers with 
       | Some r -> Lwt.return r
       | None -> 
           writers_group wiki.id >>= fun r -> 
           Lwt.return [r]) >>= fun writers ->
    (match rights_adm with 
       | Some r -> Lwt.return r
       | None -> 
           rights_adm_group wiki.id >>= fun r -> 
           Lwt.return [r]) >>= fun rights_adm ->
    (match wikiboxes_creators with 
       | Some r -> Lwt.return r
       | None -> 
           wikiboxes_creators_group wiki.id >>= fun r -> 
           Lwt.return [r]) >>= fun wikiboxes_creators ->
    Lwt.return (Some (readers, writers, rights_adm, wikiboxes_creators)))
  else Lwt.return None) >>= fun rights ->
  Lwt.catch
    (fun () ->
       (match boxid with
          | None -> 
              wiki.last := Int32.add !(wiki.last) 1l;
              Lwt.return !(wiki.last)
          | Some b -> 
              (* Lwt.catch
                 (fun () -> 
                    Wiki_cache.get_wikibox_data ~wikibox:(wiki.id, b) ()
                    >>= fun _ -> Lwt.fail (Found b))
                 (function
                    | Not_found -> *)
(*VVV not really clean *)
              if Int32.compare !(wiki.last) b >= 0
              then Lwt.fail (Found b)
              else begin
(*VVV may create holes *)
                wiki.last := b;
                Lwt.return b
              end
       )
      >>= fun box ->
      Wiki_sql.new_wikibox
        ~wiki:wiki.id
        ~box
        ~author
        ~comment
        ~content
        ?rights
        ())
    (function Found b -> Lwt.return b | e -> Lwt.fail e)
      

let create_group_ name fullname =
  Users.create_user 
    ~name
    ~pwd:User_sql.Connect_forbidden
    ~fullname
    ~email:None
    ~groups:[]
    ()


let add_to_group_ l g =
  List.fold_left
    (fun beg u -> 
       beg >>= fun () ->
       Users.add_to_group ~user:u ~group:g)
    (Lwt.return ())
    l



let can_change_rights ~sp ~sd wiki id userid =
  if userid == Users.admin.Users.id
  then Lwt.return true
  else
    get_rights_adm ~wiki (wiki.id, id) >>= function
      | Some l -> (* acl are activated *)
          List.fold_left 
            (fun b a -> 
               b >>= fun b ->
               if b then Lwt.return true
               else Users.in_group ~sp ~sd ~user:userid ~group:a ())
            (Lwt.return false) 
            l
      | None -> 
          rights_adm_group wiki.id >>= fun g -> 
          Users.in_group ~sp ~sd ~user:userid ~group:g ()

let can_read ~sp ~sd wiki id userid =
  if userid = Users.admin.Users.id
  then Lwt.return true
  else
    get_readers ~wiki (wiki.id, id) >>= function
      | Some l -> (* acl are activated *)
          List.fold_left 
            (fun b a -> 
               b >>= fun b ->
               if b then Lwt.return true
               else Users.in_group ~sp ~sd ~user:userid ~group:a ())
            (Lwt.return false) 
            l
      | None -> 
          readers_group wiki.id >>= fun g -> 
          Users.in_group ~sp ~sd ~user:userid ~group:g ()
    
let can_write ~sp ~sd wiki id userid =
  if userid = Users.admin.Users.id
  then Lwt.return true
  else
    get_writers (wiki.id, id) >>= function
      | Some l -> (* acl are activated *)
          List.fold_left 
            (fun b a -> 
               b >>= fun b ->
               if b then Lwt.return true
               else Users.in_group ~sp ~sd ~user:userid ~group:a ())
            (Lwt.return false) 
            l
      | None -> 
          writers_group wiki.id >>= fun g -> 
          Users.in_group ~sp ~sd ~user:userid ~group:g ()
    
let can_create_wikibox ~sp ~sd wiki id userid =
  if userid == Users.admin.Users.id
  then Lwt.return true
  else
    get_wikiboxes_creators (wiki.id, id) >>= function
      | Some l -> (* acl are activated *)
          List.fold_left
            (fun b a -> 
               b >>= fun b ->
               if b then Lwt.return true
               else Users.in_group ~sp ~sd ~user:userid ~group:a ())
            (Lwt.return false) 
            l
      | None -> 
          wikiboxes_creators_group wiki.id >>= fun g -> 
          Users.in_group ~sp ~sd ~user:userid ~group:g ()


let get_role_ ~sp ~sd ((wiki : Wiki_sql.wiki), id) =
  get_wiki_by_id wiki >>= fun w ->
  Users.get_user_data sp sd >>= fun u ->
  let u = u.Users.id in
  can_change_rights ~sp ~sd w id u >>= fun cana ->
  if cana
  then Lwt.return Admin
  else
    can_write ~sp ~sd w id u >>= fun canw ->
    if canw
    then Lwt.return Author
    else 
      can_read ~sp ~sd w id u >>= fun canr ->
      if canr
      then Lwt.return Lurker
      else Lwt.return Nonauthorized




(** {2 Session data} *)

module Roles = Map.Make(struct
                          type t = int32 * int32
                          let compare = compare
                        end)

type wiki_sd = 
    {
      role : (int32 * int32) -> role Lwt.t;
    }

let cache_find table f box =
  try 
    Lwt.return (Roles.find box !table)
  with Not_found -> 
    f box >>= fun v ->
    table := Roles.add box v !table;
    Lwt.return v

let default_wiki_sd ~sp ~sd =
  let cache = ref Roles.empty in
  (* We cache the values to retrieve them only once *)
  {role = cache_find cache (get_role_ ~sp ~sd);
  }

(** The polytable key for retrieving wiki data inside session data *)
let wiki_key : wiki_sd Polytables.key = Polytables.make_key ()

let get_wiki_sd ~sp ~sd =
  try
    Polytables.get ~table:sd ~key:wiki_key
  with Not_found -> 
    let wsd = default_wiki_sd ~sp ~sd in
    Polytables.set sd wiki_key wsd;
    wsd




let get_role ~sp ~sd k =
  let wiki_sd = get_wiki_sd ~sp ~sd in
  wiki_sd.role k




(** {2 } *)
let send_static_file sp sd wiki dir page =
  readers_group wiki.id >>= fun g -> 
  Users.get_user_id ~sp ~sd >>= fun userid ->
  Users.in_group ~sp ~sd ~user:userid ~group:g () >>= fun b ->
  if b
  then Eliom_predefmod.Files.send sp (dir^"/"^page)
  else Lwt.fail Eliom_common.Eliom_404


let display_page w wikibox action_create_page sp page () =
  if not w.pages
  then Lwt.fail Eliom_common.Eliom_404
  else
    let sd = Ocsimore_common.get_sd sp in
    (* if there is a static page, we serve it: *)
    Lwt.catch
      (fun () ->
         match w.staticdir with
           | Some d -> send_static_file sp sd w d page
           | None -> Lwt.fail Eliom_common.Eliom_404)
      (function
         | Eliom_common.Eliom_404 ->
             ((* otherwise, we serve the wiki page: *)
             Lwt.catch
               (fun () ->
                  Wiki_cache.get_box_for_page w.id page >>= fun box ->
                  wikibox#editable_wikibox ~sp ~sd ~data:(w.id, box)
(*VVV it does not work if I do not put optional parameters !!?? *)
                    ?rows:None ?cols:None ?classe:None ?subbox:None
                    ?cssmenu:(Some (Some page)) 
                    ~ancestors:Wiki_syntax.no_ancestors
                    () >>= fun subbox -> 
                  Lwt.return {{ [ subbox ] }}
               )
               (function
                  | Not_found -> 
                      Users.get_user_id ~sp ~sd >>= fun userid ->
                      let draw_form name =
                        {{ [<p>[
                               {: Eliom_duce.Xhtml.string_input
                                  ~input_type:{: "hidden" :} 
                                  ~name
                                  ~value:page () :}
                                 {: Eliom_duce.Xhtml.string_input
                                    ~input_type:{: "submit" :} 
                                    ~value:"Create it!" () :}
                             ]] }}
                          
                      in
                      page_creators_group w.id >>= fun creators ->
                      Users.in_group ~sp ~sd ~user:userid ~group:creators ()
                        >>= fun c ->
                      let form =
                        if c
                        then
                          {{ [ {: Eliom_duce.Xhtml.post_form
                                  ~service:action_create_page
                                  ~sp draw_form () :} ] }}
                        else {{ [] }}
                      in
                      Lwt.return
                        {{ [ <p>"That page does not exist." !form ] }}
                        | e -> Lwt.fail e
               )
      >>= fun subbox ->

      match w.container_id with
        | None -> Lwt.fail (Failure "Wiki has no container box")
        | Some container_id ->
            wikibox#editable_wikibox ~sp ~sd ~data:(w.id, container_id)
              ?rows:None ?cols:None ?classe:None
              ?subbox:(Some subbox) ?cssmenu:(Some None)
              ~ancestors:Wiki_syntax.no_ancestors
              ()
            >>= fun pagecontent ->

            wikibox#get_css_header ~sp ~wiki:w.id 
              ?admin:(Some false) ?page:(Some page) ()

            >>= fun css ->
            let title = Ocamlduce.Utf8.make w.title in
            Eliom_duce.Xhtml.send
              sp
              {{
                 <html>[
                   <head>[
                     <title>title
                       !css
    (*VVV quel titre ? quel layout de page ? *)
                   ]
                   <body>[ pagecontent ]
                 ]
               }}
             )
         | e -> Lwt.fail e)


let create_wiki ~title ~descr
    ?sp
    ?path
    ?(readers = [Users.anonymous.Users.id])
    ?(writers = [Users.authenticated_users.Users.id])
    ?(rights_adm = [])
    ?(wikiboxes_creators = [Users.authenticated_users.Users.id])
    ?(container_adm = [])
    ?(page_creators = [Users.authenticated_users.Users.id])
    ?(css_editors = [Users.authenticated_users.Users.id])
    ?(admins = [])
    ?(boxrights = true)
    ?staticdir
    ~wikibox
    () =
  Lwt.catch 
    (fun () -> get_wiki_by_name title)
    (function
       | Not_found -> 
           (Wiki_sql.new_wiki ~title ~descr ~pages:(not (path = None))
              ~boxrights ~staticdir ()
           >>= fun wiki_id -> 
           
           (* Creating groups *)
           create_group_
             (readers_group_name wiki_id) 
             ("Users who can read wiki "^Int32.to_string wiki_id)
           >>= fun readers_data ->
           create_group_
             (writers_group_name wiki_id) 
             ("Users who can write in wiki "^Int32.to_string wiki_id)
           >>= fun writers_data ->
           create_group_
             (rights_adm_group_name wiki_id) 
             ("Users who can change rights in wiki "^Int32.to_string wiki_id)
           >>= fun rights_adm_data ->
           create_group_
             (page_creators_group_name wiki_id) 
             ("Users who can create pages in wiki "^Int32.to_string wiki_id)
           >>= fun page_creators_data ->
           create_group_
             (css_editors_group_name wiki_id) 
             ("Users who can edit css for wikipages of wiki "^Int32.to_string wiki_id)
           >>= fun css_editors_data ->
           create_group_
             (wikiboxes_creators_group_name wiki_id) 
             ("Users who can create wikiboxes in wiki "^Int32.to_string wiki_id)
           >>= fun wikiboxes_creators_data ->
           create_group_
             (container_adm_group_name wiki_id)
             ("Users who can change the layout of pages "^Int32.to_string wiki_id)
           >>= fun container_adm_data ->
           create_group_
             (admin_group_name wiki_id) 
             ("Wiki administrator "^Int32.to_string wiki_id)
           >>= fun admin_data ->

           (* Putting users in groups *)
           add_to_group_ [admin_data.Users.id] 
             wikiboxes_creators_data.Users.id
             >>= fun () ->
           add_to_group_ [admin_data.Users.id] 
             page_creators_data.Users.id
             >>= fun () ->
           add_to_group_ [admin_data.Users.id] 
             css_editors_data.Users.id
             >>= fun () ->
           add_to_group_ [admin_data.Users.id] 
             rights_adm_data.Users.id
             >>= fun () ->
           add_to_group_ [admin_data.Users.id] 
             container_adm_data.Users.id
             >>= fun () ->
           add_to_group_ [wikiboxes_creators_data.Users.id;
                          page_creators_data.Users.id;
                          css_editors_data.Users.id;
                          rights_adm_data.Users.id;
                          container_adm_data.Users.id] 
             writers_data.Users.id
             >>= fun () ->
           add_to_group_ [writers_data.Users.id] readers_data.Users.id
             >>= fun () ->
           add_to_group_ readers readers_data.Users.id >>= fun () ->
           add_to_group_ writers writers_data.Users.id >>= fun () ->
           add_to_group_ rights_adm rights_adm_data.Users.id >>= fun () ->
           add_to_group_ page_creators page_creators_data.Users.id >>= fun () ->
           add_to_group_ css_editors css_editors_data.Users.id >>= fun () ->
           add_to_group_ wikiboxes_creators wikiboxes_creators_data.Users.id
           >>= fun () ->

           get_wiki_by_id wiki_id >>= fun wiki ->


           (* Filling a wikibox with wikipage container *)
           new_wikibox 
             ~wiki
             ~author:Users.admin.Users.id
             ~comment:"Wikipage" 
             ~content:"= Ocsimore wikipage\r\n\r\n<<loginbox>>\r\n\r\n<<content>>"
             ~writers:[container_adm_data.Users.id]
             ()
           >>= fun container_id ->

           Wiki_cache.update_wiki ~wiki_id:wiki.id ~container_id ()
           >>= fun () ->

           Lwt.return {wiki with
                         container_id = Some container_id})

       | e -> Lwt.fail e)
  >>= fun w ->



  (* *** Wikipages *** *)
  (match path with
     | None -> ()
     | Some path ->

         let action_create_page =
           Eliom_predefmod.Actions.register_new_post_service' 
             ~name:("wiki_page_create"^Int32.to_string w.id)
             ~post_params:(Eliom_parameters.string "page")
             (fun sp () page ->
                let sd = Ocsimore_common.get_sd sp in
                Users.get_user_id ~sp ~sd >>= fun userid ->
                page_creators_group w.id >>= fun creators ->
                Users.in_group ~sp ~sd ~user:userid ~group:creators ()
                  >>= fun c ->
                if c
                then
                  Lwt.catch
                    (fun () -> 
                       Wiki_cache.get_box_for_page w.id page >>= fun _ ->
                       (* The page already exists *)
                       Lwt.return [Ocsimore_common.Session_data sd]
(*VVV Put an error message *)                     
                    )
                    (function 
                       | Not_found ->
                           new_wikibox 
                             w
                             userid
                             "new wikipage" 
                             ("=="^page^"==")
(*VVV readers, writers, rights_adm, wikiboxes_creators? *)
                             () >>= fun box ->
                           Wiki_cache.set_box_for_page
                             ~wiki:w.id ~id:box ~page >>= fun () ->
                           Lwt.return [Ocsimore_common.Session_data sd]
                       | e -> Lwt.fail e)
                else Lwt.return [Ocsimore_common.Session_data sd]
(*VVV Put an error message *)
                  )
         in


         
         (* Registering the service with suffix for wikipages *)
         (* Note that Eliom will look for the service corresponding to
            the longest prefix. Thus it is possible to register a wiki
            at URL / and another one at URL /wiki and it works,
            whatever be the order of registration *)
         let servpage =
           Eliom_predefmod.Any.register_new_service
             ~path
             ?sp
             ~get_params:(Eliom_parameters.suffix 
                            (Eliom_parameters.all_suffix "page"))
             (fun sp path () ->
                display_page w wikibox action_create_page sp 
                  (Ocsigen_lib.string_of_url_path path) ())
         in Wiki_syntax.add_servpage w.id servpage;

         (* the same, but non attached: *)
         let naservpage =
           Eliom_predefmod.Any.register_new_service'
             ~name:("display"^Int32.to_string w.id)
             ?sp
             ~get_params:(Eliom_parameters.string "page")
             (fun sp path () ->
                let path =
                  Ocsigen_lib.string_of_url_path
                    (Ocsigen_lib.remove_slash_at_beginning
                       (Ocsigen_lib.remove_dotdot (Neturl.split_path path)))
                in
                display_page w wikibox action_create_page sp path ())
         in Wiki_syntax.add_naservpage w.id naservpage;


  );
  Lwt.return w







(** {2 } *)
type wiki_errors =
  | Action_failed of exn
  | Operation_not_allowed

type wiki_action_info =
  | Edit_box of (int32 * int32)
  | Edit_perm of (int32 * int32)
  | Preview of ((int32 * int32) * string)
  | History of ((int32 * int32) * (int option * int option))
  | Oldversion of ((int32 * int32) * int32)
  | Src of ((int32 * int32) * int32)
  | Error of ((int32 * int32) * wiki_errors)

exception Wiki_action_info of wiki_action_info

let save_wikibox ~sp ~sd (((wiki_id, box_id) as d), content) =
  get_role sp sd d >>= fun role ->
  match role with
    | Admin
    | Author ->
        Lwt.catch
          (fun () ->
              Users.get_user_data sp sd >>= fun user ->
              Wiki_cache.update_wikibox
                wiki_id box_id
                user.Users.id
                "" content >>= fun _ ->
              Lwt.return [Ocsimore_common.Session_data sd])
          (fun e -> 
             Lwt.return 
               [Ocsimore_common.Session_data sd;
                Wiki_action_info (Error (d, Action_failed e))])
    | _ -> Lwt.return [Ocsimore_common.Session_data sd;
                       Wiki_action_info (Error (d, Operation_not_allowed))]


let save_wikibox_permissions ~sp ~sd (((wiki_id, box_id) as d), rights) =
  get_role sp sd d >>= fun role ->
  (match role with
    | Admin ->
        let (addr, (addw, (adda, (addc, 
                                  (delr, (delw, (dela, delc))))))) = rights in
        Users.group_list_of_string addr >>= fun readers ->
        Wiki_cache.populate_readers wiki_id box_id readers >>= fun () ->
        Users.group_list_of_string addw >>= fun w ->
        Wiki_cache.populate_writers wiki_id box_id w >>= fun () ->
        Users.group_list_of_string adda >>= fun a ->
        Wiki_cache.populate_rights_adm wiki_id box_id a >>= fun () ->
        Users.group_list_of_string addc >>= fun a ->
        Wiki_cache.populate_wikiboxes_creators wiki_id box_id a >>= fun () ->
        Users.group_list_of_string delr >>= fun readers ->
        Wiki_cache.remove_readers wiki_id box_id readers >>= fun () ->
        Users.group_list_of_string delw >>= fun w ->
        Wiki_cache.remove_writers wiki_id box_id w >>= fun () ->
        Users.group_list_of_string dela >>= fun a ->
        Wiki_cache.remove_rights_adm wiki_id box_id a >>= fun () ->
        Users.group_list_of_string delc >>= fun a ->
        Wiki_cache.remove_wikiboxes_creators wiki_id box_id a
    | _ -> Lwt.return ()) >>= fun () ->
(*  Lwt.return [Ocsimore_common.Session_data sd] NO! We want a new sd, or at least, remove role *)
  Lwt.return []

