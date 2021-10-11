module Git = Current_git
module Docker = Current_docker.Default
module Analyse = Analyse
module Packaging = Packaging

let () = Logging.init ()

let monthly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) ()

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
    let ocluster_build ~ocluster ~label spec src =
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
  end
end

let program_name = "tezos-ci"

let pipeline ocluster =
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
          Spec.Ocluster.ocluster_build ~ocluster ~label spec repo_tezos
  in

  let analysis = Analyse.v repo_tezos in
  Current.all
    [
      Integration.job ~build analysis
      |> Current.collapse ~key:"stage" ~value:"integration" ~input:analysis;
      Packaging.job ~build analysis
      |> Current.collapse ~key:"stage" ~value:"integration" ~input:analysis;
      build ~label:"tezos build" (Current.return Build.v);
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
