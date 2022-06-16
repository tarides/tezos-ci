open Cmdliner
open Config
open Printf

exception Project_hook of string

let token_file =
  Arg.required
  @@ Arg.opt Arg.(some file) None
  @@ Arg.info ~doc:"A file containing the GitLab OAuth token." ~docv:"PATH"
       [ "gitlab-token-file" ]

let project_ids =
  Arg.value
  @@ Arg.opt Arg.string ""
  @@ Arg.info [ "project-ids" ] ~doc:"A comma separated list of project-ids."
       ~docv:"PROJECT IDS"

let project_names =
  Arg.value
  @@ Arg.opt Arg.string ""
  @@ Arg.info [ "project-names" ]
       ~doc:"A comma separated list of project-names." ~docv:"PROJECT NAMES"

let add_doc = "Add projects to tezos-ci."

let add_man =
  [
    `S Manpage.s_description;
    `P
      "Setup webhooks and permissions for a project so that it can be added to \
       tezos-ci.";
  ]

let validate (project_ids : string) =
  match project_ids with
  | "" -> []
  | _ ->
      let project_ids = String.split_on_char ',' project_ids in
      let converted = List.map int_of_string_opt project_ids in
      let converted' = List.filter_map (fun x -> x) converted in
      if List.length converted = List.length converted' then converted'
      else (
        eprintf "%S"
          "Error: Project-ids must be a comma separated list of integers.";
        exit Cmd.Exit.cli_error)

let add_term run =
  let combine token_file project_ids project_names =
    let project_ids = validate project_ids in
    let project_names = String.split_on_char ',' project_names in
    let token = String.trim @@ read_file token_file in
    { token; project_ids; project_names } |> run
  in
  Term.(const combine $ token_file $ project_ids $ project_names)

let add run =
  let info = Cmd.info "add" ~doc:add_doc ~man:add_man in
  Cmd.v info (add_term run)

let envs = Gitlab.Env.envs
let callback_url = "https://tezos.ci.dev/webhooks/gitlab"

let fail project_name =
  let err =
    Fmt.str "Unrecognised project name: %S. Expected format 'owner/name'"
      project_name
  in
  eprintf "%S" err;
  exit Cmd.Exit.some_error

let lookup_project ~token ~owner ~name =
  let project_name = Fmt.str "%s/%s" owner name in
  let (project_data : Gitlab_t.projects_short) =
    let cmd =
      let open Gitlab in
      let open Monad in
      let token = Gitlab.Token.AccessToken token in
      Project.by_name ~token ~owner ~name () >|~ fun x -> x
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  match project_data with
  | [] ->
      let err_msg = Fmt.str "No project found with name: %S" project_name in
      eprintf "%S" err_msg;
      exit Cmd.Exit.some_error
  | [ project ] -> project.project_short_id
  | _ :: _ ->
      let err_msg =
        Fmt.str "Internal Error -- Multiple projects returned with name: %S"
          project_name
      in
      eprintf "%S" err_msg;
      raise @@ Project_hook err_msg

let lookup_ids token names =
  List.map
    (fun project_name ->
      match String.split_on_char '/' project_name with
      | [] | [ _ ] -> fail project_name
      | [ owner; name ] -> lookup_project ~token ~owner ~name
      | _ :: _ -> fail project_name)
    names

let validate conf : int list =
  let err_msg = "Error: either specify project-ids or project-names" in
  match conf.project_ids with
  | [] -> (
      match conf.project_names with
      | [] | [ "" ] ->
          eprintf "%S" err_msg;
          exit Cmd.Exit.cli_error
      | _ :: _ -> lookup_ids conf.token conf.project_names)
  | _ :: _ -> (
      match conf.project_names with
      | [ "" ] | [] -> conf.project_ids
      | _ :: _ ->
          eprintf "%S" err_msg;
          exit Cmd.Exit.cli_error)

let add_projects =
  let project_hook_create (cmd_conf : Config.project_setup_conf) =
    let token = Gitlab.Token.AccessToken cmd_conf.token in
    let project_ids = validate cmd_conf in
    let cmds =
      let open Gitlab in
      let data : Gitlab_t.create_project_hook =
        {
          id = None;
          url = callback_url;
          enable_ssl_verification = Some true;
          push_events = Some true;
          merge_requests_events = Some true;
          tag_push_events = Some true;
          confidential_issues_events = None;
          confidential_note_events = None;
          deployment_events = None;
          issues_events = None;
          job_events = None;
          note_events = None;
          pipeline_events = None;
          push_events_branch_filter = None;
          releases_events = None;
          repository_update_events = None;
          wiki_page_events = None;
          token = None;
        }
      in
      let open Monad in
      List.map
        (fun project_id ->
          Project.Hook.create ~token ~project_id data () >|~ fun p ->
          printf "%s\n" "Created new hook";
          printf "Project: %d\n" project_id;
          printf "Hook-id: %d\n" p.id;
          printf "Callback-url: %S\n" p.url;
          printf "%s\n"
            "Events: push-events, merge-request-events, tag-push-events";
          printf "%s\n" "SSL-verification: enabled.")
        project_ids
    in
    List.iter (fun cmd -> Lwt_main.run @@ Gitlab.Monad.run cmd) cmds
  in
  add project_hook_create
