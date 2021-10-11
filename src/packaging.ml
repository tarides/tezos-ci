(* Test opam install for each package in the tezos repository *)

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
        run "opam install --yes %s" package;
        run "opam reinstall --yes --with-test %s" package;
      ])
