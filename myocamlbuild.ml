(* OASIS_START *)
(* DO NOT EDIT (digest: f5325916618ec1d767a7476f5c2edb11) *)
module OASISGettext = struct
(* # 21 "src/oasis/OASISGettext.ml" *)

  let ns_ str =
    str

  let s_ str =
    str

  let f_ (str : ('a, 'b, 'c, 'd) format4) =
    str

  let fn_ fmt1 fmt2 n =
    if n = 1 then
      fmt1^^""
    else
      fmt2^^""

  let init =
    []

end

module OASISExpr = struct
(* # 21 "src/oasis/OASISExpr.ml" *)



  open OASISGettext

  type test = string

  type flag = string

  type t =
    | EBool of bool
    | ENot of t
    | EAnd of t * t
    | EOr of t * t
    | EFlag of flag
    | ETest of test * string


  type 'a choices = (t * 'a) list

  let eval var_get t =
    let rec eval' =
      function
        | EBool b ->
            b

        | ENot e ->
            not (eval' e)

        | EAnd (e1, e2) ->
            (eval' e1) && (eval' e2)

        | EOr (e1, e2) ->
            (eval' e1) || (eval' e2)

        | EFlag nm ->
            let v =
              var_get nm
            in
              assert(v = "true" || v = "false");
              (v = "true")

        | ETest (nm, vl) ->
            let v =
              var_get nm
            in
              (v = vl)
    in
      eval' t

  let choose ?printer ?name var_get lst =
    let rec choose_aux =
      function
        | (cond, vl) :: tl ->
            if eval var_get cond then
              vl
            else
              choose_aux tl
        | [] ->
            let str_lst =
              if lst = [] then
                s_ "<empty>"
              else
                String.concat
                  (s_ ", ")
                  (List.map
                     (fun (cond, vl) ->
                        match printer with
                          | Some p -> p vl
                          | None -> s_ "<no printer>")
                     lst)
            in
              match name with
                | Some nm ->
                    failwith
                      (Printf.sprintf
                         (f_ "No result for the choice list '%s': %s")
                         nm str_lst)
                | None ->
                    failwith
                      (Printf.sprintf
                         (f_ "No result for a choice list: %s")
                         str_lst)
    in
      choose_aux (List.rev lst)

end


# 117 "myocamlbuild.ml"
module BaseEnvLight = struct
(* # 21 "src/base/BaseEnvLight.ml" *)

  module MapString = Map.Make(String)

  type t = string MapString.t

  let default_filename =
    Filename.concat
      (Sys.getcwd ())
      "setup.data"

  let load ?(allow_empty=false) ?(filename=default_filename) () =
    if Sys.file_exists filename then
      begin
        let chn =
          open_in_bin filename
        in
        let st =
          Stream.of_channel chn
        in
        let line =
          ref 1
        in
        let st_line =
          Stream.from
            (fun _ ->
               try
                 match Stream.next st with
                   | '\n' -> incr line; Some '\n'
                   | c -> Some c
               with Stream.Failure -> None)
        in
        let lexer =
          Genlex.make_lexer ["="] st_line
        in
        let rec read_file mp =
          match Stream.npeek 3 lexer with
            | [Genlex.Ident nm; Genlex.Kwd "="; Genlex.String value] ->
                Stream.junk lexer;
                Stream.junk lexer;
                Stream.junk lexer;
                read_file (MapString.add nm value mp)
            | [] ->
                mp
            | _ ->
                failwith
                  (Printf.sprintf
                     "Malformed data file '%s' line %d"
                     filename !line)
        in
        let mp =
          read_file MapString.empty
        in
          close_in chn;
          mp
      end
    else if allow_empty then
      begin
        MapString.empty
      end
    else
      begin
        failwith
          (Printf.sprintf
             "Unable to load environment, the file '%s' doesn't exist."
             filename)
      end

  let var_get name env =
    let rec var_expand str =
      let buff =
        Buffer.create ((String.length str) * 2)
      in
        Buffer.add_substitute
          buff
          (fun var ->
             try
               var_expand (MapString.find var env)
             with Not_found ->
               failwith
                 (Printf.sprintf
                    "No variable %s defined when trying to expand %S."
                    var
                    str))
          str;
        Buffer.contents buff
    in
      var_expand (MapString.find name env)

  let var_choose lst env =
    OASISExpr.choose
      (fun nm -> var_get nm env)
      lst
end


# 215 "myocamlbuild.ml"
module MyOCamlbuildFindlib = struct
(* # 21 "src/plugins/ocamlbuild/MyOCamlbuildFindlib.ml" *)

  (** OCamlbuild extension, copied from
    * http://brion.inria.fr/gallium/index.php/Using_ocamlfind_with_ocamlbuild
    * by N. Pouillard and others
    *
    * Updated on 2009/02/28
    *
    * Modified by Sylvain Le Gall
    *)
  open Ocamlbuild_plugin

  (* these functions are not really officially exported *)
  let run_and_read =
    Ocamlbuild_pack.My_unix.run_and_read

  let blank_sep_strings =
    Ocamlbuild_pack.Lexers.blank_sep_strings

  let split s ch =
    let x =
      ref []
    in
    let rec go s =
      let pos =
        String.index s ch
      in
        x := (String.before s pos)::!x;
        go (String.after s (pos + 1))
    in
      try
        go s
      with Not_found -> !x

  let split_nl s = split s '\n'

  let before_space s =
    try
      String.before s (String.index s ' ')
    with Not_found -> s

  (* this lists all supported packages *)
  let find_packages () =
    List.map before_space (split_nl & run_and_read "ocamlfind list")

  (* this is supposed to list available syntaxes, but I don't know how to do it. *)
  let find_syntaxes () = ["camlp4o"; "camlp4r"]

  (* ocamlfind command *)
  let ocamlfind x = S[A"ocamlfind"; x]

  let dispatch =
    function
      | Before_options ->
          (* by using Before_options one let command line options have an higher priority *)
          (* on the contrary using After_options will guarantee to have the higher priority *)
          (* override default commands by ocamlfind ones *)
          Options.ocamlc     := ocamlfind & A"ocamlc";
          Options.ocamlopt   := ocamlfind & A"ocamlopt";
          Options.ocamldep   := ocamlfind & A"ocamldep";
          Options.ocamldoc   := ocamlfind & A"ocamldoc";
          Options.ocamlmktop := ocamlfind & A"ocamlmktop"

      | After_rules ->

          (* When one link an OCaml library/binary/package, one should use -linkpkg *)
          flag ["ocaml"; "link"; "program"] & A"-linkpkg";

          (* For each ocamlfind package one inject the -package option when
           * compiling, computing dependencies, generating documentation and
           * linking. *)
          List.iter
            begin fun pkg ->
              flag ["ocaml"; "compile";  "pkg_"^pkg] & S[A"-package"; A pkg];
              flag ["ocaml"; "ocamldep"; "pkg_"^pkg] & S[A"-package"; A pkg];
              flag ["ocaml"; "doc";      "pkg_"^pkg] & S[A"-package"; A pkg];
              flag ["ocaml"; "link";     "pkg_"^pkg] & S[A"-package"; A pkg];
              flag ["ocaml"; "infer_interface"; "pkg_"^pkg] & S[A"-package"; A pkg];
            end
            (find_packages ());

          (* Like -package but for extensions syntax. Morover -syntax is useless
           * when linking. *)
          List.iter begin fun syntax ->
          flag ["ocaml"; "compile";  "syntax_"^syntax] & S[A"-syntax"; A syntax];
          flag ["ocaml"; "ocamldep"; "syntax_"^syntax] & S[A"-syntax"; A syntax];
          flag ["ocaml"; "doc";      "syntax_"^syntax] & S[A"-syntax"; A syntax];
          flag ["ocaml"; "infer_interface"; "syntax_"^syntax] & S[A"-syntax"; A syntax];
          end (find_syntaxes ());

          (* The default "thread" tag is not compatible with ocamlfind.
           * Indeed, the default rules add the "threads.cma" or "threads.cmxa"
           * options when using this tag. When using the "-linkpkg" option with
           * ocamlfind, this module will then be added twice on the command line.
           *
           * To solve this, one approach is to add the "-thread" option when using
           * the "threads" package using the previous plugin.
           *)
          flag ["ocaml"; "pkg_threads"; "compile"] (S[A "-thread"]);
          flag ["ocaml"; "pkg_threads"; "doc"] (S[A "-I"; A "+threads"]);
          flag ["ocaml"; "pkg_threads"; "link"] (S[A "-thread"]);
          flag ["ocaml"; "pkg_threads"; "infer_interface"] (S[A "-thread"])

      | _ ->
          ()

end

module MyOCamlbuildBase = struct
(* # 21 "src/plugins/ocamlbuild/MyOCamlbuildBase.ml" *)

  (** Base functions for writing myocamlbuild.ml
      @author Sylvain Le Gall
    *)



  open Ocamlbuild_plugin
  module OC = Ocamlbuild_pack.Ocaml_compiler

  type dir = string
  type file = string
  type name = string
  type tag = string

(* # 56 "src/plugins/ocamlbuild/MyOCamlbuildBase.ml" *)

  type t =
      {
        lib_ocaml: (name * dir list) list;
        lib_c:     (name * dir * file list) list;
        flags:     (tag list * (spec OASISExpr.choices)) list;
        (* Replace the 'dir: include' from _tags by a precise interdepends in
         * directory.
         *)
        includes:  (dir * dir list) list;
      }

  let env_filename =
    Pathname.basename
      BaseEnvLight.default_filename

  let dispatch_combine lst =
    fun e ->
      List.iter
        (fun dispatch -> dispatch e)
        lst

  let tag_libstubs nm =
    "use_lib"^nm^"_stubs"

  let nm_libstubs nm =
    nm^"_stubs"

  let dispatch t e =
    let env =
      BaseEnvLight.load
        ~filename:env_filename
        ~allow_empty:true
        ()
    in
      match e with
        | Before_options ->
            let no_trailing_dot s =
              if String.length s >= 1 && s.[0] = '.' then
                String.sub s 1 ((String.length s) - 1)
              else
                s
            in
              List.iter
                (fun (opt, var) ->
                   try
                     opt := no_trailing_dot (BaseEnvLight.var_get var env)
                   with Not_found ->
                     Printf.eprintf "W: Cannot get variable %s" var)
                [
                  Options.ext_obj, "ext_obj";
                  Options.ext_lib, "ext_lib";
                  Options.ext_dll, "ext_dll";
                ]

        | After_rules ->
            (* Declare OCaml libraries *)
            List.iter
              (function
                 | nm, [] ->
                     ocaml_lib nm
                 | nm, dir :: tl ->
                     ocaml_lib ~dir:dir (dir^"/"^nm);
                     List.iter
                       (fun dir ->
                          List.iter
                            (fun str ->
                               flag ["ocaml"; "use_"^nm; str] (S[A"-I"; P dir]))
                            ["compile"; "infer_interface"; "doc"])
                       tl)
              t.lib_ocaml;

            (* Declare directories dependencies, replace "include" in _tags. *)
            List.iter
              (fun (dir, include_dirs) ->
                 Pathname.define_context dir include_dirs)
              t.includes;

            (* Declare C libraries *)
            List.iter
              (fun (lib, dir, headers) ->
                   (* Handle C part of library *)
                   flag ["link"; "library"; "ocaml"; "byte"; tag_libstubs lib]
                     (S[A"-dllib"; A("-l"^(nm_libstubs lib)); A"-cclib";
                        A("-l"^(nm_libstubs lib))]);

                   flag ["link"; "library"; "ocaml"; "native"; tag_libstubs lib]
                     (S[A"-cclib"; A("-l"^(nm_libstubs lib))]);

                   flag ["link"; "program"; "ocaml"; "byte"; tag_libstubs lib]
                     (S[A"-dllib"; A("dll"^(nm_libstubs lib))]);

                   (* When ocaml link something that use the C library, then one
                      need that file to be up to date.
                    *)
                   dep ["link"; "ocaml"; "program"; tag_libstubs lib]
                     [dir/"lib"^(nm_libstubs lib)^"."^(!Options.ext_lib)];

                   dep  ["compile"; "ocaml"; "program"; tag_libstubs lib]
                     [dir/"lib"^(nm_libstubs lib)^"."^(!Options.ext_lib)];

                   (* TODO: be more specific about what depends on headers *)
                   (* Depends on .h files *)
                   dep ["compile"; "c"]
                     headers;

                   (* Setup search path for lib *)
                   flag ["link"; "ocaml"; "use_"^lib]
                     (S[A"-I"; P(dir)]);
              )
              t.lib_c;

              (* Add flags *)
              List.iter
              (fun (tags, cond_specs) ->
                 let spec =
                   BaseEnvLight.var_choose cond_specs env
                 in
                   flag tags & spec)
              t.flags
        | _ ->
            ()

  let dispatch_default t =
    dispatch_combine
      [
        dispatch t;
        MyOCamlbuildFindlib.dispatch;
      ]

end


# 476 "myocamlbuild.ml"
open Ocamlbuild_plugin;;
let package_default =
  {
     MyOCamlbuildBase.lib_ocaml =
       [
          ("ocsimore", ["src/core"; "src/core/server"]);
          ("ocsimore_client", ["src/core/client"]);
          ("user", ["src/user"]);
          ("ocsimore-nis", ["src/user"]);
          ("ocsimore-pam", ["src/user"]);
          ("ocsimore-ldap", ["src/user"]);
          ("wiki", ["src/wiki"; "src/wiki/server"]);
          ("wiki_client", ["src/wiki/client"]);
          ("forum", ["src/forum"]);
          ("core_site", ["src/site"; "src/site/server"]);
          ("core_site_client", ["src/site/client"]);
          ("user_site", ["src/site"; "src/site/server"]);
          ("wiki_site", ["src/site"; "src/site/server"]);
          ("forum_site", ["src/site"; "src/site/server"]);
          ("wiki_perso", ["src/site"; "src/site/server"])
       ];
     lib_c = [("ocsimore", "src/core", [])];
     flags =
       [
          (["oasis_library_ocsimore_cclib"; "link"],
            [(OASISExpr.EBool true, S [A "-cclib"; A "-lcrypt"])]);
          (["oasis_library_ocsimore_cclib"; "ocamlmklib"; "c"],
            [(OASISExpr.EBool true, S [A "-lcrypt"])])
       ];
     includes =
       [
          ("src/wiki/server", ["src/user"; "src/wiki"]);
          ("src/wiki/client", ["src/core/client"]);
          ("src/wiki", ["src/user"; "src/wiki/server"]);
          ("src/user", ["src/core"; "src/core/server"]);
          ("src/site/server",
            [
               "src/core";
               "src/core/server";
               "src/forum";
               "src/site";
               "src/wiki";
               "src/wiki/server"
            ]);
          ("src/site/client", ["src/wiki/client"]);
          ("src/site",
            [
               "src/core";
               "src/core/server";
               "src/forum";
               "src/site/server";
               "src/wiki";
               "src/wiki/server"
            ]);
          ("src/forum", ["src/wiki"; "src/wiki/server"]);
          ("src/core/server", ["src/core"]);
          ("src/core", ["src/core/server"])
       ];
     }
  ;;

let dispatch_default = MyOCamlbuildBase.dispatch_default package_default;;

# 541 "myocamlbuild.ml"
(* OASIS_STOP *)

(*Ocamlbuild_pack.Log.classic_display := true;;*)

module Ocamlbuild_eliom (Client : sig
  val client_exec : string option
  val dispatch_default : Ocamlbuild_plugin.hook -> unit
  val server_dir : string
  val type_dir : string
  val client_dir : string
end) = struct
  open Ocamlbuild_plugin
  module Pack = Ocamlbuild_pack

  let copy_with_header src prod =
    let contents = Pathname.read src in
    let header = "# 1 \"" ^ src ^ "\"\n" in
    Pack.Shell.mkdir_p (Filename.dirname prod);
    Echo ([header; contents], prod)

  let copy_rule_with_header f name ?(deps=[]) src prod =
    rule name ~deps:(src :: deps) ~prod
      (fun env _ ->
         let prod = env prod in
         let src = env src in
         f env (Pathname.dirname prod) (Pathname.basename prod) prod;
         copy_with_header src prod
      )

  let flag_infer file type_inferred =
    let file_tag = "file:" ^ file in
    let tags =
      [["ocaml"; "ocamldep"; file_tag];
       ["ocaml"; "compile"; file_tag];
       ["ocaml"; "infer_interface"; file_tag];
      ]
    in
    let f tags =
      flag tags (S [A "-ppopt"; A "-type"; A "-ppopt"; P type_inferred])
    in
    List.iter f tags;
    flag ["ocaml"; "doc"; file_tag] (S [A "-ppopt"; A "-notype"])

  let copy_rule_server =
    copy_rule_with_header
      (fun env dir name file ->
         let path = env "%(path)" in
         let type_inferred =
           Pathname.concat
             (Pathname.concat path Client.type_dir)
             (Pathname.update_extension "inferred.mli" name)
         in
         tag_file file
           [ "pkg_eliom.server"; "pkg_eliom.syntax.server"; "thread";
             "syntax_camlp4o";
           ];
         flag_infer file type_inferred;
         Pathname.define_context dir [path];
         Pathname.define_context path [dir];
      )

  let copy_rule_client =
    copy_rule_with_header
      (fun env dir name file ->
         let path = env "%(path)" in
         let type_inferred =
           Pathname.concat
             (Pathname.concat path Client.type_dir)
             (Pathname.update_extension "inferred.mli" name)
         in
         tag_file file
           [ "pkg_eliom.client"; "pkg_eliom.syntax.client"; "thread";
             "syntax_camlp4o";
           ];
         flag_infer file type_inferred;
         Pathname.define_context dir [path];
      )

  let copy_rule_type =
    copy_rule_with_header
      (fun env dir name file ->
         let path = env "%(path)" in
         let server_dir = Pathname.concat path Client.server_dir in
         let server_file = Pathname.concat server_dir name in
         tag_file file
           ( "pkg_eliom.syntax.type" :: "thread" :: "syntax_camlp4o"
             :: Tags.elements (tags_of_pathname server_file)
           );
         Pathname.define_context dir [path; server_dir];
      )

  let js_rule () =
    let linker tags deps out =
      Cmd (S [A "js_of_eliom"; T tags;
              Command.atomize_paths deps; A "-o"; Px out])
    in
    rule "js_of_eliom: .cmo -> .js" ~dep:"%.cmo" ~prod:"%.js"
      (fun env ->
         Pack.Ocaml_compiler.link_gen
           "cmo" "cma" "cma" ["cmo"; "cmi"] linker
           (fun tags ->
              Tags.union
                (tags_of_pathname (env "%.ml"))
                (tags++"ocaml"++"link"++"byte"++"jslink"++"js_of_eliom")
           )
           "%.cmo" "%.js"
           env
      )

  let add_to_targets () =
    match Client.client_exec with
      | None -> ()
      | Some x -> Options.targets @:= [x]

  let dispatch_default hook =
    Client.dispatch_default hook;
    match hook with
      | After_options ->
          add_to_targets ();
      | After_rules ->
          js_rule ();

          copy_rule_server "*.eliom -> **/_server/*.ml"
            ~deps:["%(path)/" ^ Client.type_dir ^ "/%(file).inferred.mli"]
            "%(path)/%(file).eliom"
            ("%(path)/" ^ Client.server_dir ^ "/%(file:<*>).ml");
          copy_rule_server "*.eliomi -> **/_server/*.mli"
            "%(path)/%(file).eliomi"
            ("%(path)/" ^ Client.server_dir ^ "/%(file:<*>).mli");
          copy_rule_type "*.eliom -> **/_type/*.ml"
            "%(path)/%(file).eliom"
            ("%(path)/" ^ Client.type_dir ^ "/%(file:<*>).ml");
          copy_rule_type "*.eliomi -> **/_type/*.mli"
            "%(path)/%(file).eliomi"
            ("%(path)/" ^ Client.type_dir ^ "/%(file:<*>).mli");
          copy_rule_client "*.eliom -> **/_client/*.ml"
            ~deps:["%(path)/" ^ Client.type_dir ^ "/%(file).inferred.mli"]
            "%(path)/%(file).eliom"
            ("%(path)/" ^ Client.client_dir ^ "/%(file:<*>).ml");
          copy_rule_client "*.eliomi -> **/_client/*.mli"
            "%(path)/%(file).eliomi"
            ("%(path)/" ^ Client.client_dir ^ "/%(file:<*>).mli");

          copy_rule_server "*.eliom -> _server/*.ml"
            ~deps:[Client.type_dir ^ "/%(file).inferred.mli"]
            "%(file).eliom" (Client.server_dir ^ "/%(file:<*>).ml");
          copy_rule_server "*.eliomi -> _server/*.mli"
            "%(file).eliomi" (Client.server_dir ^ "/%(file:<*>).mli");
          copy_rule_type "*.eliom -> _type/*.ml"
            "%(file).eliom" (Client.type_dir ^ "/%(file:<*>).ml");
          copy_rule_type "*.eliomi -> _type/*.mli"
            "%(file).eliomi" (Client.type_dir ^ "/%(file:<*>).mli");
          copy_rule_client "*.eliom -> _client/*.ml"
            ~deps:[Client.type_dir ^ "/%(file).inferred.mli"]
            "%(file).eliom" (Client.client_dir ^ "/%(file:<*>).ml");
          copy_rule_client "*.eliomi -> _client/*.mli"
            "%(file).eliomi" (Client.client_dir ^ "/%(file:<*>).mli");
      | _ -> ()
end;;

module M = Ocamlbuild_eliom(struct
  let client_exec = Some "src/site/client/ocsimore.js"
  let dispatch_default = dispatch_default
  let client_dir = "client"
  let server_dir = "server"
  let type_dir = "type"
end);;

Ocamlbuild_plugin.dispatch M.dispatch_default;;

(* Use an introduction page with categories *)
tag_file "api.docdir/index.html" ["apiref"];;
dep ["apiref"] ["doc/indexdoc"];;
flag ["apiref"] & S[A "-intro"; P "doc/indexdoc"; A"-colorize-code"];;

(* Compile the wiki version of the Ocamldoc.

   Thanks to Till Varoquaux on usenet:
   http://www.digipedia.pl/usenet/thread/14273/231/

*)

let ocamldoc_wiki tags deps docout docdir =
  let tags = tags -- "extension:html" in
  Ocamlbuild_pack.Ocaml_tools.ocamldoc_l_dir tags deps docout docdir

let () =
  try
    let wikidoc_dir =
      let base = Ocamlbuild_pack.My_unix.run_and_read "ocamlfind query wikidoc" in
      String.sub base 0 (String.length base - 1)
    in

    Ocamlbuild_pack.Rule.rule
      "ocamldoc: document ocaml project odocl & *odoc -> wikidocdir"
      ~insert:`top
      ~prod:"%.wikidocdir/index.wiki"
      ~stamp:"%.wikidocdir/wiki.stamp"
      ~dep:"%.odocl"
      (Ocamlbuild_pack.Ocaml_tools.document_ocaml_project
         ~ocamldoc:ocamldoc_wiki
         "%.odocl" "%.wikidocdir/index.wiki" "%.wikidocdir");

    tag_file "api.wikidocdir/index.wiki" ["apiref";"wikidoc"];
    flag ["wikidoc"] & S[A"-i";A wikidoc_dir;A"-g";A"odoc_wiki.cma"]

  with Failure e -> () (* Silently fail if the package wikidoc isn't available *)
