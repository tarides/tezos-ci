let template ~script =
  let build = Build.v in
  let from =
    Variables.image_template__runtime_build_test_dependencies_template
  in
  Obuilder_spec.(
    stage ~from ~child_builds:[ ("build", build) ]
      [
        user ~uid:100 ~gid:100;
        workdir "/home/tezos";
        copy [ "tests_python" ] ~dst:"./tests_python";
        copy [ "poetry.lock"; "pyproject.toml" ] ~dst:".";
        copy [ "scripts/version.sh" ] ~dst:"scripts/version.sh";
        copy ~from:(`Build "build") [ "/" ] ~dst:".";
        run "find . -maxdepth 3";
        run ". ./scripts/version.sh";
        run ". /home/tezos/.venv/bin/activate";
        run "mkdir tests_python/tmp";
        run "touch tests_python/tmp/empty__to_avoid_glob_failing";
        workdir "tests_python";
        run "%s" script;
      ])

let integration_010_many_bakers =
  let script =
    {| poetry run pytest "tests_010/test_many_bakers.py" --exitfirst -m "slow" -s --log-dir=tmp "--junitxml=reports/010_many_bakers.xml" 2>&1 | tee "tmp/010_many_bakers.out" | tail |}
  in
  template ~script
