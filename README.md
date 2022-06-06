## Tezos-CI

A translation of Tezos' [Gitlab CI][] in the [ocurrent][] world.

### What is supported

* Build: `build_arm64`, `build_x86_64`
* Coverage: `test_coverage`
* Documentation: `documentation:build`
* Integration tests `integration:*`
* Tezt: `test:*`
* Unit: `unit:*`

### What remains to do

* Manual: `documentation:build_all`, `documentation:link_check`, `publish:docker_manual`

## Building

**TODO**

## Running

### In OCluster

```
dune exec -- tezos-ci --ocluster-cap <ocluster_capability_file> \
                      --gitlab-token-file=<GITLAB_TOKEN_FILE> \
                      --gitlab-webhook-secret-file=<WEBHOOK_SECRET_FILE>
                      --verbose
```

### Locally using docker

```
dune exec -- tezos-ci-local --verbose
```

## Architecture

A high level description of the components:

```
                                     Tezos CI
                         ┌──────────────────────────────────────────┐
                         │                                          │
       (main UI)         │ ┌──────────────────────────────────────┐ │
                         │ │                                      │ │                 ┌───────────────────────────┐
    tezos.ci.dev:80/443  │ │                                      │ │                 │                           │
                         │ │        tezos-ci                      │ │                 │    Tezos OCluster         │
         ───────────────►│ │                                      │ │   submission    │                           │
                         │ │         * octez pipeline             │ │   capability    │   ┌─────────────────┐     │
                         │ │                                      ├─┼────────────────►│   │                 │     │
                         │ │         * web ui                     │ │                 │   │    scheduler    │     │
                         │ │                                      │ │                 │   └──┬──────────────┘     │
                         │ │                                      │ │                 │      │      pools         │
                         │ │                                      │ │                 │      │    ┌─────────────┐ │
                         │ │                                      │ │                 │      │    │             │ │
                         │ │                                      │ │                 │      ├────┤  x86_64     │ │
                         │ │                                      │ │                 │      │    ├─────────────┤ │
       (main UI)         │ └──────────────────────────────────────┘ │                 │      │    │             │ │
                         │                                          │                 │      ├────┤  arm64      │ │
gitlab.tezos.ci.dev:80/  │ ┌──────────────┐     ┌────────────────┐  │   submission    │      │    ├─────────────┤ │
                    443  │ │              │     │                │  │   capability    │      │    │             │ │
        ────────────────►│ │              │     │                ├──┼────────────────►│      └────┤  s390x      │ │
                         │ │ ocaml-ci-web │     │ ocaml-ci-gitlab│  │                 │           └─────────────┘ │
                 :8100   │ │              ├────►│                │  │                 │                           │
                         │ │  * web ui    │ ui  │   * pipeline   │  │                 └───────────────────────────┘
        (admin UI)       │ │              │ cap │   * solver     │  │
                         │ │              │     │   * admin ui   │  │                  1 or more workers per pool
                         │ │              │     │                │  │
                         │ └──────────────┘     └────────────────┘  │
                         │                                          │
                         └──────────────────────────────────────────┘   
```

Terminology:
 * pipeline - composition of steps to achieve an outcome, for this project building an OCaml project
 * octez-pipeline - pipeline for building the Tezos Octez implementation 
 * ocaml-ci-gitlab - pipeline for building standard OCaml projects hosted on GitLab
 * ocaml-ci-web - Web frontend for ocaml-ci-gitlab
 * ui-cap - CapnP capability for communication between ocaml-ci-web and ocaml-ci-gitlab
 * submission capability - CapnP capability for submitting a build spec to the cluster
 * Tezos cluster - an OCluster instance for running Tezos builds
 * scheduler - a place to submit build specs to run in a pool
 * worker - a program capable of running build specs in the context of some Git commit
 * build spec - textual description of the steps a worker should perform
 * capnp - serialisation and RPC protocol used for communication between components
 * pool - collection of workers, such that each worker is interchangeable and capable of running a build spec


Conceptually Tezos-ci is a combination of two pipelines that build OCaml projects related to 
the [Tezos Octez implementation](https://gitlab.com/tezos/tezos). The pipelines are:
 * octez, builds the main Octez project
 * ocaml-ci-gitlab pipeline builds OCaml dependencies of Octez that are hosted on GitLab

[Gitlab CI]: https://gitlab.com/tezos/tezos/-/tree/master/.gitlab/ci
[ocurrent]: https://github.com/ocurrent/ocurrent

