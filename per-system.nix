{ ... }:
{
  perSystem =
    { pkgs, ... }:
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

      packages = {
        summarize = pkgs.callPackage ./pkgs/summarize.nix { };
      };
    };
}
