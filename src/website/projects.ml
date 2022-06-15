(* TODO
   1. Copy styling from ocurrent_web github page (DONE ?)
   2. Convert sha to branch/ref name (DONE)
   3. Summarise build status (DONE)
   4. Standardise naming of Repo.owner name across the module
 *)

(* TODO Sections:

   1. HTML rendering
   2. Data lookup
   3. Transformation functions
   4. web route handlers
   5. routes

 *)

let gitlab_branch_url ~owner ~name ref =
  Printf.sprintf "https://gitlab.com/%s/%s/-/tree/%s" owner name ref

let gitlab_mr_url ~owner ~name id =
  Printf.sprintf "https://gitlab.com/%s/%s/-/merge_requests/%s" owner name id

let org_url owner =
  Fmt.str "/gitlab/%s" owner

(* TODO We could look this up via GitLab API. *)
let default_branch_ref =  "refs/heads/master"

let breadcrumbs steps page_title =
  let open Tyxml.Html in
  let add (prefix, results) (label, link) =
    let prefix = Fmt.str "%s/%s" prefix link in
    let link = li [a ~a:[a_href prefix] [txt label]] in
    (prefix, link :: results)
  in
  let _, steps = List.fold_left add ("", []) steps in
  let steps = li [b [txt page_title]] :: steps in
  ol ~a:[a_class ["breadcrumbs"]] (
      List.rev steps
    )

let short_hash = Astring.String.with_range ~len:6

module Index = Ocaml_ci.Index

let render_status = function
  | `Not_started -> "not-started"
  | `Pending -> "active"
  | `Failed -> "failed"
  | `Passed -> "passed"

let rec intersperse ~sep = function
  | [] -> []
  | [x] -> [x]
  | x :: xs -> x :: sep :: intersperse ~sep xs

let link_github_refs ~owner ~name =
  let open Tyxml.Html in
  function
  | [] -> txt "(not at the head of any monitored branch or PR)"
  | refs ->
     p (
         txt "(for " ::
           (
             intersperse ~sep:(txt ", ") (
                 refs |> List.map @@ fun (r, _) ->
                                     match Astring.String.cuts ~sep:"/" r with
                                     | "refs"::"heads"::branch ->
                                        let branch = String.concat "/" branch in
                                        span [txt "branch "; a ~a:[a_href (gitlab_branch_url ~owner ~name branch)] [ txt branch ]]
                                     | ["refs"; "merge-requests"; id; "head"] ->
                                        span [txt "MR "; a ~a:[a_href (gitlab_mr_url ~owner ~name id)] [ txt ("#" ^ id) ]]
                                     | _ ->
                                        txt (Printf.sprintf "Bad ref format %S" r)
               )
           ) @
           [txt ")"]
       )

let render_project_ci_ref project_owner project_name (name, hash) build_status =
  let open Tyxml_html in
  li ~a:[a_class [render_status build_status]]
    [a ~a:[a_href (Fmt.str "/gitlab/%s/%s/commit/%s" project_owner project_name hash)] [txt (Fmt.str "%s" name)]]

let render_job_status = function
  | `Not_started -> "not-started"
  | `Aborted -> "aborted"
  | `Failed m when Astring.String.is_prefix ~affix:"[SKIP]" m -> "skipped"
  | `Failed _ -> "failed"
  | `Passed -> "passed"
  | `Active -> "active"

let render_variant job_id (variant, job_state) =
  let open Tyxml_html in
  li ~a:[a_class [render_job_status job_state]]
    [a ~a:[a_href (Fmt.str "/job/%s" (Option.value job_id ~default:""))]
       [txt (Fmt.str "%s (%s)" variant (render_job_status job_state))]]

let render_owner owner =
  let open Tyxml_html in
  [a ~a:[a_href (Fmt.str "%s" (org_url owner) )] [txt (Fmt.str "%s" owner)]]

let render_project (project : Current_gitlab.Repo_id.t) build_status =
  let open Tyxml_html in
  li ~a:[a_class [Option.map render_status build_status |> Option.value ~default:"not-started" ]]
    [a ~a:[a_href (Fmt.str "/gitlab/%s/%s" project.owner project.name)]
       [txt (Fmt.str "%s/%s" project.owner project.name)]]

let render_org org =
  let open Tyxml.Html in
  li [a ~a:[a_href (org_url org)] [txt org]]

let handle_owner_project owner project = object
    inherit Current_web.Resource.t
    method! nav_link = Some "Gitlab Projects"
    method! private get ctx =
      let open Tyxml_html in 
      let refs =
        Index.get_active_refs { Ocaml_ci.Repo_id.owner; name = project }
        |> Index.Ref_map.bindings
        |> List.map (fun p -> 
               let build_status = Index.get_status ~owner ~name:project ~hash:(snd p) in
               render_project_ci_ref owner project p build_status)
      in
      Current_web.Context.respond_ok ctx @@ [
          breadcrumbs ["gitlab", "gitlab"; owner, owner;] project;
          div [ ul ~a:[a_class ["statuses"]] refs ]
        ]
  end

let handle_list_owners = object 
    inherit Current_web.Resource.t
    method! nav_link = Some "Gitlab Projects"
    method! private get ctx =
      let open Tyxml_html in
      let projects = Ocaml_ci_gitlab.Pipeline.gitlab_repos 
                     |> List.map (fun (x : Current_gitlab.Repo_id.t) -> x.owner) 
                     |> List.sort_uniq String.compare in
      
      Current_web.Context.respond_ok ctx @@ [
          breadcrumbs [] "gitlab";
          div [ul (List.map (fun p -> li (render_owner p)) projects)]
        ]
  end

let handle_owner owner = object
    inherit Current_web.Resource.t
    method! nav_link = Some "Gitlab Projects"
    method! private get ctx =
      let open Tyxml_html in
      let projects = Ocaml_ci_gitlab.Pipeline.gitlab_repos
                     |> List.filter (fun (x :Current_gitlab.Repo_id.t) -> String.equal x.owner owner) in
      
      let build_status name = Index.get_active_refs { Ocaml_ci.Repo_id.owner; name  } 
                       |> Index.Ref_map.find_opt default_branch_ref
                       |> Option.map (fun hash -> Index.get_status ~owner ~name ~hash) in

      Current_web.Context.respond_ok ctx @@ [
          breadcrumbs ["gitlab", "gitlab"] owner;
          ul ~a:[a_class ["statuses"]] 
            (List.map (fun p -> render_project p (build_status p.Current_gitlab.Repo_id.name)) projects) 
        ]
  end

let handle_project_commit owner name hash = object
    inherit Current_web.Resource.t 
    method! nav_link = Some "Gitlab Projects"
    method! private get ctx = 
      let open Tyxml_html in

      let job_of_variant variant =
        match Index.get_job ~owner ~name ~hash ~variant with
        | Error `No_such_variant -> None
        | Ok None -> None
        | Ok (Some id) -> Some id
      in

      let refs =
        Index.get_active_refs { Ocaml_ci.Repo_id.owner; name }
        |> Index.Ref_map.bindings
        |> List.filter (fun (_, y) -> String.equal y hash)
      in

      let variants =
        Index.get_jobs ~owner ~name hash 
        |> List.map (fun j -> render_variant (job_of_variant (fst j)) j) in

      let body = [
          breadcrumbs ["gitlab", "gitlab";
                       owner, owner;
                       name, name;
            ] (short_hash hash);
          link_github_refs ~owner ~name refs;
          ul ~a:[a_class ["statuses"]] variants
        ] in
      Current_web.Context.respond_ok ctx body
  end

let routes =
  Routes.[
      s "gitlab" /? nil @--> handle_list_owners ;
      s "gitlab" / str /? nil @--> handle_owner ;
      s "gitlab" / str / str /? nil @--> handle_owner_project ;
      s "gitlab" / str / str /s "commit" / str /? nil @--> handle_project_commit ;
  ]