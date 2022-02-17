(lang dune 2.8)

(name tezos-ci)

(generate_opam_files true)
(formatting disabled)
; Edit these to give your project's URL, authors and maintainers:

(source
 (github ocurrent/tezos-ci))

(authors "lucas@tarides.com")

(maintainers "lucas@tarides.com")

(package
 (name tezos-ci)
 (synopsis "An OCurrent pipeline")
 (description "A longer description")
 (depends
  (ocaml
   (>= 4.08.0))
  (current
   (>= 0.3))
  current_web
  current_git
  current_gitlab
  current_docker
  current_ocluster
  capnp-rpc-unix
  obuilder-spec
  opam-file-format
  (ppx_deriving (>= 5.2.1))
  (ppx_deriving_yojson (>= 3.6.1))
  astring
  fmt
  lwt
  logs
  (cmdliner (>= 1.1.0))
  dockerfile
  conf-libev)
 (conflicts (gitlab-unix (= "0.1.1"))))
