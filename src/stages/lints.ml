let sanity_ci ~builder (analysis : Analysis.Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let spec =
    let+ analysis = analysis in
    let build = Build.v analysis in
    let from =
      Analysis.Variables.docker_image_runtime_build_test_dependencies
        analysis.version
    in
    Obuilder_spec.(
      stage ~from
        ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
        [
          user ~uid:1000 ~gid:1000; 
          workdir "/home/tezos";
          copy ~from:(`Build "src") [ "/tezos/" ] ~dst:".";
          copy ~from:(`Build "build") [ "/dist/" ] ~dst:".";
          run ". ./scripts/version.sh";
          run ". /home/tezos/.venv/bin/activate";
          run "opam exec -- src/tooling/lint.sh --check-gitlab-ci-yml";
        ])
  in
  Lib.Builder.build ~label:"lints:sanity_ci" builder spec

let docker_hadolint ~builder (analysis : Analysis.Tezos_repository.t Current.t)
    =
  let open Current.Syntax in
  let spec =
    let+ analysis = analysis in
    Obuilder_spec.(
      stage ~from:"hadolint/hadolint:latest-debian"
        ~child_builds:[ ("src", Lib.Fetch.spec analysis) ]
        [
          workdir "/src";
          copy ~from:(`Build "src")
            [ "/tezos/build.Dockerfile"; "/tezos/Dockerfile" ]
            ~dst:".";
          run "hadolint build.Dockerfile";
          run "hadolint Dockerfile";
        ])
  in
  Lib.Builder.build ~label:"lints:docker_hadolint" builder spec

let misc_checks ~builder (analysis : Analysis.Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let spec =
    let+ analysis = analysis in
    let from =
      Analysis.Variables.docker_image_runtime_build_test_dependencies
        analysis.version
    in
    Obuilder_spec.(
      stage ~from
        ~child_builds:[ ("src", Lib.Fetch.spec analysis) ]
        [
          user ~uid:1000 ~gid:1000; 
          workdir "/home/tezos/src";
          copy ~from:(`Build "src") [ "/tezos" ] ~dst:".";
          run ". ./scripts/version.sh";
          env "VIRTUAL_ENV" "/home/tezos/.venv";
          env "PATH" "$VIRTUAL_ENV/bin:$PATH";
          (* checks that all deps of opam packages are already installed *)
          run "./scripts/opam-check.sh";
          (* misc linting *)
          run
            "find . ! -path \"./_opam/*\" -name \"*.opam\" -exec opam lint {} \
             +;";
          run "opam exec -- make check-linting";
          run "opam exec -- make check-python-linting";
          (* python checks *)
          run "opam exec -- make -C tests_python typecheck";
          (* ensure that ...*)
          run "git apply devtools/protocol-print/add-hack-module.patch";
          run
            {|opam exec -- dune runtest -p tezos-test-helpers ||
    { echo "You have probably defined some tests in dune files without specifying to which 'package' they belong."; exit 1; }
|};
        ])
  in
  Lib.Builder.build ~label:"lints:misc_checks" builder spec

let check_precommit_hook ~builder
    (analysis : Analysis.Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let spec =
    let+ analysis = analysis in
    let from =
      Analysis.Variables.docker_image_runtime_build_test_dependencies
        analysis.version
    in
    Obuilder_spec.(
      stage ~from
        ~child_builds:[ ("src", Lib.Fetch.spec analysis) ]
        [
          user ~uid:1000 ~gid:1000; 
          workdir "/home/tezos";
          copy ~from:(`Build "src") [ "/tezos" ] ~dst:".";
          run ". ./scripts/version.sh";
          run ". /home/tezos/.venv/bin/activate";
          (* checks that all deps of opam packages are already installed *)
          run "./scripts/pre_commit/pre_commit.py --test-itself";
          run "poetry run pylint scripts/pre_commit/pre_commit.py";
          run "poetry run pycodestyle scripts/pre_commit/pre_commit.py";
          run "poetry run mypy scripts/pre_commit/pre_commit.py";
        ])
  in
  Lib.Builder.build ~label:"lints:check_precommit_hook" builder spec
