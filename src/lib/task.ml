type 'a status =
  ( 'a,
    [ `Active of [ `Running | `Ready ]
    | `Msg of string
    | `Cancelled
    | `Blocked
    | `Skipped of string ] )
  result

let status_of_state_and_metadata state metadata =
  match (state, metadata) with
  | Ok v, _ -> Ok v
  | (Error (`Skipped _) as e), _ -> e
  | Error _, Some { Current.Metadata.job_id = None; _ } -> Error `Blocked
  | Error _, None -> Error `Blocked
  | (Error (`Active _) as e), _ -> e
  | Error (`Msg "Cancelled"), _ -> Error `Cancelled
  | (Error (`Msg _) as e), _ -> e

let to_int = function
  | Error (`Skipped _) -> 0
  | Ok _ -> 1
  | Error `Blocked -> 2
  | Error (`Active `Ready) -> 3
  | Error (`Active `Running) -> 4
  | Error `Cancelled -> 5
  | Error (`Msg _) -> 6

let status_of_list =
  List.fold_left
    (fun v new_v -> if to_int new_v > to_int v then new_v else v)
    (Error (`Skipped "no task to do"))

type subtask_value =
  | Item of (unit status * Current.Metadata.t option)
  | Stage of subtask_node list

and subtask_node = { name : string; value : subtask_value }

let rec status = function
  | { value = Item (status, _); _ } -> status
  | { value = Stage subtasks; _ } ->
      subtasks |> List.map status |> status_of_list

let item ~name ?metadata item = { name; value = Item (item, metadata) }
let group ~name items = { name; value = Stage items }

type t = { current : unit Current.t; subtasks_status : subtask_node Current.t }

let v current subtasks_status = { current; subtasks_status }

(* TODO: cmdline *)
let skip_failures = true

let maybe_catch current =
  if skip_failures then
    Current.catch ~hidden:true current |> Current.map (fun _ -> ())
  else current

let single_c ~name current =
  let open Current.Syntax in
  let subtasks_status =
    let+ state = Current.state ~hidden:true current
    and+ metadata = Current.Analysis.metadata current
    and+ name = name in
    status_of_state_and_metadata state metadata |> item ~name ?metadata
  in
  { current = maybe_catch current; subtasks_status }

let single ~name current =
  let open Current.Syntax in
  let subtasks_status =
    let+ state = Current.state ~hidden:true current
    and+ metadata = Current.Analysis.metadata current in
    status_of_state_and_metadata state metadata |> item ~name ?metadata
  in
  { current = maybe_catch current; subtasks_status }

let list_iter (type a) ~collapse_key
    (module S : Current_term.S.ORDERED with type t = a) fn values =
  let fn_take_current v =
    let v = fn v in
    v.current
  in
  let fn_take_status v =
    let v = fn v in
    v.subtasks_status
  in

  let current =
    Current.list_iter ~collapse_key (module S) fn_take_current values
  in
  let status =
    Current.list_map ~collapse_key (module S) fn_take_status values
    |> Current.map (fun items -> group ~name:collapse_key items)
  in
  v current status

let all ~name tasks =
  let current = List.map (fun t -> t.current) tasks |> Current.all in
  let status =
    let open Current.Syntax in
    let+ items = List.map (fun t -> t.subtasks_status) tasks |> Current.list_seq
    and+ name = name in
    group ~name items
  in
  v current status

let skip ~name reason =
  {
    current = Current.return ();
    subtasks_status =
      Current.return { name; value = Item (Error (`Skipped reason), None) };
  }
