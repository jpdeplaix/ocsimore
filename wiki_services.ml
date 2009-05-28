(* Ocsimore
 * http://www.ocsigen.org
 * Copyright (C) 2005-2009
 * Piero Furiesi - Jaap Boender - Vincent Balat - Boris Yakobowski -
 * CNRS - Université Paris Diderot Paris 7
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
These are all the services related to wikis

*)

open User_sql.Types
open Wiki_widgets_interface
open Wiki_types
let (>>=) = Lwt.bind

exception Css_already_exists
exception Page_already_exists



let send_wikipage ~(rights : Wiki_types.wiki_rights) ~sp ~wiki ~page =
  Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
  (* if there is a static page, and should we send it ? *)
  Lwt.catch
    (fun () ->
       match wiki_info.wiki_staticdir with
         | Some dir ->
                Eliom_predefmod.Files.send ~sp (dir^"/"^page) >>= fun r ->
                  (rights#can_view_static_files sp wiki >>= function
                     | true -> Lwt.return r
                     | false -> Lwt.fail Ocsimore_common.Permission_denied (* XXX We should send a 403. ? *)
             )
         | None -> Lwt.fail Eliom_common.Eliom_404)
    (function
       | Eliom_common.Eliom_404 ->
           Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
           let widgets = Wiki_models.get_widgets wiki_info.wiki_model in
           widgets#display_wikipage ~sp ~wiki ~page >>= fun (html, code) ->
             Eliom_duce.Xhtml.send ~sp ~code html
       | e -> Lwt.fail e)


(* Register the services for the wiki [wiki] *)
let register_wiki ~rights ?sp ~path ~wiki () =
  Ocsigen_messages.debug
    (fun () -> Printf.sprintf "Registering wiki %s (at path '%s')"
       (string_of_wiki wiki) (String.concat "/"  path));
  (* Registering the service with suffix for wikipages *)
  (* Note that Eliom will look for the service corresponding to
     the longest prefix. Thus it is possible to register a wiki
     at URL / and another one at URL /wiki and it works,
     whatever be the order of registration *)
  let servpage =
    Eliom_predefmod.Any.register_new_service ~path ?sp
      ~get_params:(Eliom_parameters.suffix (Eliom_parameters.all_suffix "page"))
      (fun sp path () ->
         send_wikipage ~rights ~sp ~wiki
           ~page:(Ocsigen_lib.string_of_url_path ~encode:true path)
      )
  in
  add_servpage wiki servpage;

  (* the same, but non attached: *)
  let naservpage =
    Eliom_predefmod.Any.register_new_coservice' ?sp
      ~name:("display"^string_of_wiki wiki)
      ~get_params:(Eliom_parameters.string "page")
      (fun sp page () ->
         let path =
           Ocsigen_lib.remove_slash_at_beginning (Neturl.split_path page) in
         let page = Ocsigen_lib.string_of_url_path ~encode:true path in
         send_wikipage ~rights ~sp ~wiki ~page
      )
  in
  add_naservpage wiki naservpage;

  let wikicss_service =
    Eliom_predefmod.CssText.register_new_service ?sp
      ~path:(path@["__ocsiwikicss"])
      ~get_params:Eliom_parameters.unit
      (fun sp () () -> Wiki_data.wiki_css rights sp wiki)
  in
  add_servwikicss wiki wikicss_service



let save_then_redirect overriden_wikibox ~sp redirect_mode f =
  Lwt.catch
    (fun () ->
       f () >>= fun _ ->
       (* We do a redirection to prevent repost *)
       match redirect_mode with
         | `BasePage ->
             Eliom_predefmod.Redirection.send ~sp Eliom_services.void_coservice'
         | `SamePage ->
             Eliom_predefmod.Action.send ~sp ()
    )
    (fun e ->
       Wiki_widgets_interface.set_wikibox_error
         ~sp
         (overriden_wikibox, e);
       Eliom_predefmod.Action.send ~sp ())




let ( ** ) = Eliom_parameters.prod

let eliom_wiki_args = Wiki_sql.eliom_wiki "wid"
let eliom_wikibox_args = eliom_wiki_args ** (Eliom_parameters.int32 "wbid")
let eliom_wikipage_args = eliom_wiki_args ** (Eliom_parameters.string "page")
let eliom_css_args =
  (Wiki_sql.eliom_wiki "widcss" ** (Eliom_parameters.int32 "wbidcss"))
  ** (Eliom_parameters.opt (Eliom_parameters.string "pagecss"))




(* Services *)

let make_services () = 
  let action_edit_css = Eliom_predefmod.Action.register_new_coservice'
    ~name:"css_edit"
    ~get_params:(eliom_wikibox_args **
                   (eliom_css_args **
                      (Eliom_parameters.opt (Eliom_parameters.string "css" **
                                               Eliom_parameters.int32 "version"))))
    (fun sp (wb, args) () -> 
       Wiki_widgets_interface.set_override_wikibox
         ~sp
         (wb, EditCss args);
       Lwt.return ())

  and action_edit_wikibox = Eliom_predefmod.Action.register_new_coservice'
    ~name:"wiki_edit" ~get_params:eliom_wikibox_args
    (fun sp wb () ->
       Wiki_widgets_interface.set_override_wikibox
         ~sp
         (wb, EditWikitext wb);
       Lwt.return ())

  and action_delete_wikibox = Eliom_predefmod.Any.register_new_coservice'
    ~name:"wiki_delete" ~get_params:eliom_wikibox_args
    (fun sp wb () ->
       Wiki_sql.get_wiki_info_by_id (fst wb) >>= fun wiki_info ->
       let rights = Wiki_models.get_rights wiki_info.wiki_model in
       let content_type =
         Wiki_models.get_default_content_type wiki_info.wiki_model in
       save_then_redirect wb ~sp `BasePage
         (fun () -> Wiki_data.save_wikitextbox ~rights ~content_type ~sp ~wb
            ~content:None)
    )

  and action_edit_wikibox_permissions =
    Eliom_predefmod.Action.register_new_coservice'
      ~name:"wikibox_edit_perm" ~get_params:eliom_wikibox_args
      (fun sp wb () -> 
         Wiki_widgets_interface.set_override_wikibox
           ~sp
           (wb, EditWikiboxPerms wb);
         Lwt.return ())

  and action_edit_wiki_permissions =
    Eliom_predefmod.Action.register_new_coservice'
      ~name:"wiki_edit_perm" ~get_params:(eliom_wikibox_args ** eliom_wiki_args)
      (fun sp (wb, wiki) () ->
         Wiki_widgets_interface.set_override_wikibox ~sp
           (wb, EditWikiPerms wiki);
         Lwt.return ())

  and action_wikibox_history = Eliom_predefmod.Action.register_new_coservice'
    ~name:"wikibox_history" ~get_params:eliom_wikibox_args
    (fun sp wb () -> 
       Wiki_widgets_interface.set_override_wikibox
         ~sp
         (wb, History wb);
       Lwt.return ())

  and action_css_history = Eliom_predefmod.Action.register_new_coservice'
    ~name:"css_history" ~get_params:(eliom_wikibox_args ** eliom_css_args)
    (fun sp (wb, css) () -> 
       Wiki_widgets_interface.set_override_wikibox
         ~sp
         (wb, CssHistory css);
       Lwt.return ())

  and action_old_wikibox = Eliom_predefmod.Action.register_new_coservice'
    ~name:"wiki_old_version"
    ~get_params:(eliom_wikibox_args ** (Eliom_parameters.int32 "version"))
    (fun sp (wb, _ver as arg) () ->
       Wiki_widgets_interface.set_override_wikibox
         ~sp
         (wb, Oldversion arg);
       Lwt.return ())

  and action_old_wikiboxcss = Eliom_predefmod.Action.register_new_coservice'
    ~name:"css_old_version"
    ~get_params:(eliom_wikibox_args **
                   (eliom_css_args ** (Eliom_parameters.int32 "version")))
    (fun sp (wb, (wbcss, version)) () ->
       Wiki_widgets_interface.set_override_wikibox
         ~sp
         (wb, CssOldversion (wbcss, version));
       Lwt.return ())

  and action_src_wikibox = Eliom_predefmod.Action.register_new_coservice'
    ~name:"wiki_src"
    ~get_params:(eliom_wikibox_args ** (Eliom_parameters.int32 "version"))
    (fun sp (wb, _ver as arg) () -> 
       Wiki_widgets_interface.set_override_wikibox
         ~sp
         (wb, Src arg);
       Lwt.return ())

  and action_send_wikiboxtext = Eliom_predefmod.Any.register_new_post_coservice'
    ~keep_get_na_params:false ~name:"wiki_save_wikitext"
    ~post_params:
    (Eliom_parameters.string "actionname" **
       ((eliom_wikibox_args ** Eliom_parameters.int32 "boxversion") **
          Eliom_parameters.string "content"))
    (fun sp () (actionname, ((wb, boxversion), content)) ->
       (* We always show a preview before saving. Moreover, we check that the
          wikibox that the wikibox has not been modified in parallel of our
          modifications. If this is the case, we also show a warning *)
       Wiki.modified_wikibox wb boxversion >>= fun modified ->
       if actionname = "save" 
       then
         match modified with
           | None ->
               Wiki_sql.get_wiki_info_by_id (fst wb) >>= fun wiki_info ->
               let rights = Wiki_models.get_rights wiki_info.wiki_model in
               let wp = Wiki_models.get_default_wiki_preparser
                 wiki_info.wiki_model in
               Wiki_data.wikibox_content rights sp wb >>= fun (content_type, _, _) ->
               wp (sp, wb) content >>= fun content ->
               save_then_redirect wb ~sp `BasePage
                 (fun () -> Wiki_data.save_wikitextbox ~rights
                    ~content_type ~sp ~wb ~content:(Some content))
           | Some _ ->
               Wiki_widgets_interface.set_override_wikibox
                 ~sp
                 (wb, PreviewWikitext (wb, (content, boxversion)));
               Eliom_predefmod.Action.send ~sp ()
         else begin
           Wiki_widgets_interface.set_override_wikibox
             ~sp
             (wb, PreviewWikitext (wb, (content, boxversion)));
           Eliom_predefmod.Action.send ~sp ()
         end
    )

  and action_send_css = Eliom_predefmod.Any.register_new_post_coservice'
    ~keep_get_na_params:false ~name:"wiki_save_css"
    ~post_params:
    ((eliom_wikibox_args ** (eliom_css_args **
                               Eliom_parameters.int32 "boxversion")) **
       Eliom_parameters.string "content")
    (fun sp () ((wb, ((wbcss, page), boxversion)), content) ->
       (* We always show a preview before saving. Moreover, we check that the
          wikibox that the wikibox has not been modified in parallel of our
          modifications. If this is the case, we also show a warning *)
       Wiki.modified_wikibox wbcss boxversion >>= fun modified ->
         Wiki_sql.get_wiki_info_by_id (fst wb) >>= fun wiki_info ->
           let rights = Wiki_models.get_rights wiki_info.wiki_model in
           match modified with
             | None ->
                 save_then_redirect wb ~sp `BasePage
                   (fun () -> match page with
                      | None -> Wiki_data.save_wikicssbox ~rights ~sp
                          ~wiki:(fst wbcss) ~content:(Some content)
                      | Some page -> Wiki_data.save_wikipagecssbox ~rights ~sp
                          ~wiki:(fst wbcss) ~page ~content:(Some content)
                   )
             | Some _ ->
                 Wiki_widgets_interface.set_override_wikibox
                   ~sp
                   (wb, EditCss ((wbcss, page),
                                 Some (content, boxversion)));
                 Eliom_predefmod.Action.send ~sp ()
    )

  and action_send_wikibox_permissions =
    let { Users.GroupsForms.awr_eliom_params = params; awr_save = f;
          awr_eliom_arg_param = arg} =
      Wiki.helpers_wikibox_permissions in
    Eliom_predefmod.Any.register_new_post_coservice'
      ~name:"wiki_save_wikibox_permissions"
      ~post_params:(Eliom_parameters.bool "special" ** (arg ** params))
      (fun sp () (special, (wbuid, args))->
         Wiki_sql.wikibox_from_uid wbuid >>= fun wb ->
         Wiki_sql.get_wiki_info_by_id (fst wb) >>= fun wiki_info ->
         let rights = Wiki_models.get_rights wiki_info.wiki_model in
         rights#can_set_wikibox_specific_permissions sp wb >>= function
           | true ->
               save_then_redirect wb ~sp `SamePage
                 (fun () ->
                    f wbuid args >>= fun () ->
                    Wiki_sql.set_wikibox_special_rights wb special)
           | false -> Lwt.fail Ocsimore_common.Permission_denied
      )

  and action_send_wiki_permissions =
    let params, f, _ = Wiki.helpers_wiki_permissions in
    Eliom_predefmod.Any.register_new_post_coservice'
      ~name:"wiki_save_wiki_permissions"
      ~post_params:(eliom_wikibox_args ** params)
      (fun sp () (wb, args) ->
         Wiki_sql.get_wiki_info_by_id (fst wb) >>= fun wiki_info ->
           let rights = Wiki_models.get_rights wiki_info.wiki_model in
           save_then_redirect wb ~sp `SamePage (fun () -> f rights sp args))

  (* Below are the services for the css of wikis and wikipages.  The css
     at the level of wikis are registered in Wiki_data.ml *)

  (* do not use this service, but the one below for css <link>s inside page *)
  and _ = Eliom_predefmod.CssText.register_new_service
    ~path:[Ocsimore_lib.ocsimore_admin_dir; "pagecss"]
    ~get_params:(Eliom_parameters.suffix eliom_wikipage_args)
    (fun sp (wiki, page) () ->
       Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
       let rights = Wiki_models.get_rights wiki_info.wiki_model in
       Wiki_data.wikipage_css rights sp wiki page)

  (* This is a non attached coservice, so that the css is in the same
     directory as the page. Important for relative links inside the css. *)
  and pagecss_service = Eliom_predefmod.CssText.register_new_coservice'
    ~name:"pagecss" ~get_params:eliom_wikipage_args
    (fun sp (wiki, page) () ->
       Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
       let rights = Wiki_models.get_rights wiki_info.wiki_model in
       Wiki_data.wikipage_css rights sp wiki page)

  and  _ = Eliom_predefmod.CssText.register_new_service
    ~path:[Ocsimore_lib.ocsimore_admin_dir; "wikicss"]
    ~get_params:(Wiki_sql.eliom_wiki "wiki")
    (fun sp wiki () ->
       Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
       let rights = Wiki_models.get_rights wiki_info.wiki_model in
       Wiki_data.wiki_css rights sp wiki)

  and action_create_page = Eliom_predefmod.Action.register_new_post_coservice'
    ~name:"wiki_page_create" ~post_params:eliom_wikipage_args
    (fun sp () (wiki, page) ->
       Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
         let rights = Wiki_models.get_rights wiki_info.wiki_model in
         rights#can_create_wikipages ~sp wiki
         >>= function
           | true ->
               Lwt.catch
                 (fun () ->
                    Wiki_sql.get_wikipage_info wiki page
                    >>= fun { wikipage_dest_wiki = wid; wikipage_wikibox = wbid } ->
                      (* The page already exists. We display an error message
                         in the wikibox that should have contained the button
                         leading to the creation of the page. *)
                      let wb = (wid, wbid) in
                      Wiki_widgets_interface.set_wikibox_error
                        ~sp
                        (wb, Page_already_exists);
                      Lwt.return ()
                 )
                 (function
                    | Not_found ->
                        Users.get_user_id ~sp >>= fun user ->
                          let content_type = 
                            Wiki_models.get_default_content_type
                              wiki_info.wiki_model 
                          in
                          Wiki_data.new_wikitextbox ~rights
                            ~content_type ~sp ~wiki ~author:user
                            ~comment:(Printf.sprintf "wikipage %s in wiki %s"
                                        page (string_of_wiki wiki))
                            ~content:("== Page "^page^"==") ()
                          >>= fun wbid ->
                            Wiki_sql.set_box_for_page ~sourcewiki:wiki ~wbid ~page ()
                            >>= fun () ->
                              Lwt.return ()
                            | e -> Lwt.fail e)
           | false ->  Lwt.fail Ocsimore_common.Permission_denied
    )

  and action_create_css = Eliom_predefmod.Action.register_new_coservice'
    ~name:"wiki_create_css"
    ~get_params:(eliom_wiki_args **
                   (Eliom_parameters.opt (Eliom_parameters.string "pagecss")))
    (fun sp (wiki, page) () ->
       Users.get_user_id ~sp >>= fun user ->
         Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
           let rights = Wiki_models.get_rights wiki_info.wiki_model in
           (match page with
              | None -> rights#can_create_wikicss sp wiki
              | Some page -> rights#can_create_wikipagecss sp (wiki, page)
           ) >>= function
             | false -> Lwt.fail Ocsimore_common.Permission_denied
             | true ->
                 let text = Some "" (* empty CSS by default *) in
                 match page with
                   | None -> (* Global CSS for the wiki *)
                       (Wiki_sql.get_css_for_wiki wiki >>= function
                          | None ->
                              Wiki_sql.set_css_for_wiki ~wiki ~author:user text
                          | Some _ -> Lwt.fail Css_already_exists
                       )

                   | Some page -> (* Css for a specific wikipage *)
                       (Wiki_sql.get_css_for_wikipage ~wiki ~page >>= function
                          | None ->
                              Wiki_sql.set_css_for_wikipage ~wiki ~page
                                ~author:user text
                          | Some _ -> Lwt.fail Css_already_exists
                       )
    )

  in (
    action_edit_css,
    action_edit_wikibox,
    action_delete_wikibox,
    action_edit_wikibox_permissions,
    action_edit_wiki_permissions,
    action_wikibox_history,
    action_css_history,
    action_old_wikibox,
    action_old_wikiboxcss,
    action_src_wikibox,
    action_send_wikiboxtext,
    action_send_css,
    action_send_wiki_permissions,
    action_send_wikibox_permissions,
    pagecss_service,
    action_create_page,
    action_create_css
  )
