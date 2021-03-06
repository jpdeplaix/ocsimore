open Eliom_lib
open Eliom_content
open Lwt


      (* USEFUL STUFF *)

      (* these operators allow to write something like this:
         list_item_1 ^:
         false % list_item_2 ^?
         true % list_item_3 ^?
         false % list_item_4 ^?
         list_item_5 ^:
         []
         which evaluates to [list_item_1; list_item_3; list_item_5]. *)
let ( ^? ) (cond, x) xs = if cond then x::xs else xs (* right assoc *)
let ( ^: ) x xs = x :: xs (* right assoc, same precedence of ^? *)
let ( % ) x y = x,y  (* left assoc, higher precedence *)

let ( |- ) f g = fun x -> g (f x)
let ( -| ) f g = fun x -> f (g x)
let ( **> ) f x = f x
let ( |> ) x f = f x

let eliom_inline_class = Html5.F.a_class ["eliom_inline"]
let accept_charset_utf8 = Html5.F.a_accept_charset ["utf-8"]
let unopt_str = function | None -> "" | Some s -> s

let iter_option f o = match o with None -> () | Some x -> f x
let some x = Some x
let get_opt ~default = function Some x -> x | None -> default

let flip f b a = f a b

let list_singleton x = [x]
let cons x xs = x :: xs

let fresh_id =
  let counter = ref 0 in
  fun ?(prefix="id_") () ->
    prefix^string_of_int (incr counter; !counter)

type 'a tree = Node of 'a * ('a tree list);;

    (* A user defined parameter type *)
(* let id p = user_type Sql.db_int_of_string Sql.string_of_db_int p  *)
(* let int64 p = user_type Int64.of_string Int64.to_string p *)

let rec lwt_tree_map (f: 'a -> 'b Lwt.t) (tree: 'a tree): 'b tree Lwt.t =
let Node (p, cs) = tree in
  f p >>=
        fun start -> lwt_forest_map f cs >>=
        fun rest -> return (Node (start, rest))
and lwt_forest_map (f: 'a -> 'b Lwt.t) (forest: 'a tree list): 'b tree list Lwt.t =
        Lwt_list.map_p (fun t -> lwt_tree_map f t) forest

let rec lwt_flatten (l: 'a list list): 'a list Lwt.t =
  match l with
  | [] -> return []
  | h :: t ->
      lwt_flatten t >>=
        fun ft -> return (List.append h ft);;

let lwt_sequence : 'a Lwt.t list -> 'a list Lwt.t =
  fun lwt_li ->
    let rec aux sofar = function
      | [] -> Lwt.return (List.rev sofar)
      | x :: xs ->
          x >>= fun x -> aux (x :: sofar) xs
    in aux [] lwt_li

let eref_modify : ('a -> 'b) -> 'a Eliom_reference.eref -> unit Lwt.t =
  fun f eref ->
    lwt content = Eliom_reference.get eref in
    Eliom_reference.set eref (f content)

let rec lwt_tree_flatten (tree: 'a tree): 'a list Lwt.t =
let Node (p, cs) = tree in
        lwt_forest_flatten cs >>=
        fun rest -> return (p::rest)
and lwt_forest_flatten (forest: 'a tree list): 'a list Lwt.t =
        Lwt_list.map_p lwt_tree_flatten forest >>=
        fun f -> lwt_flatten f

let list_assoc_opt a l =
  try
    Some (List.assoc a l)
  with Not_found -> None

let list_assoc_default a l default =
  try
    List.assoc a l
  with Not_found -> default

let list_assoc_exn a l exn =
  try List.assoc a l
  with Not_found -> raise exn

let bind_opt o f = match o with
  | None -> None
  | Some s -> Some (f s)

let lwt_bind_opt o f = match o with
  | None -> Lwt.return None
  | Some s -> f s >>= fun r -> Lwt.return (Some r)

let int_of_string_opt s =
  bind_opt s int_of_string

let string_of_string_opt = function
  | None -> ""
  | Some s -> s

let rec lwt_filter f = function
  | [] -> Lwt.return []
  | a::l ->
      let llt = lwt_filter f l in
      f a >>= fun b ->
      llt >>= fun ll ->
      if b
      then Lwt.return (a::ll)
      else Lwt.return ll

let rec find_opt f = function
  | [] -> None
  | e :: l ->
      match f e with
        | None -> find_opt f l
        | Some v -> Some v

let rec concat_list_opt lo l = match lo with
  | [] -> l
  | None :: q -> concat_list_opt q l
  | Some e :: q -> e :: concat_list_opt q l



(** Association maps with default values (which thus never raise [Not_found] *)
module type DefaultMap = sig
  type key
  type 'a t

  val empty : (key -> 'a) -> 'a t
  val find : key -> 'a t -> 'a
  val add : key -> 'a -> 'a t -> 'a t
end

module DefaultMap (X : Map.OrderedType) : DefaultMap with type key = X.t
= struct
  type key = X.t
  module XMap = Map.Make(X)

  type 'a t = {
    default: X.t -> 'a;
    map: 'a XMap.t
  }
  let empty default = {
    default = default;
    map = XMap.empty
  }

  let find k map =
    try XMap.find k map.map
    with Not_found -> map.default k

  let add k v map =
    { map with map = XMap.add k v map.map }
end



let remove_prefix ~s ~prefix =
  let slen = String.length s
  and preflen = String.length prefix in
  let preflast = preflen - 1 in
  let first_diff = Eliom_lib.String.first_diff prefix s 0 preflen in
  if first_diff = preflen
  then Some (String.sub s preflen (slen - preflen))
  else if first_diff = preflast && slen = preflast
  then Some ""
  else None

let remove_begin_slash s =
  if s = "" then ""
  else if s.[0] = '/' then
    String.sub s 1 ((String.length s) - 1)
  else s


let hidden_bool_input :
  value:bool ->
  [< bool Eliom_parameter.setoneradio ] Eliom_parameter.param_name ->
  [>Html5_types.input] Html5.F.elt
 = fun ~value name ->
   Html5.D.user_type_input string_of_bool
     ~input_type:`Hidden ~value ~name ()


let eliom_bool =
  Eliom_parameter.user_type ~to_string:string_of_bool ~of_string:bool_of_string


let remove_re = Netstring_pcre.regexp "(?s-m)\\A\\s*(\\S(.*\\S)?)\\s*\\z"
let remove_spaces s =
  match Netstring_pcre.string_match remove_re s 0 with
  | None -> s
  | Some r -> Netstring_pcre.matched_group r 1 s

module List = struct
  include List
  let last ~default l = try Eliom_lib.List.last l with Not_found -> default ()
end

module Abstract_url : sig
  type t
  val create : string -> t
  val empty : t
  val to_list : t -> string list
  val to_string : t -> string
  val join : t -> t -> t
  val length : t -> int
  val last : t -> string
  val split : t -> t list
end = struct
  type t = string list
  let create = Neturl.split_path
  let empty = []
  let to_list = id
  let to_string = Neturl.join_path
  let join = (@)
  let length = List.length
  let last = List.last ~default:(fun () -> "")
  let split =
    List.fold_left
      (fun acc x -> acc @ [List.last ~default:(fun () -> empty) acc @ [x]])
      []
end
