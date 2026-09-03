{ lib, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      pkgsDir = ./pkgs;
      extraArgs = {
        inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
      };
      customPackages =
        lib.mapAttrs'
          (
            name: _:
            lib.nameValuePair (lib.removeSuffix ".nix" name) (pkgs.callPackage (pkgsDir + "/${name}") extraArgs)
          )
          (
            lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
              builtins.readDir pkgsDir
            )
          );
    in
    {
      formatter = pkgs.nixfmt-rfc-style;

      checks.diff-viewer = pkgs.runCommand "diff-viewer-tests" { } ''
        cd ${./.}
        PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 -m unittest tests/test_diff_viewer_header.py
        touch "$out"
      '';

      checks.mcpm-environment = pkgs.runCommand "mcpm-environment-tests" { } ''
        cd ${./.}
        PYTHONDONTWRITEBYTECODE=1 ${customPackages.mcpm.pythonEnv}/bin/python3 -m unittest tests/test_mcpm_env.py
        touch "$out"
      '';

      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.nil
          pkgs.nixfmt-rfc-style
          pkgs.statix
          pkgs.deadnix
        ];
      };

      packages = customPackages;
    };
}
