(lang dune 2.8)

(name tezos-ci)

(generate_opam_files true)

(source
 (github tarides/tezos-ci))

(authors
 "Lucas Pluvinage <lucas@tarides.com>"
 "Tim McGilchrist <timmcgil@gmail.com>"
 "Antonin Décimo <antonin@tarides.com>"
 "Navin Keswani <navin@novemberkilo.com>"
 "David Allsopp <david.allsopp@metastack.com>")

(maintainers "Lucas Pluvinage <lucas@tarides.com>")

(package
 (name tezos-ci)
 (synopsis "OCurrent CI for Tezos")
 (description "OCurrent CI for Tezos")
 (depends
  (ocaml
   (>= 4.10.0))
  dune-build-info
  (current (>= 0.6))
  current_web
  current_git
  current_gitlab
  current_docker
  current_ocluster
  capnp-rpc-unix
  obuilder-spec
  opam-file-format
  ocaml-ci-solver
  (ppx_deriving (>= 5.2.1))
  (ppx_deriving_yojson (>= 3.6.1))
  astring
  fmt
  lwt
  logs
  ocaml-ci
  ocaml-ci-service
  ocaml-ci-solver
  (cmdliner (>= 1.1.0))
  dockerfile
  conf-libev)
 (conflicts (gitlab-unix (= "0.1.1"))))

(package
 (name tezos-setup)
 (synopsis "CLI tool for setting up Gitlab applications and permissions")
 (description "CLI tool for setting up Gitlab applications and permissions")
 (depends
  (ocaml (>= 4.10.0))
  (cmdliner (>= 1.1.0))
  (gitlab-unix (>= 0.1.4))
  (fmt (>= 0.9.0))))
