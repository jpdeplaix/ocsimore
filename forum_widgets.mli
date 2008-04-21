open Lwt
open Eliommod
open Eliom_parameters
open Eliom_services
open Eliom_duce
open Ocsimorelib
open CalendarLib
open Session_manager
open Widget

(**
This module contains forum widgets for use with the {!Forum.forum} class

@author Jaap Boender
*)

type message_data =
{
	id: Forum_sql.forum;
	text: string;
	author: string;
	datetime: Calendar.t;
	hidden: bool;
}

class message_toggle_action: parent:sessionmanager ->
object
	inherit [Forum_sql.forum * int32] parametrized_widget
end;;
class message_list_widget : parent:sessionmanager ->
object
  inherit [message_data] list_widget
  inherit [Forum_sql.forum * int32 * int64 option * int64 option] 
    parametrized_widget
end;;

class message_navigation_widget : 
  parent:sessionmanager -> 
      srv_thread:(int32 * (int32 * int64 option), 
                  unit, 
                  get_service_kind,
                  [`WithoutSuffix],
                  [`One of int32] param_name *
                    ([`One of int32] param_name * [`Opt of int64] param_name),
                  unit,
                  [`Registrable]) service ->
object
  inherit [Forum_sql.forum * int32 * int64 option * int64 option] 
    parametrized_widget
end;;

class message_forest_widget : 
  parent:sessionmanager -> 
      srv_reply_message:(int32 * (int32 * (int32 option * int32)), 
                         unit,
                         get_service_kind,
                         [`WithoutSuffix],
                         [`One of int32] param_name *
                           ([`One of int32] param_name * 
                              ([`Opt of int32] param_name *
                                 [`One of int32] param_name)), 
                         unit, [`Registrable]) service -> 
      srv_message_toggle:(int32 * (int32 * int32 option), 
                          int32,
                          post_service_kind,
                          [ `WithoutSuffix ], 
                          [ `One of int32 ] param_name * 
                            ([ `One of int32 ] param_name *
                               [ `Opt of int32 ] param_name), 
                          [`One of int32] param_name,
                          [ `Registrable ]) service ->
object
  inherit [Forum_sql.forum * int32 * int32 option] parametrized_widget	
    
  method get_children: message_data Ocsimorelib.tree list
    
  method set_children: message_data Ocsimorelib.tree list -> unit
end;;

class message_form_widget: 
  parent:sessionmanager -> 
      srv_add_message: (int32 * (int32 * int32 option), string * (int32 option * bool), post_service_kind, [`WithoutSuffix], [`One of int32] param_name * ([`One of int32] param_name * [`Opt of int32] param_name), [`One of string] param_name * ([`Opt of int32] param_name * [`One of bool] param_name), [`Registrable]) service ->
object
	inherit [Forum_sql.forum * int32 * int32 option * int32 option] parametrized_widget
end;;

class message_add_action: parent:sessionmanager ->
object
	inherit [Forum_sql.forum * int32 * int32 option * string * bool] parametrized_widget
end;;

class latest_messages_widget: parent:sessionmanager ->
object
	inherit [int64] parametrized_widget
end;;

type thread_data =
{
	id: Forum_sql.forum;
	subject: string;
	author: string;
	datetime: Calendar.t
}

class thread_widget: 
  parent:sessionmanager -> 
      srv_thread_toggle:(int32 * (int32 * int32 option), 
                         unit, 
                         post_service_kind, 
                         [`WithoutSuffix], 
                         [`One of int32] param_name * 
                           ([`One of int32] param_name * 
                              [`Opt of int32] param_name), 
                         unit, [`Registrable]) service -> 
object
  inherit [Forum_sql.forum * int32] parametrized_widget
    
  (** Set the thread subject *)
  method set_subject: string -> unit
    
  (** Set the tread author *)
  method set_author: string -> unit
    
  (**
     Set the thread article. What we call an article is a special sort of message
     in a thread that can only be specified when creating the tread; this is for
     example useful if the thread contains a news article that can be reacted
     upon.
  *)
  method set_article: string -> unit
    
  (** Set the thread date and time *)
  method set_datetime: Calendar.t -> unit
    
  (**
     Indicate whether the thread is hidden (if not, individual messages can
     still be hidden)
  *)
  method set_hidden: bool -> unit
    
  (** Set the number of shown messages *)
  method set_shown_messages: int64 -> unit
    
  (** Set the number of hidden messages *)
  method set_hidden_messages: int64 -> unit
    
  (** Get the thread subject *)
  method get_subject: string
    
  (** Get the thread author *)
  method get_author: string
    
  (** Get the thread's article (if applicable) *)
  method get_article: string option
    
  (** Get the thread creation time *)
  method get_datetime: Calendar.t
    
  (** Query whether the thread is hidden *)
  method get_hidden: bool
    
  (** Get the number of shown messages in the thread *)
  method get_shown_messages: int64
    
  (** Get the number of shown messages in the thread *)
  method get_hidden_messages: int64
end;;

class thread_toggle_action: parent:sessionmanager ->
object
	inherit [Forum_sql.forum * int32] parametrized_widget
end;;

class thread_list_widget: 
  parent:sessionmanager -> 
      srv_thread: (int32 * (int32 * int32 option), 
                   unit, 
                   get_service_kind, 
                   [`WithoutSuffix], 
                   [`One of int32] param_name * 
                     ([`One of int32] param_name * 
                        [`Opt of int32] param_name), 
                   unit, 
                   [`Registrable]) service ->
object
	inherit [thread_data] list_widget
	inherit [Forum_sql.forum] parametrized_widget 
end;;

class thread_form_widget: 
  parent: sessionmanager -> 
      srv_add_thread: (int32, 
                       bool * (string * string), 
                       post_service_kind,
                       [`WithoutSuffix], 
                       [`One of int32] param_name, 
                       [`One of bool] param_name *
                         ([`One of string] param_name *
                            [`One of string] param_name),
                       [`Registrable]) service -> 
object
	inherit [Forum_sql.forum] parametrized_widget
end;;

class thread_add_action: parent:sessionmanager ->
object
	inherit [Forum_sql.forum * bool * string * string] parametrized_widget
end;;

type forum_data =
{
	id: Forum_sql.forum;
	name: string;
	description: string;
	moderated: bool;
	arborescent: bool;
};;

class forums_list_widget: 
  parent:sessionmanager -> 
    srv_forum:(int32, 
               unit, 
               get_service_kind,
               [`WithoutSuffix], 
               [`One of int32] param_name, 
               unit, [`Registrable]) service ->
object
  inherit [unit] parametrized_widget
  inherit [forum_data] list_widget
end;;

class forum_form_widget: parent: sessionmanager -> srv_add_forum: (unit, string * (string * (string * (bool * bool))), post_service_kind, [`WithoutSuffix], unit, [`One of string] param_name * ([`One of string] param_name * ([`One of string] param_name * ([`One of bool] param_name * [`One of bool] param_name))), [`Registrable]) service -> 
object
	inherit [unit] parametrized_widget
end;;

class forum_add_action: parent:sessionmanager ->
object
	inherit [string * string * string * bool * bool] parametrized_widget
end;;


(*
(** A parametrized_widget that displays one message *)
class message_widget: parent:sessionmanager -> srv_message_toggle:unit -> 
object
  inherit [Forum_sql.forum * int32] parametrized_widget
    
  (** Set the message subject *)
  method set_subject: string -> unit
    
  (** Set the message author *)
  method set_author: string -> unit
    
  (** Set the message contents *)
  method set_text: string -> unit
    
  (** Set the message date and time *)
  method set_datetime: Calendar.t -> unit
    
  (** Indicate whether the message is hidden *)
  method set_hidden: bool -> unit
    
  (** Indicate whether the message is sticky *)
  method set_sticky: bool -> unit
end;;

*)
