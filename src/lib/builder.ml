module Git = Current_git
module Docker = Current_docker.Default

module Docker_builder = struct
  let pool = Current.Pool.create ~label:"docker build" 1

  let build ~level ~label spec =
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
    Docker.build ~level ~label ~pool ~pull:true ~dockerfile `No_context
end

module Ocluster_builder = struct
  let obuilder_build ~level ~pool ~ocluster ~label spec =
    let open Current.Syntax in
    let spec =
      let+ spec = spec in
      let spec_str = Fmt.to_to_string Obuilder_spec.pp spec in
      { Cluster_api.Obuilder_job.Spec.spec = `Contents spec_str }
    in
    let src = Current.return [] in
    Current_ocluster.build_obuilder ~level ocluster
      ~cache_hint:"tezos-ci" ~label ~src ~pool spec

  let docker_build ~level ~pool ~ocluster ~label spec =
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
    let src = Current.return [] in
    Current_ocluster.build ~level ocluster ~cache_hint:"tezos-ci"
      ~options ~label ~src ~pool (`Contents spec)
end

type mode =
  | Host_docker
  | Ocluster_docker of Current_ocluster.t
  | Ocluster_obuilder of Current_ocluster.t

type t = { mode : mode; gates : unit Current.t list; manual : bool }

let make mode = { mode; gates = []; manual = false }
let make_docker = make Host_docker

let make_ocluster mode ocluster =
  match mode with
  | `Docker -> make (Ocluster_docker ocluster)
  | `Obuilder -> make (Ocluster_obuilder ocluster)

let gate ~gate t = { t with gates = gate :: t.gates }
let manual t = { t with manual = true }

type pool = Arm64 | X86_64

let pool_to_string = function
  | Arm64 -> "linux-arm64"
  | X86_64 -> "linux-x86_64"

(* TODO: default to host's pool *)
let build ?(pool = X86_64) ~label t spec =
  let spec =
    let open Current.Syntax in
    let+ () = Current.all t.gates and+ spec = spec in
    spec
  in
  let level =
    if t.manual then Current.Level.Dangerous else Current.Level.Average
  in
  match t.mode with
  | Host_docker ->
      Docker_builder.build ~level ~label spec |> Current.ignore_value
  | Ocluster_docker ocluster ->
      Ocluster_builder.docker_build ~level ~pool:(pool_to_string pool) ~ocluster
        ~label spec
  | Ocluster_obuilder ocluster ->
      Ocluster_builder.obuilder_build ~level ~pool:(pool_to_string pool)
        ~ocluster ~label spec

let build ?pool ?name ~label t spec =
  let current = build ?pool ~label t spec in
  match name with
  | None -> Task.single ~name:label current
  | Some name -> Task.single_c ~name current
