{ lib, inputs, ... }:
let
  determinate = import ./os-modules/determinate.nix { inherit inputs; };
  tailscale = import ./os-modules/tailscale.nix;

  # OS-level (NixOS / nix-darwin) home-manager defaults shared by every host
  # repo: nix-mac, nix-server, nix-pixelbook.
  #
  # Deliberately NOT in `modules/`: `home-manager.*` is a *system* namespace
  # option, declared by home-manager's own nixos/common.nix, so it cannot be
  # set from inside `home-manager.users.<name>`. home-modules.nix auto-exports
  # every modules/*.nix as a homeModule, which this is not.
  #
  # overwriteBackup makes activation replace a stale <file>.backup instead of
  # aborting with "Existing file '<file>.backup' would be clobbered by backing
  # up '<file>'". Without it, backupFileExtension only survives ONE activation
  # per unmanaged file: the first switch moves the file aside, the next one
  # dies on the leftover backup. Hit this repeatedly on files that a runtime
  # process rewrites outside home-manager's control (e.g. the paseo daemon
  # merging its hooks into ~/.claude/settings.json).
  #
  # mkDefault so a host can still override, and so a host that has not yet
  # dropped its own `backupFileExtension = "backup"` line does not conflict
  # while the nix-components input bump rolls out.
  homeManagerBackup = {
    _file = ./os-modules.nix;
    key = "nix-components-home-manager-backup";
    home-manager.backupFileExtension = lib.mkDefault "backup";
    home-manager.overwriteBackup = lib.mkDefault true;
  };
in
{
  flake.darwinModules = {
    home-manager-backup = homeManagerBackup;
    determinate = determinate.darwin;
    tailscale = tailscale.darwin;
  };

  flake.nixosModules = {
    home-manager-backup = homeManagerBackup;
    determinate = determinate.nixos;
    tailscale = tailscale.nixos;
  };
}
