## Tezos-CI

A translation of Tezos' [Gitlab CI](https://gitlab.com/tezos/tezos/-/tree/master/.gitlab/ci) in the ocurrent world.

### What is supported

* Build: `build_arm64`, `build_x86_64`
* Coverage: `test_coverage`
* Documentation: `documentation:build`
* Integration tests `integration:*`
* Tezt: `test:*`
* Unit: `unit:*`

### What remains to do

* Manual: `documentation:build_all`, `documentation:link_check`, `publish:docker_manual`

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
