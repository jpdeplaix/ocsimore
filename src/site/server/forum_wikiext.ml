(* Ocsimore
 * Copyright (C) 2009
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
   Provides a function to register the wikicreole extensions for forums.
   @author Vincent Balat
   @author Boris Yakobowski
*)

open Eliom_content


(** This function registers the following wiki extensions:
     - [<<forum_message>>]
     - [<<forum_thread>>]
     - [<<forum_message_list>>]
     - [<<forum_threads_list>>]
  *)
let register_wikiext
    ((message_widget : Forum_widgets.message_widget),
     (thread_widget : Forum_widgets.thread_widget),
     (message_list_widget : Forum_widgets.message_list_widget),
     (threads_list_widget : Forum_widgets.threads_list_widget)) =
  let f_forum_message _ args content =
    `Flow5
      (let classes =
         try Some [List.assoc "class" args]
         with Not_found -> None
       in
       try
         let message_id =
              Forum_types.message_of_string (List.assoc "message" args)
         in
         lwt c = message_widget#display
                ?classes
                ~data:message_id ()
         in
         Lwt.return [c]
       with Not_found | Failure _ ->
         let s = Wiki_syntax.string_of_extension "raw" args content in
         Lwt.return [Html5.F.b [Html5.F.pcdata s]]
      )
  in
  Wiki_syntax.register_simple_flow_extension
    ~name:"forum_message" ~reduced:false f_forum_message;

  let f_forum_thread _ args content =
    `Flow5
      (let classes =
         try Some [List.assoc "class" args]
         with Not_found -> None
       in
       let rows =
         try Some (int_of_string (List.assoc "rows" args))
         with Not_found | Failure _ -> None
       in
       let cols =
         try Some (int_of_string (List.assoc "cols" args))
         with Not_found | Failure _ -> None
       in
       try
         let message_id =
           Forum_types.message_of_string (List.assoc "message" args)
         in
         lwt c = thread_widget#display ?commentable:(Some true)
           ?rows ?cols ?classes
           ~data:message_id () in
         Lwt.return [c]
       with Not_found | Failure _ ->
         let s = Wiki_syntax.string_of_extension "raw" args content in
         Lwt.return [Html5.F.b [Html5.F.pcdata s]]
      ) in


  Wiki_syntax.register_simple_flow_extension
    ~name:"forum_thread" ~reduced:false f_forum_thread;

  let f_forum_message_list _ args content =
    `Flow5
      (let classes =
         try Some [List.assoc "class" args]
         with Not_found -> None
       in
       let rows =
         try Some (int_of_string (List.assoc "rows" args))
         with Not_found | Failure _ -> None
       in
       let cols =
         try Some (int_of_string (List.assoc "cols" args))
         with Not_found | Failure _ -> None
       in
       let first =
         try Int64.of_string (List.assoc "first" args)
         with Not_found | Failure _ -> 1L
       in
       let number =
         try Int64.of_string (List.assoc "number" args)
         with Not_found | Failure _ -> 1000L
       in
       let add_message_form =
         Some
           (try match List.assoc "addform" args with
             | "false" -> false
             | _ -> true
            with Not_found -> true)
       in
       try
         let forum =
           Forum_types.forum_of_string (List.assoc "forum" args)
         in
         lwt c = message_list_widget#display
           ?rows ?cols ?classes
           ~forum  ~first ~number
           ?add_message_form () in
         Lwt.return [c]
       with Not_found | Failure _ ->
         let s = Wiki_syntax.string_of_extension "raw" args content in
         Lwt.return [Html5.F.b [Html5.F.pcdata s]]
      )
  in
  Wiki_syntax.register_simple_flow_extension
    ~name:"forum_message_list" ~reduced:false f_forum_message_list;

  let f_forum_threads_list _ args content =
    `Flow5
      (let classes =
         try Some [List.assoc "class" args]
         with Not_found -> None
       in
       let rows =
         try Some (int_of_string (List.assoc "rows" args))
         with Not_found | Failure _ -> None
       in
       let cols =
         try Some (int_of_string (List.assoc "cols" args))
         with Not_found | Failure _ -> None
       in
       let first =
         try Int64.of_string (List.assoc "first" args)
         with Not_found | Failure _ -> 1L
       in
       let number =
         try Int64.of_string (List.assoc "number" args)
         with Not_found | Failure _ -> 1000L
       in
       let add_message_form =
         Some
           (try match List.assoc "addform" args with
             | "false" -> false
             | _ -> true
            with Not_found -> true)
       in
       try
         let forum =
           Forum_types.forum_of_string (List.assoc "forum" args)
         in
         lwt c = threads_list_widget#display
           ?rows ?cols ?classes
           ~forum ~first ~number
           ?add_message_form () in
         Lwt.return [c]
       with Not_found | Failure _ ->
         let s = Wiki_syntax.string_of_extension "raw" args content in
         Lwt.return [Html5.F.b [Html5.F.pcdata s]]
      )
  in
  Wiki_syntax.register_simple_flow_extension
    ~name:"forum_threads_list" ~reduced:false f_forum_threads_list
