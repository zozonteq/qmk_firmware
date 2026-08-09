{
  description = "QMK Firmware development environment";

  inputs = {
    # Pinned to the same revisions as util/nix/sources.json (Niv) so the
    # flake shell matches `nix-shell` / shell.nix.
    nixpkgs.url = "github:NixOS/nixpkgs/98b00b6947a9214381112bdb6f89c25498db4959";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix = {
      url = "github:nix-community/poetry2nix/3c92540611f42d3fb2d0d084a6c694cd6544b609";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        p2n = poetry2nix.lib.mkPoetry2Nix { inherit pkgs; };

        avr = true;
        arm = true;
        teensy = true;

        avrlibc = pkgs.pkgsCross.avr.libcCross;

        avr_incflags = [
          "-isystem ${avrlibc}/avr/include"
          "-B${avrlibc}/avr/lib/avr5"
          "-L${avrlibc}/avr/lib/avr5"
          "-B${avrlibc}/avr/lib/avr35"
          "-L${avrlibc}/avr/lib/avr35"
          "-B${avrlibc}/avr/lib/avr51"
          "-L${avrlibc}/avr/lib/avr51"
        ];

        pythonEnv = p2n.mkPoetryEnv {
          projectDir = ./util/nix;
          overrides = p2n.overrides.withDefaults (self: super: {
            qmk = super.qmk.overridePythonAttrs (old: {
              # Allow QMK CLI to run "qmk" as a subprocess (the wrapper changes
              # $PATH and breaks these invocations).
              dontWrapPythonPrograms = true;

              # Fix "qmk setup" to use the Python interpreter from the environment
              # when invoking "qmk doctor" (sys.executable gets its value from
              # $NIX_PYTHONEXECUTABLE, which is set by the "qmk" wrapper from the
              # Python environment, so "qmk doctor" then runs with the proper
              # $NIX_PYTHONPATH too, because sys.executable actually points to
              # another wrapper from the same Python environment).
              postPatch = ''
                substituteInPlace qmk_cli/subcommands/setup.py \
                  --replace "[Path(sys.argv[0]).as_posix()" \
                    "[Path(sys.executable).as_posix(), Path(sys.argv[0]).as_posix()"
              '';
            });
          });
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "qmk-firmware";

          buildInputs = with pkgs; [ clang-tools_11 dfu-programmer dfu-util diffutils git pythonEnv niv wb32-dfu-updater ]
            ++ pkgs.lib.optional avr [
              pkgs.pkgsCross.avr.buildPackages.binutils
              pkgs.pkgsCross.avr.buildPackages.gcc8
              avrlibc
              pkgs.avrdude
            ]
            ++ pkgs.lib.optional arm [ pkgs.gcc-arm-embedded ]
            ++ pkgs.lib.optional teensy [ pkgs.teensy-loader-cli ];

          AVR_CFLAGS = pkgs.lib.optional avr avr_incflags;
          AVR_ASFLAGS = pkgs.lib.optional avr avr_incflags;

          shellHook = ''
            # Prevent the avr-gcc wrapper from picking up host GCC flags
            # like -iframework, which is problematic on Darwin
            unset NIX_CFLAGS_COMPILE_FOR_TARGET
          '';
        };
      });
}
