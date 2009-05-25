(* Ocsimore
 * Copyright (C) 2008
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
   @author Boris Yakobowski
   @author Vincent Balat
*)

open User_sql.Types


(** Semi-abstract type for a wiki *)
type wiki_arg = [ `Wiki ]
type wiki = wiki_arg Opaque.int32_t

(** Conversions from a wiki index *)
val string_of_wiki : wiki -> string
val wiki_of_string : string -> wiki
val sql_of_wiki : wiki -> int32
val wiki_of_sql : int32 -> wiki

type wikibox_arg = [ `Wikibox ]
type wikibox_id = int32
type wikibox = wiki * wikibox_id
type wikibox_uid = wikibox_arg Opaque.int32_t

val sql_of_wikibox_uid : wikibox_uid -> int32
val wikibox_uid_of_sql : int32 -> wikibox_uid

type wikipage = wiki * string

type wikipage_arg = [ `Wikipage ]
type wikipage_uid = wikipage_arg Opaque.int32_t

type wiki_model
type content_type
val string_of_wiki_model : wiki_model -> string
val wiki_model_of_string : string -> wiki_model
val string_of_content_type : content_type -> string
val content_type_of_string : string -> content_type

(** Fields for a wiki *)
type wiki_info = {
  wiki_id : wiki;
  wiki_title : string;
  wiki_descr : string;
  wiki_pages : string option;
  wiki_boxrights : bool;
  wiki_container : wikibox_id;
  wiki_staticdir : string option (** if static dir is given,
                                ocsimore will serve static pages if present,
                                instead of wiki pages *);
  wiki_model : wiki_model;
}

type wikipage_info = {
  wikipage_source_wiki: wiki;
  wikipage_page: string;
  wikipage_dest_wiki: wiki;
  wikipage_wikibox: wikibox_id;
  wikipage_title: string option;
  wikipage_uid: wikipage_uid;
}

type wikibox_info = {
  wikibox_id : wikibox;
  wikibox_uid: wikibox_uid;
  wikibox_comment: string option;
  wikibox_special_rights: bool;
}

type 'a rights_aux = sp:Eliom_sessions.server_params -> 'a -> bool Lwt.t

class type wiki_rights =
object
  method can_admin_wiki :          wiki rights_aux
  method can_create_genwikiboxes : wiki rights_aux
  method can_create_subwikiboxes : wiki rights_aux
  method can_create_wikicss :      wiki rights_aux
  method can_create_wikipages :    wiki rights_aux
  method can_delete_wikiboxes :    wiki rights_aux

  method can_admin_wikibox : wikibox rights_aux
  method can_set_wikibox_specific_permissions : wikibox rights_aux
  method can_write_wikibox : wikibox rights_aux
  method can_read_wikibox : wikibox rights_aux

  method can_create_wikipagecss : wikipage rights_aux
end


(** Content of a wikibox. The second field is the actual content. It is [None]
    if the wikibox has been deleted. The third field is the version id *)
type wikibox_content = content_type * string option * int32