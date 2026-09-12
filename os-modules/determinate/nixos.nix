# NixOS. Fully declarative, no installer: upstream's module sets
# `nix.package` to Determinate Nix, swaps the nix-daemon unit's ExecStart to
# determinate-nixd, adds a determinate-nixd socket, and redirects the
# generated nix.conf to /etc/nix/nix.custom.conf. Unlike the darwin path it
# does NOT disable `nix.*`, so ordinary `nix.settings`, `nix.extraOptions`
# and a `post-build-hook` all keep working — they just land in the custom
# conf that determinate-nixd includes.
#
# The first `nixos-rebuild` after adding this needs
#   --option extra-substituters https://install.determinate.systems
#   --option extra-trusted-public-keys cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM=
# or it builds Determinate Nix from source.
{
  inputs,
  sharedSettings,
  pushHook,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
{
  _file = ./nixos.nix;
  key = "nix-components-determinate-nixos";

  imports = [
    inputs.determinate.nixosModules.default
    sharedSettings
  ];

  nix = {
    # `extra-*` rather than the plain keys so this merges with, rather than
    # fights, a host that still has its own `nix.settings.substituters`
    # during the rollout.
    settings = {
      extra-substituters = config.nix-components.determinate.substituters;
      extra-trusted-public-keys = config.nix-components.determinate.trustedPublicKeys;
      # Renders as "root root <user>": nixpkgs' nix module defines
      # trusted-users in `config` (not as a `default`), so it merges with
      # ours rather than being replaced, and our baseline repeats "root".
      # Left alone deliberately — nix ignores the duplicate, and dropping
      # "root" from the baseline would weaken the darwin side, where this
      # same list replaces Determinate's own value instead of merging.
      trusted-users = config.nix-components.determinate.trustedUsers;

      # nix.settings works normally here: unlike the nix-darwin module, the
      # NixOS one does not disable `nix.*`. Enabled on this repo's two
      # x86_64-linux hosts; previously this hook lived only in nix-server.
      post-build-hook = pushHook { inherit lib pkgs config; };
    };

    # Garbage collection, and why it does not look like the darwin side.
    #
    # The two platforms cannot share one setting, because upstream does not
    # offer one. `nixosModules.default` declares only `determinate.enable`
    # and `determinate.edgeCacheSubstituters` — there is no
    # `garbageCollector` option — and it writes /etc/determinate/config.json
    # itself when edgeCacheSubstituters is set, so writing that file by hand
    # here would collide with it.
    #
    # What makes that acceptable: unlike the nix-darwin module, this one
    # does NOT disable `nix.*`, so NixOS's own `nix.gc` and `nix.optimise`
    # keep working normally and just write into nix.custom.conf. So the
    # darwin side delegates GC to determinate-nixd (free-space driven, no
    # age knob) and the NixOS side keeps an explicit age bound. Deliberate:
    # nix-server has had no GC policy at all, and an age bound we can read
    # beats depending on determinate-nixd's undocumented default.
    #
    # 14d/weekly carries over the shortest policy any host had: nix-mac's
    # 14d, originally a response to a 78%-full data volume. It tightens
    # nix-pixelbook's previous 30d, and nix-server gains a policy where it
    # had none. Tighter is the safer default for a shared baseline -- a
    # host that wants to keep generations longer can say so, since every
    # value below is a mkDefault.
    gc = {
      automatic = lib.mkDefault true;
      dates = lib.mkDefault "weekly";
      options = lib.mkDefault "--delete-older-than 14d";
    };

    optimise.automatic = lib.mkDefault true;
  };
}
