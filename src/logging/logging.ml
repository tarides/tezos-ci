let reporter =
  let report src level ~over k msgf =
    let k _ =
      over ();
      k ()
    in
    let src = Logs.Src.name src in
    msgf @@ fun ?header ?tags:_ fmt ->
    Fmt.kpf k Fmt.stdout
      ("%a %a @[" ^^ fmt ^^ "@]@.")
      Fmt.(styled `Magenta string)
      (Printf.sprintf "%14s" src)
      Logs_fmt.pp_header (level, header)
  in
  { Logs.report }

let init style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter reporter

let cmdliner =
  let open Cmdliner in
  let docs = Manpage.s_common_options in
  Term.(const init $ Fmt_cli.style_renderer ~docs () $ Logs_cli.level ~docs ())

let run x =
  match Lwt_main.run x with
  | Ok () -> Ok ()
  | Error (`Msg m) as e ->
      Logs.err (fun f -> f "%a" Fmt.lines m);
      e
