let tezt_job_total = 3

let template ~tezt_job version =
  let build = Build.v version in
  let from = Variables.docker_image_runtime_build_test_dependencies version in
  Obuilder_spec.(
    stage ~from ~child_builds:[ ("build", build) ]
      [
        user ~uid:100 ~gid:100;
        workdir "/home/tezos";
        copy [ "/" ] ~dst:"./";
        copy ~from:(`Build "build") [ "/dist/" ] ~dst:".";
        run "find . -maxdepth 3";
        run ". ./scripts/version.sh";
        run ". /home/tezos/.venv/bin/activate";
        run
          "opam exec -- dune exec tezt/tests/main.exe -- --color \
           --log-buffer-size 5000 --log-file tezt.log --global-timeout 3300 \
           --junit tezt-junit.xml --from-record tezt/test-results.json --job \
           %d/%d --record tezt-results-%d.json"
          tezt_job tezt_job_total tezt_job;
        run "cat tezt.log";
        run "cat tezt-results-%d.json" tezt_job;
      ])

let job ~build (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let version =
    let+ analysis = analysis in
    analysis.version
  in

  List.init tezt_job_total (fun n -> n + 1) (* 1, 2, ..., tezt_job_total *)
  |> List.map (fun n ->
         let label = Fmt.str "integration:tezt:%d" n in
         build ~label (Current.map (template ~tezt_job:n) version))
  |> Current.all
