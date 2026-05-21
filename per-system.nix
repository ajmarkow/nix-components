{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      pkgsDir = ./pkgs;
      customPackages = lib.mapAttrs'
        (name: _: lib.nameValuePair
          (lib.removeSuffix ".nix" name)
          (pkgs.callPackage (pkgsDir + "/${name}") { }))
        (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name)
          (builtins.readDir pkgsDir));
    in
    {
      formatter = pkgs.nixfmt-rfc-style;

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
