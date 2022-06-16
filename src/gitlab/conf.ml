(* GitHub defines a stale branch as more than 3 months old.
   Don't bother testing these. *)
let max_staleness = Duration.of_day 93

let dev_pool = Current.Pool.create ~label:"docker" 1

(** Maximum time for one Docker build. *)
let build_timeout = Duration.of_hour 1

module Builders = struct
  let v docker_context =
    let docker_context, pool =
      Some docker_context, Current.Pool.create ~label:("docker-" ^ docker_context) 20
    in
    { Ocaml_ci.Builder.docker_context; pool; build_timeout }

  let local = { Ocaml_ci.Builder.docker_context = None; pool = dev_pool; build_timeout }
end

module OV = Ocaml_version
module DD = Dockerfile_distro

let default_compiler = OV.(Releases.latest |> without_patch)
let trunk_compiler = OV.(Sources.trunk |> without_patch)

type platform = {
  label : string;
  builder : Ocaml_ci.Builder.t;
  pool : string;
  distro : string;
  ocaml_version : OV.t;
  arch: OV.arch;
  opam_version: Ocaml_ci.Opam_version.t;
}

let pool_of_arch = function
| `X86_64 | `I386 -> "linux-x86_64"
| `Aarch32 | `Aarch64 -> "linux-arm64"
| `S390x -> "linux-s390x"
| `Ppc64le -> "linux-ppc64"

let platforms opam_version =
  let v ?(arch=`X86_64) label distro ocaml_version =
    { arch; label; builder = Builders.local; pool = pool_of_arch arch; distro;
      ocaml_version; opam_version }
  in
  let master_distro = DD.resolve_alias DD.master_distro in
  let make_distro distro =
    let distro = DD.resolve_alias distro in
    let label = DD.latest_tag_of_distro (distro :> DD.t) in
    let tag = DD.tag_of_distro (distro :> DD.t) in
    let ov = OV.(Releases.latest |> with_just_major_and_minor) in
    let multicore_latest = OV.(Releases.v4_12 |> with_just_major_and_minor) in
    if distro = master_distro then
      v label tag (OV.with_variant ov (Some "flambda")) ::
      v label tag (OV.with_variant multicore_latest (Some "domains")) ::
      List.map (fun arch -> v ~arch label tag ov) (DD.distro_arches ov (distro :> DD.t))
    else
      [v label tag ov]
  in
  let make_release ?arch ov =
    let distro = DD.tag_of_distro (master_distro :> DD.t) in
    let ov = OV.with_just_major_and_minor ov in
    v ?arch (OV.to_string ov) distro ov in
  let distros =
    DD.active_tier1_distros `X86_64 @ DD.active_tier2_distros `X86_64 |>
    List.map make_distro |> List.flatten in
  (* The first one in this list is used for lint actions *)
  let ovs = List.rev OV.Releases.recent @ OV.Releases.unreleased_betas in
  List.map make_release ovs @ distros
  