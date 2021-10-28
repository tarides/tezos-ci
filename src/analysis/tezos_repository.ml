let ( let* ) = Result.bind

let ( let+ ) r f = Result.map f r

module Active_protocol = struct
  type t = {
    name : string;
    (* 011-PtHangzH *)
    folder_name : string;
    (* 011_PtHangzH *)
    id : string;
    (* 011 *)
    slow_tests : string list;
  }
  [@@deriving yojson, ord]

  let pp f v = Fmt.pf f "%s" v.name

  let get version =
    let folder_name = version in
    let name = String.map (function '_' -> '-' | x -> x) folder_name in
    let id = List.hd (String.split_on_char '-' name) in

    let+ slow_tests =
      Result.join
      @@
      let is_slow_test_marker line =
        Astring.String.is_prefix ~affix:"@pytest.mark.slow" line
      in
      let tests_folder = Fpath.(v "tests_python" / ("tests_" ^ id)) in
      Bos.OS.Dir.fold_contents ~elements:`Files
        (fun path acc ->
          let* acc = acc in
          let filename = Fpath.basename path in
          if
            Astring.String.is_prefix ~affix:"test_" filename
            && Astring.String.is_suffix ~affix:".py" filename
          then
            let testname =
              let len = String.length filename in
              String.sub filename 5 (len - 5 - 3)
            in
            let+ content = Bos.OS.File.read_lines path in
            if List.exists is_slow_test_marker content then testname :: acc
            else acc
          else Ok acc)
        (Ok []) tests_folder
    in

    { slow_tests; folder_name; name; id }
end

module Version = struct
  type t = { build_deps_image_version : string } [@@deriving yojson]

  let parse () =
    let version_path = Fpath.v "scripts/version.sh" in
    let* version_file_content = Bos.OS.File.read_lines version_path in
    version_file_content
    |> List.find_map (fun line ->
           match String.split_on_char '=' line with
           | [ "export opam_repository_tag"; build_deps_image_version ]
           | [ "opam_repository_tag"; build_deps_image_version ] ->
               Some { build_deps_image_version }
           | _ -> None)
    |> Option.to_result
         ~none:
           (`Msg "Failed to find 'opam_repository_tag' in 'scripts/version.sh'")
end

type t = {
  all_protocols : string list;
  active_protocols : Active_protocol.t list;
  active_testing_protocol_versions : string list;
  lib_packages : string list;
  bin_packages : string list;
  version : Version.t;
}
[@@deriving yojson]

let marshal t = t |> to_yojson |> Yojson.Safe.to_string

let unmarshal t = t |> Yojson.Safe.from_string |> of_yojson |> Result.get_ok

let find_opam folder =
  Bos.OS.Dir.fold_contents ~elements:`Files
    (fun path acc ->
      let path, ext = Fpath.split_ext path in
      if ext = ".opam" then path :: acc else acc)
    [] folder

let find_all_protocols () =
  Bos.OS.Dir.fold_contents
    ~traverse:(`Sat (fun path -> Ok (List.length (Fpath.segs path) < 2)))
    ~elements:`Dirs
    (fun path acc ->
      let name = Fpath.basename path in
      let affix = "proto_" in
      if Astring.String.is_prefix ~affix name then
        (Astring.String.sub ~start:(String.length affix) name
        |> Astring.String.Sub.to_string)
        :: acc
      else acc)
    [] (Fpath.v "src")

let parse_protocol_file file =
  let+ lines = Bos.OS.File.read_lines file in
  List.map (String.map (function '-' -> '_' | x -> x)) lines

let make repo_path =
  Bos.OS.Dir.with_current repo_path
    (fun () ->
      (* opam-pin.sh *)
      let* opams_vendors = find_opam Fpath.(v "vendors") in
      let* opams_src = find_opam (Fpath.v "src") in
      let opams = opams_vendors @ opams_src in
      let bin_packages, lib_packages =
        List.partition
          (fun path ->
            let dir, _ = Fpath.split_base path in
            Fpath.to_string dir |> Astring.String.is_infix ~affix:"/bin_")
          opams
      in
      let bin_packages =
        List.map
          (fun path -> Fpath.split_base path |> snd |> Fpath.to_string)
          bin_packages
      in
      let lib_packages =
        List.map
          (fun path -> Fpath.split_base path |> snd |> Fpath.to_string)
          lib_packages
      in
      (* remove-old-protocols.sh *)
      let* all_protocols = find_all_protocols () in
      let* active_testing_protocol_versions =
        parse_protocol_file (Fpath.v "active_testing_protocol_versions")
      in
      let* active_protocol_versions =
        parse_protocol_file (Fpath.v "active_protocol_versions")
      in
      let* active_protocols =
        List.fold_left
          (fun rest v ->
            let* rest = rest in
            let+ v = Active_protocol.get v in
            v :: rest)
          (Ok []) active_protocol_versions
      in
      let* version = Version.parse () in
      Ok
        {
          all_protocols;
          active_testing_protocol_versions;
          active_protocols;
          bin_packages;
          lib_packages;
          version;
        })
    ()
  |> Result.join
