open Current_web_pipelines

type task_metadata = { name : string; skippable : bool }

type t =
  ( unit,
    (Current_ocluster.Artifacts.t option, task_metadata) State.job_tree )
  Task.t

let all ~name (t : t list) : t =
  let open Current_web_pipelines in
  let v = t |> Task.all in
  let state =
    let open Current.Syntax in
    let+ lst = Task.state v and+ name = name in
    State.job_tree_group { name; skippable = false } lst
  in
  Task.v ~current:(Task.current v) ~state

let single ~name t =
  Task.single { name; skippable = false } t |> Task.map_current ignore

let single_c ~name t =
  let metadata = Current.map (fun name -> { name; skippable = false }) name in
  Task.single_c metadata t |> Task.map_current ignore

let allow_failures t =
  let current =
    Task.current t
    |> Current.map_error (fun _ -> "failure allowed")
    |> Current.state ~hidden:true
    |> Current.map (fun _ -> ())
  in
  let state =
    Task.state t
    |> Current.map (fun (s : _ State.job_tree) ->
           { s with metadata = { s.metadata with skippable = true } })
  in
  Task.v ~current ~state

let list_iter (type a) ~collapse_key
    (module S : Current_term.S.ORDERED with type t = a) fn values =
  Task.list_iter ~collapse_key (module S) fn values
  |> Task.map_state (fun lst ->
         State.job_tree_group { name = collapse_key; skippable = false } lst)

let skip ~name reason =
  let current = Current.return () in
  let state =
    Current.return
      {
        State.node = Item { result = Error (`Skipped reason); metadata = None };
        metadata = { name; skippable = false };
      }
  in
  Task.v ~current ~state
