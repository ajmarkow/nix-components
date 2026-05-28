{ lib, inputs, ... }:
let
  pkgsDir = ./pkgs;
  extraArgs = {
    inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
  };
in
{
  flake.overlays.default = final: _prev:
    lib.mapAttrs'
      (name: _: lib.nameValuePair
        (lib.removeSuffix ".nix" name)
        (final.callPackage (pkgsDir + "/${name}") extraArgs))
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir pkgsDir));
}
