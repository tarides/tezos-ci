module Git = Current_git

(* TODO: caching ??? *)
let spec (tezos_repository : Analysis.Tezos_repository.t) =
  let commit = tezos_repository.commit in
  (* we need git *)
  let open Obuilder_spec in
  stage ~from:"alpine"
    [ run "apk add git"
    ; workdir "/tezos"
    ; run ~network:[ "host" ]
        "git clone --recursive %S /tezos && git fetch origin %S && git reset \
         --hard %S"
        (Git.Commit_id.repo commit)
        (Git.Commit_id.gref commit)
        (Git.Commit_id.hash commit)
    ]
