# macOS. Determinate manages the Nix installation itself, entirely outside
# nix-darwin: upstream's module only sets `nix.enable = mkForce false` and
# writes /etc/nix/nix.custom.conf, /etc/nix/registry.json and
# /etc/determinate/config.json. It installs no Nix and asserts nothing about
# Determinate being present, so the .pkg installer
# (https://install.determinate.systems/determinate-pkg/stable/Universal) must
# have run on the machine BEFORE the first activation. Activating first makes
# nix-darwin restore whatever unmanaged daemon is in
# /nix/var/nix/profiles/default and leaves /etc/nix/nix.conf unmanaged, i.e.
# no experimental-features, i.e. no flakes, i.e. no way to rebuild back out.
#
# Note that with `nix.enable = false` every other `nix.*` option becomes
# silently inert — nix-darwin wraps its whole nix config in `handleUnmanaged`
# with no warning. A host's leftover `nix.settings` / `nix.gc` /
# `nix.optimise` blocks are dead code and should be deleted, not kept.
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
  _file = ./darwin.nix;
  key = "nix-components-determinate-darwin";

  imports = [
    inputs.determinate.darwinModules.default
    sharedSettings
  ];

  determinateNix = {
    # Replaces the per-host `nix.gc` + `nix.optimise` pairs, which differed
    # (14d on the Mac, 30d on the pixelbook) and are inert under
    # `nix.enable = false` anyway. determinate-nixd collects in the
    # background against free disk space instead of a fixed age.
    determinateNixd.garbageCollector.strategy = lib.mkDefault "automatic";

    customSettings = {
      extra-substituters = config.nix-components.determinate.substituters;
      extra-trusted-public-keys = config.nix-components.determinate.trustedPublicKeys;
      # Plain `trusted-users`, so this *replaces* whatever Determinate's
      # own nix.conf lists rather than extending it — hence keeping "root"
      # in the baseline. (nix always trusts root regardless, but being
      # explicit here means the rendered nix.conf reads correctly.)
      trusted-users = config.nix-components.determinate.trustedUsers;

      # Into customSettings rather than nix.settings, because nix-darwin's
      # whole nix tree is inert under `nix.enable = false`. No darwin host
      # enables pushCache today (the Mac is pull-only), so this branch is
      # for symmetry rather than current use.
      post-build-hook = pushHook { inherit lib pkgs config; };
    };
  };
}
