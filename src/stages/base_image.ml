let alpine_version = "3.14"
let ocaml_version = "4.12.1"
let rust_version = "1.52.1"
let python_version = "3.9.5"

module Specs = struct
  open Obuilder_spec

  let libusb =
    stage ~from:"alpinelinux/docker-abuild"
      [
        env "PACKAGER" "Tezos <ci@tezos.com>";
        run "abuild-keygen -a -i";
        env "alpine_version" alpine_version;
        (* download package description *)
        run
          "wget --continue \
           \"https://git.alpinelinux.org/aports/plain/main/libusb/APKBUILD?h=$alpine_version-stable\" \
           -O \"APKBUILD.libusb\"";
        (* download associated patch 1 *)
        run
          "wget --continue \
           \"https://git.alpinelinux.org/aports/plain/main/libusb/f38f09da98acc63966b65b72029b1f7f81166bef.patch?h=$alpine_version-stable\" \
           -O \"f38f09da98acc63966b65b72029b1f7f81166bef.patch\"";
        (* download associated patch 2 *)
        run
          "wget --continue \
           \"https://git.alpinelinux.org/aports/plain/main/libusb/f6d2cb561402c3b6d3627c0eb89e009b503d9067.patch?h=$alpine_version-stable\" \
           -O \"f6d2cb561402c3b6d3627c0eb89e009b503d9067.patch\"";
        run
          "sed 's/--disable-static/--enable-static/' \"APKBUILD.libusb\" > \
           \"APKBUILD\"";
        run "abuild -r";
      ]

  let hidapi =
    stage ~from:"alpinelinux/docker-abuild"
      [
        env "PACKAGER" "Tezos <ci@tezos.com>";
        run "abuild-keygen -a -i";
        env "alpine_version" alpine_version;
        (* download package description *)
        run
          "wget --continue \
           \"https://git.alpinelinux.org/aports/plain/community/hidapi/APKBUILD?h=$alpine_version-stable\" \
           -O \"APKBUILD.hidapi\"";
        (* download associated patch 1 *)
        run
          "wget --continue \
           \"https://git.alpinelinux.org/aports/plain/community/hidapi/autoconf-270.patch?h=$alpine_version-stable\" \
           -O \"autoconf-270.patch\"";
        run
          "sed 's/--disable-static/--enable-static/' \"APKBUILD.hidapi\" > \
           \"APKBUILD\"";
        run "abuild -r";
      ]

  let runtime_dependencies =
    stage
      ~from:("alpine:" ^ alpine_version)
      [
        env "arch" "x86_64";
        (* XXX *)
        user ~uid:0 ~gid:0;
        run
          "apk --no-cache add libev gmp sudo hidapi libffi libffi-dev gcc \
           libc-dev";
        copy [ "zcash-params" ] ~dst:"/usr/share/zcash-params";
        run
          "adduser -S tezos -u 1000 -g 1000 && echo 'tezos ALL=(ALL:ALL) \
           NOPASSWD:ALL' > /etc/sudoers.d/tezos && chmod 440 \
           /etc/sudoers.d/tezos && chown root:root /etc/sudoers.d/tezos && sed \
           -i.bak 's/^Defaults.*requiretty//g' /etc/sudoers && mkdir -p \
           /var/run/tezos/node /var/run/tezos/client && chown -R tezos \
           /var/run/tezos";
        user ~uid:1000 ~gid:1000;
        env "USER" "tezos";
        workdir "/home/tezos";
      ]

  let runtime_prebuild_dependencies =
    stage
      ~child_builds:
        [
          ("runtime-dependencies", runtime_dependencies);
          ("libusb", libusb);
          ("hidapi", hidapi);
        ]
      ~from:"runtime-dependencies"
      [
        shell [ "/bin/ash"; "-o"; "pipefail"; "-c" ];
        workdir "/";
        env "RUST_VERSION" rust_version;
        env "OCAML_VERSION" ocaml_version;
        copy ~from:(`Build "libusb") [ "/etc/apk/keys/" ] ~dst:"/etc/apk/keys/";
        copy ~from:(`Build "hidapi") [ "/etc/apk/keys/" ] ~dst:"/etc/apk/keys/";
        copy ~from:(`Build "libusb")
          [ "/home/builder/packages/home/x86_64/*.apk" ]
          (* XXX: arch hardcoded*)
          ~dst:"./";
        copy ~from:(`Build "hidapi")
          [ "/home/builder/packages/home/x86_64/*.apk" ]
          ~dst:"./";
        user ~uid:0 ~gid:0;
        run
          "apk --no-cache add build-base bash perl xz m4 git curl tar rsync \
           patch jq ncurses-dev opam openssl-dev cargo hidapi-0.9.0-r2.apk \
           hidapi-dev-0.9.0-r2.apk libusb-1.0.24-r2.apk \
           libusb-dev-1.0.24-r2.apk";
        run "test \"$(rustc --version | cut -d' ' -f2)\" = ${RUST_VERSION}";
        user ~uid:1000 ~gid:1000;
        (* tezos *)
        workdir "/home/tezos";
        run
          "mkdir ~/.ssh && chmod 700 ~/.ssh && git config --global user.email \
           \"ci@tezos.com\" && git config --global user.name \"Tezos CI\"";
        copy [ "repo" ] ~dst:"opam-repository/";
        copy [ "packages" ] ~dst:"opam-repository/packages";
        copy
          [
            "packages/ocaml";
            "packages/ocaml-config";
            "packages/ocaml-base-compiler";
            "packages/ocaml-options-vanilla";
            "packages/base-bigarray";
            "packages/base-bytes";
            "packages/base-unix";
            "packages/base-threads";
          ]
          ~dst:"opam-repository/packages/";
        workdir "/home/tezos/opam-repository";
        run
          "opam init --disable-sandboxing --no-setup --yes --compiler \
           ocaml-base-compiler.${OCAML_VERSION} tezos \
           /home/tezos/opam-repository && opam admin cache && opam update && \
           opam install opam-depext && opam depext --update --yes $(opam list \
           --all --short | grep -v ocaml-option-) && opam clean";
        (* XXX: ENTRYPOINT [ "opam", "exec", "--" ] *)
        (* XXX: CMD [ "/bin/sh" ] *)
      ]

  let runtime_build_dependencies =
    stage
      ~child_builds:
        [ ("runtime_prebuild_dependencies", runtime_prebuild_dependencies) ]
      ~from:"runtime_prebuild_dependencies"
      [
        shell [ "/bin/ash"; "-o"; "pipefail"; "-c" ];
        user ~uid:1000 ~gid:1000;
        workdir "/home/tezos";
        run
          "opam install --yes $(opam list --all --short | grep -v \
           ocaml-option-)";
      ]

  let runtime_build_test_dependencies =
    stage
      ~child_builds:
        [ ("runtime_build_dependencies", runtime_build_dependencies) ]
      ~from:"runtime_build_dependencies"
      [
        shell [ "/bin/ash"; "-o"; "pipefail"; "-c" ];
        env "PYTHON_VERSION" python_version;
        user ~uid:0 ~gid:0;
        run
          "apk --no-cache add py3-pip python3 python3-dev coreutils py3-sphinx \
           py3-sphinx_rtd_theme && if [ \"$(arch)\" = \"x86_64\" ]; then apk \
           --no-cache add shellcheck; fi";
        user ~uid:1000 ~gid:1000;
        workdir "/home/tezos";
        copy [ "nodejs" ] ~dst:"nodejs";
        run "bash nodejs/install-nvm.sh";
        env "CRYPTOGRAPHY_DONT_BUILD_RUST" "1";
        run "pip3 --no-cache-dir install --user poetry==1.0.10";
        env "PATH" "/home/tezos/.local/bin:${PATH}";
        copy [ "poetry.lock" ] ~dst:"poetry.lock";
        copy [ "pyproject.toml" ] ~dst:"pyproject.toml";
        run "poetry config virtualenvs.in-project true && poetry install";
        (* no entrypoint, no cmd*)
      ]
end

let build ~builder _ =
  let context =
    Current_git.clone
      ~schedule:(Current_cache.Schedule.v ())
      ~gref:"master" "https://gitlab.com/tezos/opam-repository.git"
    |> Current.map Current_git.Commit.id
  in
  Lib.Builder.build ~context ~pool:X86_64 ~label:"base_image" builder
    (Current.return Specs.runtime_build_test_dependencies)
