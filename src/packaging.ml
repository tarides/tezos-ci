(* Test opam install for each package in the tezos repository *)

let cache =
  [
    Obuilder_spec.Cache.v ~target:"/home/tezos/.cache/dune"
      "packaging-dune-cache";
  ]

let v ~package () =
  let from =
    Variables.image_template__runtime_build_test_dependencies_template
  in
  Obuilder_spec.(
    stage ~from
      [
        user ~uid:100 ~gid:100;
        env "HOME" "/home/tezos";
        workdir "/tezos/";
        copy [ "." ] ~dst:".";
        run "./scripts/opam-pin.sh";
        run "opam depext --yes %s" package;
        env "DUNE_CACHE" "enabled";
        env "DUNE_CACHE_TRANSPORT" "direct";
        run ~cache "opam install --yes %s" package;
        run ~cache "opam reinstall --yes --with-test %s" package;
      ])

let job ~build (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let all_packages =
    let+ analysis = analysis in
    analysis.bin_packages @ analysis.lib_packages
  in
  Current.list_iter ~collapse_key:"packaging"
    (module struct
      type t = string

      let pp = Fmt.string

      let compare = String.compare
    end)
    (fun package ->
      let spec =
        let+ package = package in
        v ~package ()
      in
      let* package = package in
      build ~label:("packaging:" ^ package) spec)
    all_packages
