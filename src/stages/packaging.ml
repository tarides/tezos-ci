(* Test opam install for each package in the tezos repository *)
open Analysis
open Lib

let cache =
  [ Obuilder_spec.Cache.v ~target:"/home/tezos/.cache/dune"
      "packaging-dune-cache"
  ]

let v ~package (tezos_repository : Analysis.Tezos_repository.t) =
  let from =
    Variables.docker_image_runtime_build_test_dependencies
      tezos_repository.version
  in
  Obuilder_spec.(
    stage ~from
      ~child_builds:[ ("build_src", Lib.Fetch.spec tezos_repository) ]
      [ user ~uid:100 ~gid:100
      ; env "HOME" "/home/tezos"
      ; workdir "/tezos/"
      ; copy ~from:(`Build "build_src") [ "/tezos/" ] ~dst:"./"
      ; run "./scripts/opam-pin.sh"
      ; run "opam depext --yes %s" package
      ; env "DUNE_CACHE" "enabled"
      ; env "DUNE_CACHE_TRANSPORT" "direct"
      ; run ~cache "opam install --yes %s" package
      ; run ~cache "opam reinstall --yes --with-test %s" package
      ])

let all ~builder (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let all_packages =
    let+ analysis = analysis in
    analysis.bin_packages @ analysis.lib_packages
  in
  Task.list_iter ~collapse_key:"packaging"
    (module struct
      type t = string

      let pp = Fmt.string

      let compare = String.compare
    end)
    (fun package ->
      let spec =
        let+ package = package
        and+ analysis = analysis in
        v ~package analysis
      in
      let name =
        let+ package = package in
        "packaging:" ^ package
      in
      Lib.Builder.build builder ~name ~label:"packaging" spec)
    all_packages
