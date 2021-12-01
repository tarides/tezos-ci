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

    (* TODO: provide marshalling in Current_ocluster.Artifacts.t *)
    let marshal v = Marshal.to_string v []
    let unmarshal v = Marshal.from_string v 0
  end

  module Node = struct
    open Lib.Task

    type t = task_metadata

    let render_inline { name; skippable } =
      if skippable then i [ txt name ] else txt name

    let map_status { skippable; _ } =
      if not skippable then Fun.id
      else function
        | Error (`Msg _) -> Error `Skipped_failure
        | Error `Cancelled -> Error `Skipped_failure
        | v -> v

    let marshal { name; skippable } =
      `Assoc [ ("name", `String name); ("skippable", `Bool skippable) ]
      |> Yojson.Safe.to_string

    let unmarshal str =
      let json = Yojson.Safe.from_string str in
      let open Yojson.Safe.Util in
      let name = member "name" json |> to_string in
      let skippable = member "skippable" json |> to_bool in
      { name; skippable }
  end

  module Stage = struct
    type t = string

    let id name = name
    let render_inline name = txt name
    let render _ = txt ""
    let marshal = Fun.id
    let unmarshal = Fun.id
  end

  module Pipeline = struct
    open Pipeline

    module Group = struct
      type t = Merge_request | Branch | Tag | Other

      let id = function
        | Merge_request -> "mr"
        | Branch -> "b"
        | Tag -> "t"
        | Other -> "o"

      let to_string = function
        | Merge_request -> "Merge request"
        | Branch -> "Branch"
        | Tag -> "Tag"
        | Other -> "Other"
    end

    module Source = struct
      include Source

      let group = function
        | Schedule _ -> Group.Other
        | Branch _ -> Branch
        | Tag _ -> Tag
        | Merge_request _ -> Merge_request

      let id = Source.id
    end

    type t = metadata

    let id t = Current_git.Commit_id.hash t.commit
    let source t = t.source

    let marshal { source; commit } =
      `Assoc
        [
          ("repo", `String (Current_git.Commit_id.repo commit));
          ("hash", `String (Current_git.Commit_id.hash commit));
          ("gref", `String (Current_git.Commit_id.gref commit));
          ("source", `String (Source.marshal source));
        ]
      |> Yojson.Safe.to_string

    let unmarshal str =
      let json = Yojson.Safe.from_string str in
      let open Yojson.Safe.Util in
      let repo = member "repo" json |> to_string in
      let hash = member "hash" json |> to_string in
      let gref = member "gref" json |> to_string in
      let source = member "source" json |> to_string in
      {
        source = Source.unmarshal source;
        commit = Current_git.Commit_id.v ~repo ~gref ~hash;
      }

    let render_inline (t : t) =
      let commit_hash = String.sub (Current_git.Commit_id.hash t.commit) 0 7 in
      txt ("@" ^ commit_hash)

    let render (t : t) =
      div
        [
          txt "Link to ";
          a ~a:[ a_href (Source.link_to t.source) ] [ txt "Gitlab" ];
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
