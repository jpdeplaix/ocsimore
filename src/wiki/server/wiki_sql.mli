(* Ocsimore
 * Copyright (C) 2009
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
open Wiki_types



(** Exception raised when a CSS does not exists *)
exception Unknown_Css of wikibox



val wikis :
  (< boxrights : < get : unit; nul : Sql.non_nullable; t : Sql.bool_t > Sql.t;
   container : < get : unit; nul : Sql.nullable; t : Sql.int32_t > Sql.t;
   deleted : < get : unit; nul : Sql.non_nullable; t : Sql.bool_t > Sql.t;
   descr : < get : unit; nul : Sql.non_nullable; t : Sql.string_t > Sql.t;
   id : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t > Sql.t;
   model : < get : unit; nul : Sql.non_nullable; t : Sql.string_t > Sql.t;
   pages : < get : unit; nul : Sql.nullable; t : Sql.string_t > Sql.t;
   siteid : < get : unit; nul : Sql.nullable; t : Sql.string_t > Sql.t;
   staticdir : < get : unit; nul : Sql.nullable; t : Sql.string_t > Sql.t;
   title : < get : unit; nul : Sql.non_nullable; t : Sql.string_t > Sql.t >,
   < deleted : < nul : Sql.non_nullable; t : Sql.bool_t > Sql.t;
   descr : < nul : Sql.non_nullable; t : Sql.string_t > Sql.t;
   id : < nul : Sql.non_nullable; t : Sql.int32_t > Sql.t;
   model : < nul : Sql.non_nullable; t : Sql.string_t > Sql.t;
   title : < nul : Sql.non_nullable; t : Sql.string_t > Sql.t >
     Sql.writable)
           Sql.view

(** inserts a new wiki, creating on the fly the container wikibox
    (which is returned along the index of the new wiki). The [author]
    argument is used when creating the wikibox for the container. *)
val new_wiki :
  ?db: Ocsi_sql.db_t ->
  title:string ->
  descr:string ->
  pages:string option ->
  boxrights:bool ->
  staticdir:string option ->
  ?container_text:string ->
  author:userid ->
  model:Wiki_types.wiki_model ->
  unit ->
  (wiki * wikibox option) Lwt.t

(** Delete or undelete the wiki. Does not delete anything in the database *)
val delete_wiki : ?delete:bool -> wiki -> unit Lwt.t

(** Inserts a new wikibox in an existing wiki and return the id of the
    wikibox. *)
val new_wikibox :
  ?db: Ocsi_sql.db_t ->
  wiki:wiki ->
  author:userid ->
  comment:string ->
  content:string ->
  content_type:'a Wiki_types.content_type ->
  unit ->
  wikibox Lwt.t

(** return the history of a wikibox. *)
val get_wikibox_history :
  wb:Wiki_types.wikibox ->
  < author : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t > Sql.t;
 comment : < get : unit; nul : Sql.non_nullable; t : Sql.string_t > Sql.t;
 datetime : < get : unit; nul : Sql.non_nullable; t : Sql.timestamp_t > Sql.t;
 version : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t > Sql.t >
   list Lwt.t

val get_wikiboxes_by_wiki : wiki -> wikibox list Lwt.t
(* val get_wikiboxes_by_wiki' : wiki -> (wikibox_info, wikibox_content) list Lwt.t *)

(** Wikipages *)

(** Links the wikibox [wb] to the page [page] of wiki [wiki]. Fails
    if there already exists a wikibox linked to this wikipage *)
val create_wikipage :
  ?db: Ocsi_sql.db_t ->
  wiki:wiki ->
  page:string ->
  wb:wikibox ->
  unit Lwt.t

(** return the information for a wikipage *)
val get_wikipage_info : wiki:wiki -> page:string -> wikipage_info Lwt.t

(** Sets the info for a wikipage. All parameters not passed are left
    unchanged. If [title] is [Some ""], it will be set to NULL
    (just as if it is [None]). If [wb] is [None], the page is deleted.
*)
val set_wikipage_properties :
  ?db: Ocsi_sql.db_t ->
  wiki:wiki ->
  page:string ->
  ?title:string ->
  ?newpage:string ->
  ?wb:wikibox option ->
  unit -> unit Lwt.t



(** returns the lists of css associated to a wikipage or a wiki, together
    with the content of the wikibox and the version (as last arguments) *)
val get_css_for_wikipage : wiki:wiki -> page:string ->
  (Wiki_types.css_wikibox * (string * int32)) list Lwt.t
val get_css_for_wiki : wiki:wiki ->
  (Wiki_types.css_wikibox * (string * int32)) list Lwt.t

(** Add a new CSS to a wikipage or a wiki. If [wbcss] is supplied,
    a link to the (supposed existing) CSS is created, and [author]
    and [content] are ignored. Otherwise, a new wikibox is created.
    In both cases, the wikibox containing the CSS is returned.
*)
val add_css_aux:
  ?db: Ocsi_sql.db_t ->
  wiki:wiki ->
  page:string option ->
  author:userid ->
  media:media_type ->
(*  ?content:string -> *)
  ?wbcss:wikibox ->
  unit ->
  wikibox Lwt.t

val remove_css_wiki :
  ?db: Ocsi_sql.db_t ->
  wiki:wiki ->
  wikibox ->
  unit Lwt.t

val remove_css_wikipage :
  ?db: Ocsi_sql.db_t ->
  wiki:wiki ->
  page:string ->
  wikibox ->
  unit Lwt.t


(** returns the wikibox for the css of a page or [None] if the page has no css*)
val get_css_wikibox_for_wikipage :
  wiki:wiki -> page:string -> Wiki_types.css_wikibox list Lwt.t

(** returns the wikibox for the global css of a wiki, or [None] if the wiki
    has no such css *)
val get_css_wikibox_for_wiki : wiki:wiki -> Wiki_types.css_wikibox list Lwt.t


val update_css_wikibox_aux:
  ?db: Ocsi_sql.db_t ->
  wiki:wiki ->
  page:string option ->
  oldwb:wikibox ->
  newwb:wikibox ->
  media:media_type ->
  rank:int32 ->
  unit ->
  unit Lwt.t


(** Find wiki information for a wiki, given its id *)
val get_wiki_info_by_id : id:wiki -> wiki_info Lwt.t

(** Find wiki information for a wiki, given its name *)
val get_wiki_info_by_name : name:string -> wiki_info Lwt.t

(** Find wiki information for a wiki, given its pages *)
val get_wiki_info_by_pages : pages:string -> wiki_info Lwt.t

(** looks for a wikibox and returns [Some (comment, author, content, datetime,
    content_type, version)], or [None] if the page doesn't exist. *)
val get_wikibox_content :
  ?version:int32 ->
  wikibox ->
  (string * userid * string option * CalendarLib.Calendar.t * 'a Wiki_types.content_type * int32) option Lwt.t

val get_wikis : unit -> wiki list Lwt.t

(** Does the wikibox have special permission rights *)
val set_wikibox_special_rights:
  ?db: Ocsi_sql.db_t ->
  wb:wikibox ->
  bool ->
  unit Lwt.t


(** Wiki in which the wikibox currently resides *)
val wikibox_wiki: wikibox -> wiki Lwt.t


(** Current revision number of a wikibox *)
val current_wikibox_version :
  wikibox -> Int32.t option Lwt.t


(** Inserts a new version of an existing wikibox in a wiki
    and return its version number. *)
val update_wikibox :
  ?db: Ocsi_sql.db_t ->
  old_version:int32 ->
  author:userid ->
  comment:string ->
  content:string option ->
  content_type:'a Wiki_types.content_type ->
  ?ip:string ->
  wikibox ->
  int32 Lwt.t

(** Update the information of a wiki. All arguments not passed are left
    unchanged *)
val update_wiki :
  ?db: Ocsi_sql.db_t ->
  ?container:wikibox option ->
  ?staticdir:string option ->
  ?path:string option ->
  ?descr:string ->
  ?boxrights:bool ->
  ?model:wiki_model ->
  ?siteid:string option ->
  wiki -> unit Lwt.t


(** Iterator on all the wikis  *)
val iter_wikis :
  ?db: Ocsi_sql.db_t ->
  ?deleted:bool ->
  (wiki_info -> unit Lwt.t) ->
  unit Lwt.t

val get_wikibox_info : wikibox -> wikibox_info Lwt.t


(** This function updates the content of all the wikiboxes stored in
    the database (including the old versions) according to the function
    passed as argument, which must return the updated content, or None *)
val update_wikiboxes :
  ?db: Ocsi_sql.db_t ->
  (wikibox:wikibox ->
   version:int32 ->
   content:string option ->
   content_type:'a content_type ->
   string option Lwt.t) ->
  unit Lwt.t


val rewrite_wikipages :
  ?db: Ocsi_sql.db_t ->
  oldwiki:wiki ->
  newwiki:wiki ->
  path:string ->
  unit Lwt.t

val get_wikipages_of_a_wiki :
  wiki:wiki ->
  unit ->
  < pagename : < get : unit; nul : Sql.non_nullable; t : Sql.string_t >
    Sql.t;
 title : < get : unit; nul : Sql.nullable; t : Sql.string_t >
   Sql.t;
 uid : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t >
   Sql.t;
 wiki : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t >
   Sql.t;
 wikibox : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t >
   Sql.t >
   list Lwt.t

val get_wikis_id : unit ->
  < id : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t > Sql.t;
 title : < get : unit; nul : Sql.nullable; t : Sql.string_t > Sql.t >
   list Lwt.t
val get_wikiboxes_id : unit ->
  < id : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t > Sql.t;
 title : < get : unit; nul : Sql.nullable; t : Sql.string_t > Sql.t >
   list Lwt.t
val get_wikipages_id : unit ->
  < id : < get : unit; nul : Sql.non_nullable; t : Sql.int32_t > Sql.t;
 title : < get : unit; nul : Sql.nullable; t : Sql.string_t > Sql.t >
   list Lwt.t
