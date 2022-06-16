open Cmdliner

let version =
  match Build_info.V1.version () with
  | None -> "n/a"
  | Some v -> Build_info.V1.Version.to_string v

let envs = Gitlab.Env.envs

let cmds =
  let doc = "" in
  let default = Term.(ret (const (`Help (`Pager, None)))) in
  let man =
    [
      `S "DESCRIPTION";
      `P
        "tezos-setup is a command line tool for setting up tezos projects to \
         be built on tezos-ci.";
    ]
  in
  let info = Cmd.info ~envs "tezos-setup" ~version ~doc ~man in
  Cmd.group ~default info [ Project_hook.add_projects ]

let () = exit @@ Cmd.eval ~catch:true cmds
