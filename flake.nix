{
  description = "Sung, a native Linux music player";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # The helper's dependencies, helper/requirements.txt.
      pythonFor =
        pkgs:
        pkgs.python3.withPackages (ps: [
          ps.ytmusicapi
          ps.yt-dlp
        ]);
      # CMakeLists.txt owns the version.
      version = lib.head (
        builtins.match ".*project\\(Sung VERSION ([0-9.]+).*" (builtins.readFile ./CMakeLists.txt)
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pythonFor pkgs;
        in
        {
          default = self.packages.${system}.sung;

          sung = pkgs.stdenv.mkDerivation {
            pname = "sung";
            inherit version;
            src = self;

            nativeBuildInputs = [
              pkgs.cmake
              pkgs.ninja
              pkgs.qt6.wrapQtAppsHook
            ];
            buildInputs = with pkgs.qt6; [
              qtbase
              qtdeclarative
              qtmultimedia
              qtsvg
              qtwayland
              # WebP artwork.
              qtimageformats
            ];

            cmakeFlags = [
              (lib.cmakeBool "BUILD_TESTING" false)
              (lib.cmakeBool "SUNG_DIAGNOSTICS" false)
            ];

            # The helper runs on this interpreter in place of the venv that
            # scripts/install.sh builds. yt-dlp solves YouTube's challenges with
            # node, the helper probes local files with ffmpeg, pactl watches the
            # output port and secret-tool reaches the keyring.
            qtWrapperArgs = [
              "--set-default SUNG_PYTHON ${lib.getExe python}"
              "--prefix PATH : ${
                lib.makeBinPath [
                  pkgs.ffmpeg-headless
                  pkgs.nodejs
                  pkgs.pulseaudio
                  pkgs.libsecret
                ]
              }"
            ];

            meta = {
              description = "Native Linux music player";
              homepage = "https://github.com/yappologistic/Sung";
              mainProgram = "sung";
              platforms = lib.platforms.linux;
            };
          };

          # Not in nixpkgs. The interface is set in it when fontconfig can find
          # it, and the verification harness requires it.
          google-sans-flex = pkgs.stdenvNoCC.mkDerivation {
            pname = "google-sans-flex";
            version = "0-unstable-a0e3dbc";
            src = pkgs.fetchurl {
              name = "GoogleSansFlex.ttf";
              url = "https://raw.githubusercontent.com/google/fonts/a0e3dbcdc3a3ecfafff3f071159ae0221628922d/ofl/googlesansflex/GoogleSansFlex%5BGRAD%2CROND%2Copsz%2Cslnt%2Cwdth%2Cwght%5D.ttf";
              hash = "sha256-wxpIL77L8uB+aJATTSAHhyOq33Msm5xsmkT4b4Jltv4=";
            };
            dontUnpack = true;
            installPhase = "install -Dm444 $src $out/share/fonts/truetype/GoogleSansFlex.ttf";
            meta.license = lib.licenses.ofl;
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sung = self.packages.${system}.sung;
          python = pythonFor pkgs;
          # buildInputs holds the -dev outputs; the plugins and QML modules are in out.
          qtModules = map (p: p.out) (sung.buildInputs ++ [ pkgs.qt6.qttools ]);
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ sung ];
            packages = [
              python
              pkgs.ffmpeg-headless
              pkgs.nodejs
              pkgs.pulseaudio
              pkgs.libsecret
              # qdbus for the MPRIS stage, dbus-run-session for the notification test.
              pkgs.qt6.qttools
              (pkgs.writeShellScriptBin "qdbus6" ''exec qdbus "$@"'')
              pkgs.dbus
              pkgs.fontconfig
              pkgs.grim
            ];

            # Binaries built in the shell are not wrapped, so point Qt at the
            # same plugins and QML modules the wrapper would.
            QT_PLUGIN_PATH = lib.makeSearchPath pkgs.qt6.qtbase.qtPluginPrefix qtModules;
            QML_IMPORT_PATH = lib.makeSearchPath pkgs.qt6.qtbase.qtQmlPrefix qtModules;
            # scripts/run.sh takes this over the venv scripts/setup.sh builds.
            SUNG_PYTHON = lib.getExe python;
            FONTCONFIG_FILE = pkgs.makeFontsConf {
              fontDirectories = [
                self.packages.${system}.google-sans-flex
                pkgs.dejavu_fonts
              ];
            };
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
