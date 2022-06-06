open Analysis
open Lib

let tezt_job_total = 25

let template ~tezt_job analysis =
  let build = Build.v analysis in
  let from =
    Variables.docker_image_runtime_build_test_dependencies analysis.version
  in
  Obuilder_spec.(
    stage ~from
      ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
      [ user ~uid:100 ~gid:100
      ; workdir "/home/tezos/src"
      ; copy ~from:(`Build "src") [ "/tezos/" ] ~dst:"."
      ; copy ~from:(`Build "build") [ "/dist/" ] ~dst:"."
      ; run ". ./scripts/version.sh"
      ; env "VIRTUAL_ENV" "/home/tezos/.venv"
      ; env "PATH" "$VIRTUAL_ENV/bin:$PATH"
      ; run
          "opam exec -- dune exec tezt/tests/main.exe -- --color \
           --log-buffer-size 5000 --log-file tezt.log --global-timeout 3300 \
           --junit tezt-junit.xml --from-record tezt/records --job %d/%d \
           --record tezt-results-%d.json"
          tezt_job tezt_job_total tezt_job
      ; run "cat tezt.log"
      ; run "cat tezt-results-%d.json" tezt_job
      ])

let job ~builder (analysis : Tezos_repository.t Current.t) =
  List.init tezt_job_total (fun n -> n + 1) (* 1, 2, ..., tezt_job_total *)
  |> List.map (fun n ->
         let label = Fmt.str "integration:tezt:%d" n in
         Lib.Builder.build builder ~label
           (Current.map (template ~tezt_job:n) analysis))
  |> Task.all ~name:(Current.return "integration:tezt")
