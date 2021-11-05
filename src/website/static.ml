open Lwt.Syntax

let return_404 () =
  Lwt.return
    ( Cohttp_lwt.Response.make ~status:`Not_found (),
      Cohttp_lwt.Body.of_string "Not found\n" )

let stream_file_content channel =
  let stream, push = Lwt_stream.create_bounded 2 in
  Lwt.async (fun () ->
      let rec loop () =
        let* v = Lwt_io.read ~count:(64 * 1024) channel in
        match v with
        | "" ->
            push#close;
            Lwt_io.close channel
        | v ->
            let* () = push#push v in
            loop ()
      in
      loop ());
  stream

let serve_file path =
  Lwt.catch
    (fun () ->
      let mime_type = Magic_mime.lookup (Fpath.to_string path) in
      let* channel = Lwt_io.open_file ~mode:Input (Fpath.to_string path) in
      let* size = Lwt_io.length channel in
      let headers =
        Cohttp.Header.of_list
          [
            ("Content-Length", Int64.to_string size); ("Content-Type", mime_type);
          ]
      in
      let content = stream_file_content channel in
      Lwt.return
        (Cohttp_lwt.Response.make ~headers (), Cohttp_lwt.Body.of_stream content))
    (fun _exn -> return_404 ())

let pp_size f size =
  if size < 1024 then Fmt.pf f "%dB" size
  else if size < 1024 * 1024 then Fmt.pf f "%.2fKB" (Float.of_int size /. 1024.)
  else if size < 1024 * 1024 * 1024 then
    Fmt.pf f "%.2fMB" (Float.of_int size /. (1024. *. 1024.))
  else Fmt.pf f "%.2fGB" (Float.of_int size /. (1024. *. 1024. *. 1024.))

let serve_dir_list ~name paths =
  let target fname =
    Fpath.(v "/artifacts" // name / fname |> normalize |> to_string)
  in
  let print_entry (fname, { Unix.st_kind; st_size; _ }) =
    let open Tyxml_html in
    match st_kind with
    | S_REG ->
        Some
          [
            txt "F  ";
            a ~a:[ a_href (target fname) ] [ txt fname ];
            i [ txt (Fmt.str "  %a " pp_size st_size) ];
          ]
    | S_DIR ->
        Some [ txt "D  "; a ~a:[ a_href (target fname) ] [ txt (fname ^ "/") ] ]
    | _ -> None
  in
  let+ data =
    paths
    |> List.map Fpath.to_string
    |> Lwt_list.map_s (fun v ->
           let+ stats = Lwt_unix.stat v in
           (Filename.basename v, stats))
  in
  let page =
    let open Tyxml_html in
    html
      (head (title (txt ("Artifacts - " ^ Fpath.to_string name))) [])
      (body
         [
           h1 [ txt ("Directory " ^ Fpath.to_string name) ];
           ul (data |> List.filter_map print_entry |> List.map li);
         ])
  in
  let html = Fmt.to_to_string (Tyxml.Html.pp ()) page in
  (Cohttp_lwt.Response.make (), Cohttp_lwt.Body.of_string html)

let to_dirname s =
  if s = "" || s.[String.length s - 1] <> '/' then s ^ "/" else s

(* From Dream implementation *)
let validate_path ~root path =
  match path with
  | "" | "/" -> Some root
  | v -> (
      let v = String.(sub v 1 (length v - 1)) in
      match Fpath.of_string v with
      | Ok path when Fpath.is_rel path ->
          let merged_path = Fpath.(root // path |> normalize) in
          if Fpath.is_rooted ~root merged_path then Some merged_path else None
      | _ -> None)

let strip_first_char m =
  if m = "" then "" else String.sub m 1 (String.length m - 1)

let serve ~root wildcard_path =
  let root = Fpath.normalize (Fpath.add_seg root "") in
  match validate_path ~root (Routes.Parts.wildcard_match wildcard_path) with
  | None -> return_404 ()
  | Some path -> (
      match Bos.OS.Dir.contents path with
      | Ok paths ->
          serve_dir_list
            ~name:(Fpath.relativize ~root path |> Option.get)
            (Fpath.v ".." :: paths)
      | Error _ -> serve_file path)
