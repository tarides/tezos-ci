module Website_description = struct
  open Tyxml_html

  let handle_artifacts wildcard_path =
    object
      inherit Current_web.Resource.t

      method! private get_raw _ _ =
        Static.serve ~root:Current_ocluster.Artifacts.store wildcard_path
    end

  let extra_routes =
    Routes.[ (s "artifacts" /? wildcard) @--> handle_artifacts ]

  module Output = struct
    type t = Current_ocluster.Artifacts.t option

    open Tyxml_html

    let render_inline = function
      | Some artifacts ->
          a
            ~a:
              [
                a_href
                  (Current_ocluster.Artifacts.public_path artifacts
                  |> Fpath.to_string);
              ]
            [ txt "⤵️ artifacts " ]
      | None -> txt ""
  end

  module Node = struct
    type t = Lib.Task.task_metadata

    let render_inline { Lib.Task.name; _ } = txt name

    let map_status { Lib.Task.skippable; _ } =
      if not skippable then Fun.id
      else function
        | Error (`Msg _) -> Error `Skipped_failure
        | Error `Cancelled -> Error `Skipped_failure
        | v -> v
  end

  module Stage = struct
    type t = string

    let id name = name
    let render_inline name = txt name
    let render _ = txt ""
  end

  module Pipeline = struct
    type t = Pipeline.metadata

    let id (t : t) = Pipeline.Source.to_string t.source

    let render_inline (t : t) =
      let commit_hash = String.sub (Current_git.Commit_id.hash t.commit) 0 7 in
      txt (id t ^ " @" ^ commit_hash)

    let render (t : t) =
      div
        [
          txt "Link to ";
          a ~a:[ a_href (Pipeline.Source.link_to t.source) ] [ txt "Gitlab" ];
        ]
  end

  let render_index () =
    div
      [
        h1 [ txt "ꜩ Tezos CI" ];
        p
          [
            txt "Source code on Github: ";
            a
              ~a:[ a_href "https://github.com/TheLortex/tezos-ci" ]
              [ txt "TheLortex/tezos-ci" ];
          ];
      ]
end

include Current_web_pipelines.Web.Make (Website_description)
