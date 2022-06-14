(* TODO
   1. Copy styling from ocurrent_web github page
   2. Convert sha to branch/ref name
   3. Summarise build status 
 *)

let org_url owner =
  Printf.sprintf "/gitlab/%s" owner

module Index = Ocaml_ci.Index

let breadcrumbs steps page_title =
  let open Tyxml.Html in
  let add (prefix, results) (label, link) =
    let prefix = Printf.sprintf "%s/%s" prefix link in
    let link = li [a ~a:[a_href prefix] [txt label]] in
    (prefix, link :: results)
  in
  let _, steps = List.fold_left add ("", []) steps in
  let steps = li [b [txt page_title]] :: steps in
  ol ~a:[a_class ["breadcrumbs"]] (
      List.rev steps
    )

let render_project_ci_ref project_owner project_name (name, hash) =
  let open Tyxml_html in
  [a ~a:[a_href (Fmt.str "/gitlab/%s/%s/commit/%s" project_owner project_name hash)] [txt (Fmt.str "%s" name)]]

let handle_owner_project ~engine:_ owner project = object
    inherit Current_web.Resource.t

    method! private get ctx =
      let open Tyxml_html in 
     
      let refs =
        Index.get_active_refs { Ocaml_ci.Repo_id.owner; name = project }
        |> Index.Ref_map.bindings
        |> List.map (fun p -> li (render_project_ci_ref owner project p))
      in
      Current_web.Context.respond_ok ctx @@ [
          breadcrumbs ["gitlab", "gitlab";
                       owner, owner;
                       project, project;] project;
          div [
              h3 [txt (Fmt.str "CI Refs for %s/%s" owner project)];
              ul refs
            ]
        ]
  end

let format_org org =
  let open Tyxml.Html in
  li [a ~a:[a_href (org_url org)] [txt org]]

let list_orgs ctx =
  let orgs = Ocaml_ci_gitlab.Pipeline.gitlab_repos in
  let body = Tyxml.Html.[
        breadcrumbs [] "gitlab";
        ul (List.map (fun org -> format_org org.Current_gitlab.Repo_id.name) orgs)
             ] in
  Current_web.Context.respond_ok ctx body

let render_project (project : Current_gitlab.Repo_id.t) =
  let open Tyxml_html in
  [h4 [a ~a:[a_href (Fmt.str "/gitlab/%s/%s" project.owner project.name)] [txt (Fmt.str "%s/%s" project.owner project.name)]]]

let handle_list_owners ~engine:_ = object 
    inherit Current_web.Resource.t
    method! nav_link = Some "Gitlab Projects"
    method! private get ctx =
      let open Tyxml_html in
      let projects = Ocaml_ci_gitlab.Pipeline.gitlab_repos in
      
      Current_web.Context.respond_ok ctx @@ [
          breadcrumbs [] "gitlab";
          div [
            h3 [ txt ("GitLab Projects:")]];
            ul (List.map (fun p -> li (render_project p)) projects)
        ]
  end

let handle_owner ~engine:_ owner = object
    inherit Current_web.Resource.t
    method! private get ctx =
      let open Tyxml_html in
      let projects = Ocaml_ci_gitlab.Pipeline.gitlab_repos
                     |> List.filter (fun (x :Current_gitlab.Repo_id.t) -> String.equal x.owner owner) in
      
      Current_web.Context.respond_ok ctx @@ [
          breadcrumbs ["gitlab", "gitlab";
                       owner, owner;] owner;
          div [
              h3 [ txt ("GitLab Projects:")]];
          ul (List.map (fun p -> li (render_project p)) projects)
        ]
  end

let render_variant job_id (variant, job_state) =
  let open Tyxml_html in
  [a ~a:[a_href (Fmt.str "/job/%s" (Option.value job_id ~default:""))]
     [txt (Fmt.str "%s / %s" variant (Index.show_job_state job_state))]]

let handle_project_commit ~engine:_ owner project hash = object
    inherit Current_web.Resource.t 
    method! private get ctx = 
      let open Tyxml_html in

      let job_of_variant variant =
        match Index.get_job ~owner ~name:project ~hash ~variant with
        | Error `No_such_variant -> None
        | Ok None -> None
        | Ok (Some id) -> Some id
      in

      let variants =
        Index.get_jobs ~owner ~name:project hash 
        |> List.map (fun j -> li (render_variant (job_of_variant (fst j)) j)) in
      let body = [
          div [
              h3 [txt (Fmt.str "for branch (%s)" hash)];
              ul variants
            ]
        ] in
      Current_web.Context.respond_ok ctx body
  end

let routes ~engine =
  Routes.[
      s "gitlab" /? nil @--> handle_list_owners ~engine;
      s "gitlab" / str /? nil @--> handle_owner ~engine;
      s "gitlab" / str / str /? nil @--> handle_owner_project ~engine;
      s "gitlab" / str / str /s "commit" / str /? nil @--> handle_project_commit ~engine;
  ]