(lang dune 2.8)

(name tezos-ci)

(generate_opam_files true)

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
  opam-0install
  capnp-rpc-unix
  fmt
  lwt
  cmdliner
  git-unix
  dockerfile
  graphql-cohttp
  graphql-lwt
  conf-libev))
