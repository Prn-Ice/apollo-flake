{
  description = "Apollo is a Game stream host for Moonlight";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config = {allowUnfree = true;};
        };
        # Pre-fetch the boost dependency to circumvent the problem with boost188 package.
        # This relies on CmakeLists FetchContent
        boostVersion = "1.88.0";
        boostCMakeTarballURL = "https://github.com/boostorg/boost/releases/download/boost-${boostVersion}/boost-${boostVersion}-cmake.tar.xz";

        boostFetchedTarball = pkgs.fetchurl {
          url = boostCMakeTarballURL;
          hash = "sha256-9ItIOQOAz7lKYphyNG46gTcNxJiJbxYBmt5yercusew=";
        };

        boostExtractedSrc =
          pkgs.runCommand "boost-${boostVersion}-cmake-src" {
            src = boostFetchedTarball;
            nativeBuildInputs = [pkgs.gnutar pkgs.xz];
          } ''
            mkdir -p $out
            # Extract and strip the top-level directory (e.g., "boost-1.88.0-cmake/")
            # so $out contains the contents of that directory (CMakeLists.txt, libs/, etc.)
            tar -xf $src --strip-components=1 -C $out
          '';

        sunshinePackage = {
          cudaSupport ? pkgs.config.cudaSupport or false,
          cudaPackages ? pkgs.cudaPackages,
        }: let
          stdenv' =
            if cudaSupport
            then cudaPackages.backendStdenv
            else pkgs.stdenv;
        in
          stdenv'.mkDerivation rec {
            pname = "sunshine";
            version = "0.4.3";
            src = pkgs.fetchFromGitHub {
              owner = "ClassicOldSong";
              repo = "Apollo";
              rev = "53aa222e8e22adc6fcdc9ba4ed6fce2fe5c09ea9";
              hash = "sha256-nx+bepOF8W0UktI/vgsgpk5PMC5slbAKohCmgqR47t0=";
              fetchSubmodules = true;
            };

            # build webui
            ui = pkgs.buildNpmPackage {
              inherit src version;
              pname = "apollo-ui";
              npmDepsHash = "sha256-EW6NY2kQLL4UTXedERUfEVsxxPucQ6PzmJ8Yju7DmbU=";

              postPatch = ''
                cp ${./package-lock.json} ./package-lock.json
              '';

              installPhase = ''
                mkdir -p $out
                cp -r * $out/
              '';
            };

            nativeBuildInputs =
              [
                pkgs.cmake
                pkgs.pkg-config
                pkgs.python3
                pkgs.makeWrapper
                pkgs.wayland-scanner
                # Avoid fighting upstream's usage of vendored ffmpeg libraries
                pkgs.autoPatchelfHook
              ]
              ++ pkgs.lib.optionals cudaSupport [
                pkgs.autoAddDriverRunpath
                cudaPackages.cuda_nvcc
                (pkgs.lib.getDev cudaPackages.cuda_cudart)
              ];

            buildInputs =
              [
                pkgs.avahi
                pkgs.libevdev
                pkgs.libpulseaudio
                pkgs.xorg.libX11
                pkgs.xorg.libxcb
                pkgs.xorg.libXfixes
                pkgs.xorg.libXrandr
                pkgs.xorg.libXtst
                pkgs.xorg.libXi
                pkgs.openssl
                pkgs.libopus
                pkgs.libdrm
                pkgs.wayland
                pkgs.libffi
                pkgs.libcap
                pkgs.curl
                pkgs.pcre
                pkgs.pcre2
                pkgs.libuuid
                pkgs.libselinux
                pkgs.libsepol
                pkgs.libthai
                pkgs.libdatrie
                pkgs.xorg.libXdmcp
                pkgs.libxkbcommon
                pkgs.libepoxy
                pkgs.libva
                pkgs.libvdpau
                pkgs.numactl
                pkgs.libgbm
                pkgs.amf-headers
                pkgs.sysprof
                pkgs.glib
                pkgs.svt-av1
                pkgs.libsysprof-capture
                pkgs.lerc
                (
                  if pkgs.lib?libappindicator
                  then pkgs.libappindicator
                  else pkgs.libappindicator-gtk3
                )
                pkgs.libnotify
                pkgs.miniupnpc
                pkgs.nlohmann_json
              ]
              ++ pkgs.lib.optionals cudaSupport [
                cudaPackages.cudatoolkit
                cudaPackages.cuda_cudart
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
                pkgs.intel-media-sdk
              ];

            runtimeDependencies = [
              pkgs.avahi
              pkgs.libgbm
              pkgs.xorg.libXrandr
              pkgs.xorg.libxcb
              pkgs.libglvnd
            ];

            cmakeFlags =
              [
                "-Wno-dev"
                (pkgs.lib.cmakeBool "UDEV_FOUND" true)
                (pkgs.lib.cmakeBool "SYSTEMD_FOUND" true)
                (pkgs.lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
                (pkgs.lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
                (pkgs.lib.cmakeBool "BOOST_USE_STATIC" false)
                (pkgs.lib.cmakeBool "BUILD_DOCS" false)
                (pkgs.lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "nixpkgs")
                (pkgs.lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://nixos.org")
                (pkgs.lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/NixOS/nixpkgs/issues")
                "-DFETCHCONTENT_SOURCE_DIR_BOOST=${boostExtractedSrc}"
              ]
              ++ pkgs.lib.optionals (!cudaSupport) [
                (pkgs.lib.cmakeBool "SUNSHINE_ENABLE_CUDA" false)
              ];

            env = {
              # needed to trigger CMake version configuration
              BUILD_VERSION = "${version}";
              BRANCH = "master";
              COMMIT = "";
            };

            postPatch = ''
              mv packaging/linux/dev.lizardbyte.app.Sunshine.desktop packaging/linux/com.SudoMaker.dev.Apollo.desktop
              mv packaging/linux/dev.lizardbyte.app.Sunshine.terminal.desktop packaging/linux/com.SudoMaker.dev.Apollo.terminal.desktop
              mv packaging/linux/dev.lizardbyte.app.Sunshine.metainfo.xml packaging/linux/com.SudoMaker.dev.Apollo.metainfo.xml

              # remove upstream dependency on systemd and udev
              substituteInPlace cmake/packaging/linux.cmake \
                --replace-fail 'find_package(Systemd)' "" \
                --replace-fail 'find_package(Udev)' ""

              # don't look for npm since we build webui separately
              substituteInPlace cmake/targets/common.cmake \
                --replace-fail 'find_program(NPM npm REQUIRED)' ""

              substituteInPlace packaging/linux/com.SudoMaker.dev.Apollo.desktop \
                --replace-fail '/usr/bin/env systemctl start --u sunshine' 'sunshine'

              substituteInPlace packaging/linux/sunshine.service.in \
                --subst-var-by PROJECT_DESCRIPTION 'Self-hosted game stream host for Moonlight' \
                --replace-fail '/bin/sleep' '${pkgs.lib.getExe' pkgs.coreutils "sleep"}'
            '';

            preBuild = ''
              cp -r ${ui}/build ../
            '';

            buildFlags = [
              "sunshine"
            ];

            postFixup = pkgs.lib.optionalString cudaSupport ''
              wrapProgram $out/bin/sunshine \
                --set LD_LIBRARY_PATH ${pkgs.lib.makeLibraryPath [pkgs.vulkan-loader]}
            '';

            installPhase = ''
              runHook preInstall
              cmake --install .
              runHook postInstall
            '';

            postInstall = ''
              install -Dm644 ../packaging/linux/com.SudoMaker.dev.Apollo.desktop $out/share/applications/com.SudoMaker.dev.Apollo.desktop
            '';

            meta = with pkgs.lib; {
              description = "Apollo is a Game stream host for Moonlight";
              homepage = "https://github.com/ClassicOldSong/Apollo";
              license = licenses.gpl3Only;
              mainProgram = "sunshine";
              maintainers = with maintainers; [anil9];
              platforms = platforms.linux;
            };
          };
      in {
        packages.default = sunshinePackage {};
        packages.sunshine = sunshinePackage {};
        packages.sunshine-cuda = sunshinePackage {
          cudaSupport = true;
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/sunshine";
        };
        apps.sunshine = self.apps.${system}.default;
        apps.sunshine-cuda = {
          type = "app";
          program = "${self.packages.${system}.sunshine-cuda}/bin/sunshine";
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [self.packages.${system}.default];
          packages = [
            pkgs.cmake
            pkgs.gdb
          ];
        };
        nixosModules.default = ./apollo-module.nix;
      }
    );
}
