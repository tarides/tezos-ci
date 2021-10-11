type active_protocol = {
  name : string;
  (* 011-PtHangzH *)
  folder_name : string;
  (* 011_PtHangzH *)
  id : string;
  (* 011 *)
  slow_tests : string list;
}
[@@deriving yojson]

type t = {
  all_protocols : string list;
  active_protocols : active_protocol list;
  active_testing_protocol_versions : string list;
  lib_packages : string list;
  bin_packages : string list;
}
[@@deriving yojson]

let marshal t = Marshal.to_string t []

let unmarshal t = Marshal.from_string t 0

let ( let* ) = Result.bind

let ( let+ ) r f = Result.map f r

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

let get_active_protocol version =
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

let make repo_path =
  Bos.OS.Dir.with_current repo_path
    (fun () ->
      (* opam-pin.sh *)
      let* opams_vendors = find_opam Fpath.(v "vendors") in
      let* opams_src = find_opam (Fpath.v "src") in
      let opams = opams_vendors @ opams_src in
      let bin_packages, lib_packages =
        List.partition_map
          (fun path ->
            let dir, file = Fpath.split_base path in
            let file = Fpath.to_string file in
            if Fpath.to_string dir |> Astring.String.is_infix ~affix:"/bin_"
            then Left file
            else Right file)
          opams
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
            let+ v = get_active_protocol v in
            v :: rest)
          (Ok []) active_protocol_versions
      in
      Ok
        {
          all_protocols;
          active_testing_protocol_versions;
          active_protocols;
          bin_packages;
          lib_packages;
        })
    ()
  |> Result.join
