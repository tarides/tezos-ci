module Git = Current_git
module Docker = Current_docker.Default
module Analyse = Analyse
module Packaging = Packaging

let () = Logging.init ()

let monthly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) ()

module Commit_sequence = struct
  module Key = struct
    type t = Current_git.Commit.t list

    let digest v =
      List.map Current_git.Commit.hash v
      |> String.concat ";" |> Digest.string |> Digest.to_hex
  end

  type state = {
    mutable digest : string;
    mutable index : int;
    mutable max : int;
  }

  let make digest = { digest; index = 0; max = 0 }

  let update_to state digest max =
    state.digest <- digest;
    state.max <- max;
    state.index <- 0

  let next state values =
    let digest = Key.digest values in
    if digest <> state.digest then update_to state digest (List.length values);
    let return_value = List.nth values state.index in
    if state.index + 1 < state.max then state.index <- state.index + 1
    else state.index <- 0;
    return_value

  module Op = struct
    let id = "commit-sequence"

    type t = state

    module Key = Key
    module Value = Current_git.Commit

    let auto_cancel = false

    let pp f _ = Fmt.string f "commit sequence"

    let build state job commits =
      let open Lwt.Syntax in
      let* () = Current.Job.start ~level:Harmless job in
      Lwt.return_ok (next state commits)
  end

  module Seq = Current_cache.Make (Op)
end

module Spec = struct
  module Docker = struct
    let pool = Current.Pool.create ~label:"docker build" 1

    let obuilder_spec_build ~label spec =
      let open Current.Syntax in
      let dockerfile =
        let _ = Bos.OS.Dir.create (Fpath.v "/tmp/tezos-ci") in
        let dockerfile =
          let+ spec = spec in
          Obuilder_spec.Docker.dockerfile_of_spec ~buildkit:true spec
        in
        let path =
          let+ dockerfile = dockerfile in
          let hash = Digest.string dockerfile |> Digest.to_hex in
          Fpath.v (Fmt.str "/tmp/tezos-ci/Dockerfile.%s.tez" hash)
        in
        let+ () = Current_fs.save path dockerfile and+ path = path in
        `File path
      in
      Docker.build ~label ~pool ~pull:true ~dockerfile
  end

  module Ocluster = struct
    let obuilder _build ~ocluster ~label spec src =
      let open Current.Syntax in
      let spec =
        let+ spec = spec in
        let spec_str = Fmt.to_to_string Obuilder_spec.pp spec in
        { Cluster_api.Obuilder_job.Spec.spec = `Contents spec_str }
      in
      let src =
        let+ src = src in
        [ Git.Commit.id src ]
      in
      Current_ocluster.build_obuilder ocluster ~label ~src ~pool:"linux-x86_64"
        spec

    let docker_build ~ocluster ~label spec src =
      let open Current.Syntax in
      let options =
        {
          Cluster_api.Docker.Spec.build_args = [];
          squash = false;
          buildkit = true;
          include_git = true;
        }
      in
      let spec =
        let+ spec = spec in
        Obuilder_spec.Docker.dockerfile_of_spec ~buildkit:true spec
      in
      let src =
        let+ src = src in
        [ Git.Commit.id src ]
      in
      Current_ocluster.build ocluster ~options ~label ~src ~pool:"linux-x86_64"
        (`Contents spec)
  end
end

let program_name = "tezos-ci"

let pipeline ocluster =
  let open Current.Syntax in
  let repo_tezos =
    Git.clone ~schedule:monthly "https://gitlab.com/tezos/tezos"
  in
  let build =
    match ocluster with
    | None ->
        fun ~label spec ->
          Spec.Docker.obuilder_spec_build ~label spec (`Git repo_tezos)
          |> Current.ignore_value
    | Some ocluster ->
        fun ~label spec ->
          Spec.Ocluster.docker_build ~ocluster ~label spec repo_tezos
  in
  let analysis = Analyse.v repo_tezos in
  let build_spec =
    let+ analysis = analysis in
    Build.v analysis.version
  in
  let build_job = build ~label:"tezos build" build_spec in
  let analysis = Current.gate ~on:build_job analysis in
  Current.all
    [
      Integration.job ~build analysis
      |> Current.collapse ~key:"stage" ~value:"integration" ~input:analysis;
      Packaging.job ~build analysis
      |> Current.collapse ~key:"stage" ~value:"packaging" ~input:analysis;
    ]

let main current_config mode (`Ocluster_cap cap) =
  let ocluster =
    Option.map
      (fun cap ->
        let vat = Capnp_rpc_unix.client_only_vat () in
        let submission_cap = Capnp_rpc_unix.Vat.import_exn vat cap in
        let connection =
          Current_ocluster.Connection.create ~max_pipeline:20 submission_cap
        in
        Current_ocluster.v connection)
      cap
  in
  let engine =
    Current.Engine.create ~config:current_config (fun () -> pipeline ocluster)
  in
  let site =
    let routes = Current_web.routes engine in
    Current_web.Site.(v ~has_role:allow_all) ~name:program_name routes
  in
  Logging.run
    (Lwt.choose
       [
         Current.Engine.thread engine;
         (* The main thread evaluating the pipeline. *)
         Current_web.run ~mode site;
         (* Optional: provides a web UI *)
       ])

(* Command-line parsing *)

open Cmdliner

let named f = Cmdliner.Term.(app (const f))

let ocluster_cap =
  Arg.value
  @@ Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None
  @@ Arg.info ~doc:"The ocluster submission capability file" ~docv:"FILE"
       [ "ocluster-cap" ]
  |> named (fun x -> `Ocluster_cap x)

let cmd =
  let doc = "an OCurrent pipeline" in
  ( Term.(
      const main $ Current.Config.cmdliner $ Current_web.cmdliner $ ocluster_cap),
    Term.info program_name ~doc )

let () = Term.(exit @@ eval cmd)
