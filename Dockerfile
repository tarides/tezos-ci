FROM ocaml/opam:debian-11-ocaml-4.14@sha256:c9b4f14cd425a623c4ed33182b3a845175aa7494578d6997fbb9c71d4f2a8135 AS build
RUN sudo ln -f /usr/bin/opam-2.1 /usr/bin/opam && opam update
RUN sudo apt-get update && sudo apt-get install libev-dev capnproto libcapnp-dev graphviz m4 pkg-config libsqlite3-dev libgmp-dev libffi-dev -y --no-install-recommends
RUN cd ~/opam-repository && git fetch origin master && git reset --hard d4eff0dc069a950dbebebcf7f800fc08d924682b && opam update
COPY --chown=opam \
    vendor/ocurrent/current_docker.opam \
    vendor/ocurrent/current_github.opam \
    vendor/ocurrent/current_gitlab.opam \
    vendor/ocurrent/current_git.opam \
    vendor/ocurrent/current.opam \
    vendor/ocurrent/current_rpc.opam \
    vendor/ocurrent/current_slack.opam \
    vendor/ocurrent/current_web.opam \
    /src/vendor/ocurrent/
COPY --chown=opam \
    vendor/ocluster/ocluster-api.opam \
    vendor/ocluster/current_ocluster.opam \
    /src/vendor/ocluster/
COPY --chown=opam \
    vendor/ocaml-matrix/matrix-common.opam \
    vendor/ocaml-matrix/matrix-ctos.opam \
    vendor/ocaml-matrix/matrix-current.opam \
    /src/ocaml-matrix/
COPY --chown=opam \
    vendor/ocaml-ci/ocaml-ci.opam \
    vendor/ocaml-ci/ocaml-ci-api.opam \
    vendor/ocaml-ci/ocaml-ci-service.opam \
    vendor/ocaml-ci/ocaml-ci-solver.opam \
    /src/vendor/ocaml-ci/
COPY --chown=opam \
    vendor/current-web-pipelines/current-web-pipelines.opam \
    /src/vendor/current-web-pipelines/
WORKDIR /src
RUN opam pin add -yn current_docker.dev "./vendor/ocurrent" && \
    opam pin add -yn current_github.dev "./vendor/ocurrent" && \
    opam pin add -yn current_gitlab.dev "./vendor/ocurrent" && \
    opam pin add -yn current_git.dev "./vendor/ocurrent" && \
    opam pin add -yn current.dev "./vendor/ocurrent" && \
    opam pin add -yn current_rpc.dev "./vendor/ocurrent" && \
    opam pin add -yn current_slack.dev "./vendor/ocurrent" && \
    opam pin add -yn current_web.dev "./vendor/ocurrent" && \
    opam pin add -yn current_ocluster.dev "./vendor/ocluster" && \
    opam pin add -yn ocluster-api.dev "./vendor/ocluster" && \
    opam pin add -yn current-web-pipelines.dev "./vendor/current-web-pipelines" && \
    opam pin add -yn matrix-common.dev "./vendor/ocaml-matrix" && \
    opam pin add -yn matrix-ctos.dev "./vendor/ocaml-matrix" && \
    opam pin add -yn matrix-current.dev "./vendor/ocaml-matrix" && \
    opam pin add -yn ocaml-ci.dev "./vendor/ocaml-ci" && \
    opam pin add -yn ocaml-ci-api.dev "./vendor/ocaml-ci" && \
    opam pin add -yn ocaml-ci-service.dev "./vendor/ocaml-ci" && \
    opam pin add -yn ocaml-ci-solver.dev "./vendor/ocaml-ci"
COPY --chown=opam tezos-ci.opam /src/
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam exec -- dune build ./_build/install/default/bin/tezos-ci ./_build/install/default/bin/ocaml-ci-solver 

FROM debian:11
RUN apt-get update && apt-get install libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian bullseye stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce -y --no-install-recommends
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/tezos-ci"]
ENV OCAMLRUNPARAM=a=2
# Enable experimental for docker manifest support
ENV DOCKER_CLI_EXPERIMENTAL=enabled
COPY --from=build /src/_build/install/default/bin/tezos-ci /src/_build/install/default/bin/ocaml-ci-solver /usr/local/bin/
