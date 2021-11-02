module StringMap = Map.Make (String)

type t = Stages.Task.subtask_node StringMap.t ref

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

let list_pipelines ~state =
  let open Tyxml_html in
  let show_pipeline (name, ppl) =
    [
      h2
        [
          emoji_of_status (Stages.Task.status ppl);
          a ~a:[ a_href ("/pipelines/" ^ name) ] [ txt name ];
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
    match ppl.Stages.Task.value with
    | Item _ -> assert false
    | Stage stages -> stages
  in
  let open Tyxml_html in
  [
    h1 [ txt ("Pipeline " ^ name) ];
    h2 [ txt "Stages:" ];
    ul
      (List.map
         (fun (stage : Stages.Task.subtask_node) ->
           li
             [
               emoji_of_status (Stages.Task.status stage);
               a
                 ~a:[ a_href ("/pipelines/" ^ name ^ "/" ^ stage.name) ]
                 [ txt stage.name ];
             ])
         stages);
  ]

let rec get_job_tree (stage : Stages.Task.subtask_node) =
  let emoji = emoji_of_status (Stages.Task.status stage) in
  let open Tyxml_html in
  match stage.value with
  | Item (_, Some { Current.Metadata.job_id = Some job_id; _ }) ->
      [
        emoji;
        txt stage.name;
        a ~a:[ a_href ("/job/" ^ job_id) ] [ txt "=> job" ];
      ]
  | Item _ -> [ emoji; txt stage.name ]
  | Stage rest ->
      [
        emoji; txt stage.name; ul (List.map (fun v -> li (get_job_tree v)) rest);
      ]

let show_pipeline_task ~state name stage_name =
  let pipeline = StringMap.find name !state in
  let stages =
    match pipeline.Stages.Task.value with
    | Item _ -> assert false
    | Stage stages -> stages
  in
  let stage = List.find (fun t -> t.Stages.Task.name = stage_name) stages in

  let open Tyxml_html in
  [
    h1
      [
        emoji_of_status (Stages.Task.status pipeline);
        a ~a:[ a_href ("/pipelines/" ^ name) ] [ txt ("Pipeline " ^ name) ];
      ];
    h2
      [
        emoji_of_status (Stages.Task.status stage); txt ("Stage " ^ stage_name);
      ];
    h3 [ txt "Job tree" ];
    div (get_job_tree stage);
  ]

let internal_routes ~state =
  Routes.
    [
      empty @--> list_pipelines ~state;
      (str /? nil) @--> show_pipeline ~state;
      (str / str /? nil) @--> show_pipeline_task ~state;
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

let routes t =
  Routes.
    [
      (s "pipelines" /? nil) @--> handle t (Parts.of_parts "");
      (s "pipelines" /? wildcard) @--> handle t;
    ]
