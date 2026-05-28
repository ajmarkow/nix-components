{ lib, inputs, ... }:
let
  pkgsDir = ./pkgs;
  extraArgs = {
    inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
  };
in
{
  flake.overlays.default = final: _prev:
    let
      nixComponentsPkgs = inputs.nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system};
    in
    lib.mapAttrs'
      (name: _: lib.nameValuePair
        (lib.removeSuffix ".nix" name)
        (nixComponentsPkgs.callPackage (pkgsDir + "/${name}") extraArgs))
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir pkgsDir));
}
