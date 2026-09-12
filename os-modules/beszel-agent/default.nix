# Returns the two OS-level Beszel *agent* modules. os-modules.nix assembles them
# into flake.darwinModules / flake.nixosModules; they are not flake outputs on
# their own, for the same reason as determinate.nix — flake-parts treats
# `flake.darwinModules` as a freeform attribute and so rejects two modules both
# defining it.
#
# Takes no arguments, like tailscale.nix: there is no upstream flake module to
# import here.
#
# Agent only, never the hub. The hub stays a single rootless-podman container in
# nix-server (services.podman.containers.beszel); nothing about it is shared.
let
  sharedSettings = import ./shared.nix;
in
{
  darwin = import ./darwin.nix { inherit sharedSettings; };
  nixos = import ./nixos.nix { inherit sharedSettings; };
}
