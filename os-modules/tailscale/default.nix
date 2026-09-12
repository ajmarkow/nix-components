# Returns the two OS-level Tailscale modules. os-modules.nix assembles them into
# flake.darwinModules / flake.nixosModules; they are not flake outputs on their
# own, for the same reason as determinate.nix — flake-parts treats
# `flake.darwinModules` as a freeform attribute and so rejects two modules both
# defining it.
#
# Takes no arguments, unlike determinate.nix: there is no upstream flake module
# to import here, so `inputs` is not needed.
let
  sharedSettings = import ./shared.nix;
in
{
  darwin = import ./darwin.nix { inherit sharedSettings; };
  nixos = import ./nixos.nix { inherit sharedSettings; };
}
