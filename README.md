## Tezos-CI

A translation of Tezos' Gitlab CI (https://gitlab.com/tezos/tezos/-/tree/master/.gitlab/ci) in the ocurrent world.

### What is supported

* Build: `build_arm64`, `build_x86_64`
* Integration tests `integration:*`

### What remains to do

* Documentation: `documentation:build`
* Tezt: `test:*`
* Unit: `unit:*`
* Manual: `documentation:build_all`, `documentation:link_check`, `publish:docker_manual`
* Coverage: `test_coverage`

## Running

### In OCluster

```
dune exec -- tezos-ci --ocluster-cap <ocluster_capability_file>
```

### Locally using docker

```
dune exec -- tezos-ci
```
