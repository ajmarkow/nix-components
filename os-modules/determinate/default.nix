# Returns the two OS-level Determinate modules. os-modules.nix assembles them
# into flake.darwinModules / flake.nixosModules; they are not flake outputs on
# their own, because flake-parts treats `flake.darwinModules` as a freeform
# attribute and so rejects two modules both defining it.
{ inputs }:
let
  shared = import ./shared.nix;
in
{
  darwin = import ./darwin.nix {
    inherit inputs;
    inherit (shared) sharedSettings pushHook;
  };
  nixos = import ./nixos.nix {
    inherit inputs;
    inherit (shared) sharedSettings pushHook;
  };
}
