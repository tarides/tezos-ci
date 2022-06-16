type create_gitlab_application_conf = { token : string }

type project_setup_conf = {
  token : string;
  project_names : string list;
  project_ids : int list;
}

type cmd_conf =
  | Create of create_gitlab_application_conf
  | Add of project_setup_conf

type t = { token : Gitlab.Token.t; user : string }

exception Config of string

let read_file path =
  let ch = open_in_bin path in
  Fun.protect
    (fun () ->
      let len = in_channel_length ch in
      really_input_string ch len)
    ~finally:(fun () -> close_in ch)