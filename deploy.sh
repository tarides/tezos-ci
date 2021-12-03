#!/bin/bash -ex

docker build -t tezos-ci-service -f Dockerfile .
docker stack rm tezos-ci
sleep 15
docker stack deploy -c stack.yml tezos-ci
