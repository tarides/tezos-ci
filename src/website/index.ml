open Lib
module StringMap = Map.Make (String)

type t = Task.subtask_node StringMap.t ref

let make () = ref StringMap.empty

let update_state state ~id new_state =
  let open Current.Syntax in
  let+ id = id and+ new_state = new_state in
  state := StringMap.add id new_state !state

(* rendering *)

let emoji_of_status =
  let open Tyxml_html in
  function
  | Ok _ -> span ~a:[ a_title "OK" ] [ txt "✔️ " ]
  | Error (`Active `Ready) -> span ~a:[ a_title "Ready" ] [ txt "🟡 " ]
  | Error (`Active `Running) -> span ~a:[ a_title "Running" ] [ txt "🟠 " ]
  | Error `Blocked -> span ~a:[ a_title "Blocked" ] [ txt "🔘 " ]
  | Error `Cancelled -> span ~a:[ a_title "Cancelled" ] [ txt "🛑 " ]
  | Error (`Msg msg) -> span ~a:[ a_title ("Error: " ^ msg) ] [ txt "❌ " ]
  | Error (`Skipped msg) -> span ~a:[ a_title ("Skipped: " ^ msg) ] [ txt "⚪ " ]
  | Error `Skipped_failure -> span ~a:[ a_title "Skipped failure" ] [ txt "⏹ " ]

module Run_time = struct
  let duration_pp ppf t =
    let hour = 3600_000_000_000L in
    let day = Int64.mul 24L hour in
    let year = Int64.mul 8766L hour in
    let open Duration in
    let min = to_min t in
    if min > 0 then
      let y = to_year t in
      let left = Int64.rem t year in
      let d = to_day left in
      let left = Int64.rem left day in
      if y > 0 then Format.fprintf ppf "%da%dd" y d
      else
        let h = to_hour left in
        let left = Int64.rem left hour in
        if d > 0 then Format.fprintf ppf "%dd%02dh" d h
        else
          let min = to_min left in
          let left = Int64.sub t (of_min min) in
          let sec = to_sec left in
          if h > 0 then Format.fprintf ppf "%dh%02dm" h min
          else (* if m > 0 then *)
            Format.fprintf ppf "%dm%02ds" min sec
    else
      (* below one minute *)
      let fields t =
        let sec = to_sec_64 t in
        let left = Int64.sub t (of_sec_64 sec) in
        let ms = to_ms_64 left in
        let left = Int64.sub left (of_ms_64 ms) in
        let us = to_us_64 left in
        let ns = Int64.(sub left (of_us_64 us)) in
        (sec, ms, us, ns)
      in
      let s, ms, us, ns = fields t in
      if s > 0L then Format.fprintf ppf "%Lds" s
      else if ms > 0L then Format.fprintf ppf "%Ldms" ms
      else (* if us > 0 then *)
        Format.fprintf ppf "%Ld.%03Ldus" us ns

  type t =
    | No_info
    | Running_since of float
    | Finished of { ready : float; running : float option; finished : float }

  let pp f = function
    | No_info -> ()
    | Running_since v ->
        Fmt.pf f " (running for %a)" duration_pp
          (Duration.of_f (Unix.gettimeofday () -. v))
    | Finished { ready; running = None; finished } ->
        Fmt.pf f " (%a queued)" duration_pp (Duration.of_f (finished -. ready))
    | Finished { running = Some running; finished; _ } ->
        Fmt.pf f " (%a)" duration_pp (Duration.of_f (finished -. running))

  let to_string = Fmt.to_to_string pp

  let of_job job_id =
    match Current.Job.lookup_running job_id with
    | Some job -> (
        match Lwt.state (Current.Job.start_time job) with
        | Lwt.Sleep | Lwt.Fail _ -> No_info
        | Lwt.Return t -> Running_since t)
    | None -> (
        let results = Current_cache.Db.query ~job_prefix:job_id () in
        match results with
        | [ { Current_cache.Db.ready; running; finished; _ } ] ->
            Finished { ready; running; finished }
        | _ -> No_info)

  let merge t1 t2 =
    match (t1, t2) with
    | No_info, t2 -> t2
    | t1, No_info -> t1
    | Running_since v1, Running_since v2 -> Running_since (Float.min v1 v2)
    | Running_since v1, Finished { ready; _ } ->
        Running_since (Float.min v1 ready)
    | Finished { ready; _ }, Running_since v2 ->
        Running_since (Float.min ready v2)
    | Finished v1, Finished v2 ->
        Finished
          {
            ready = Float.min v1.ready v2.ready;
            running =
              (match (v1.running, v2.running) with
              | None, None -> None
              | Some v1, None -> Some v1
              | None, Some v2 -> Some v2
              | Some v1, Some v2 -> Some (Float.min v1 v2));
            finished = Float.max v1.finished v2.finished;
          }

  module Syntax = struct
    let ( let+ ) (v, run_time) f = (f v, run_time)
  end
end

let maybe_artifacts =
  let open Tyxml_html in
  function
  | Ok (Some artifacts) ->
      span
        [
          txt "  ";
          a
            ~a:
              [
                a_href
                  (Current_ocluster.Artifacts.public_path artifacts
                  |> Fpath.to_string);
              ]
            [ txt "⤵️ artifacts " ];
        ]
  | _ -> txt ""

let rec get_job_tree ~uri_base (stage : Task.subtask_node) =
  let open Run_time.Syntax in
  let status = Task.status stage in
  let emoji = emoji_of_status (Task.status stage) in
  let open Tyxml_html in
  match (stage, status) with
  | Failure_allowed node, Error `Skipped_failure ->
      let+ child = get_job_tree ~uri_base node in
      [
        div
          ~a:[ a_style "display: flex" ]
          [
            div
              ~a:[ a_style "margin-right: 0.5rem" ]
              [ emoji; i [ txt "skipped" ] ];
            div child;
          ];
      ]
  | Failure_allowed node, _ -> get_job_tree ~uri_base node
  | Node stage, _ -> (
      match stage.value with
      | Item (artifacts, Some { Current.Metadata.job_id = Some job_id; _ }) ->
          let run_time_info = Run_time.of_job job_id in
          ( [
              emoji;
              a ~a:[ a_href (uri_base ^ "/" ^ job_id) ] [ txt stage.name ];
              i [ txt (Run_time.to_string run_time_info) ];
              maybe_artifacts artifacts;
            ],
            run_time_info )
      | Item _ -> ([ emoji; txt stage.name ], Run_time.No_info)
      | Stage rest ->
          let children_nodes, run_time_info =
            List.map (get_job_tree ~uri_base) rest |> List.split
          in
          let run_time_info =
            List.fold_left Run_time.merge Run_time.No_info run_time_info
          in
          ( [
              emoji;
              txt stage.name;
              i [ txt (Run_time.to_string run_time_info) ];
              ul (List.map li children_nodes);
            ],
            run_time_info ))

let list_pipelines ~state =
  let open Tyxml_html in
  let show_pipeline (name, ppl) =
    let _, run_time = get_job_tree ~uri_base:"" ppl in
    [
      h2
        [
          emoji_of_status (Task.status ppl);
          a ~a:[ a_href ("/pipelines/" ^ name) ] [ txt name ];
          i [ txt (Run_time.to_string run_time) ];
        ];
    ]
  in
  [
    h1 [ txt "Pipelines" ];
    ul
      (List.map
         (fun binding -> li (show_pipeline binding))
         (StringMap.bindings !state));
  ]

let show_pipeline ~state name =
  let ppl = StringMap.find name !state in
  let stages =
    match ppl with
    | Task.Failure_allowed _ | Node { value = Item _; _ } -> assert false
    | Node { value = Stage stages; _ } -> stages
  in
  let open Tyxml_html in
  [
    h1 [ txt ("Pipeline " ^ name) ];
    h2 [ txt "Stages:" ];
    ul
      (List.map
         (fun (stage : Task.subtask_node) ->
           let _, run_time = get_job_tree ~uri_base:"" stage in
           li
             [
               emoji_of_status (Task.status stage);
               a
                 ~a:
                   [ a_href ("/pipelines/" ^ name ^ "/" ^ Task.sub_name stage) ]
                 [ txt (Task.sub_name stage) ];
               i [ txt (Run_time.to_string run_time) ];
             ])
         stages);
  ]

let show_pipeline_task ~state name stage_name =
  let pipeline = StringMap.find name !state in
  let stages =
    match pipeline with
    | Task.Failure_allowed _ | Node { value = Item _; _ } -> assert false
    | Node { value = Stage stages; _ } -> stages
  in
  let stage = List.find (fun t -> Task.sub_name t = stage_name) stages in
  let job_tree, _run_time_info =
    get_job_tree ~uri_base:("/pipelines/" ^ name ^ "/" ^ stage_name) stage
  in
  let open Tyxml_html in
  [
    h1
      [
        emoji_of_status (Task.status pipeline);
        a ~a:[ a_href ("/pipelines/" ^ name) ] [ txt ("Pipeline " ^ name) ];
      ];
    h2 [ emoji_of_status (Task.status stage); txt ("Stage " ^ stage_name) ];
    h3 [ txt "Job tree" ];
    div job_tree;
  ]

let get_job_text job_id =
  let path = Current.Job.log_path job_id |> Result.get_ok in
  let max_log_chunk_size = 102400L in
  (* ocurrent/lib_web/job.ml *)
  let ch = open_in_bin (Fpath.to_string path) in
  Fun.protect ~finally:(fun () -> close_in ch) @@ fun () ->
  let len = LargeFile.in_channel_length ch in
  LargeFile.seek_in ch 0L;
  let truncated = if max_log_chunk_size < len then "\n(truncated)" else "" in
  let len = min max_log_chunk_size len in
  really_input_string ch (Int64.to_int len) ^ truncated

let show_pipeline_task_job ~state name stage_name wildcard =
  let job_id =
    let wld = Routes.Parts.wildcard_match wildcard in
    String.sub wld 1 (String.length wld - 1)
  in
  let pipeline = StringMap.find name !state in
  let stages =
    match pipeline with
    | Task.Failure_allowed _ | Node { value = Item _; _ } -> assert false
    | Node { value = Stage stages; _ } -> stages
  in
  let stage = List.find (fun t -> Task.sub_name t = stage_name) stages in
  let job_tree, _run_time_info =
    get_job_tree ~uri_base:("/pipelines/" ^ name ^ "/" ^ stage_name) stage
  in

  let open Tyxml_html in
  [
    div
      ~a:[ a_style "display: flex;" ]
      [
        div ~a:[ a_style "width: 50%" ]
          [
            h1
              [
                emoji_of_status (Task.status pipeline);
                a
                  ~a:[ a_href ("/pipelines/" ^ name) ]
                  [ txt ("Pipeline " ^ name) ];
              ];
            h2
              [
                emoji_of_status (Task.status stage);
                a
                  ~a:[ a_href ("/pipelines/" ^ name ^ "/" ^ stage_name) ]
                  [ txt ("Stage " ^ stage_name) ];
              ];
            h3 [ txt "Job tree" ];
            div job_tree;
          ];
        div ~a:[ a_style "width: 50%" ]
          [
            h2 [ txt "Job log" ];
            a
              ~a:[ a_href ("/job/" ^ job_id) ]
              [ txt "See full log and operations" ];
            pre [ txt (get_job_text job_id) ];
          ];
      ];
  ]

let internal_routes ~state =
  Routes.
    [
      empty @--> list_pipelines ~state;
      (str /? nil) @--> show_pipeline ~state;
      (str / str /? nil) @--> show_pipeline_task ~state;
      (str / str /? wildcard) @--> show_pipeline_task_job ~state;
    ]

let handle state wildcard_path =
  object
    inherit Current_web.Resource.t
    method! nav_link = Some "Pipelines"

    method! private get context =
      let target = Routes.Parts.wildcard_match wildcard_path in
      let response =
        Routes.one_of (internal_routes ~state)
        |> Routes.match' ~target
        |> Option.value ~default:[ Tyxml_html.txt "not found" ]
      in
      Current_web.Context.respond_ok context response
  end

let handle_artifacts wildcard_path =
  object
    inherit Current_web.Resource.t

    method! private get_raw _ _ =
      Static.serve ~root:Current_ocluster.Artifacts.store wildcard_path
  end

let routes t =
  Routes.
    [
      (s "pipelines" /? nil) @--> handle t (Parts.of_parts "");
      (s "pipelines" /? wildcard) @--> handle t;
      (s "artifacts" /? wildcard) @--> handle_artifacts;
    ]
