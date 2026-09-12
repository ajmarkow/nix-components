# macOS.
{ sharedSettings }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-components.tailscale;
in
{
  _file = ./darwin.nix;
  key = "nix-components-tailscale-darwin";

  imports = [ sharedSettings ];

  services.tailscale = {
    enable = true;
    # Explicit package: the plain nixpkgs (open-source) tailscale CLI +
    # tailscaled, not the sandboxed Mac App Store "Tailscale" app. The App
    # Store build's sandbox entitlements don't permit `tailscale
    # serve`/`funnel`, which the diff-viewer module depends on — if a Mac App
    # Store Tailscale install is also present on the machine, remove it so it
    # doesn't shadow or conflict with this one. `homebrew.onActivation.cleanup
    # = "uninstall"` will not remove a MAS-installed app.
    package = pkgs.tailscale;
  };

  # nix-darwin's tailscale module has no extraSetFlags option (unlike NixOS's
  # — it declares only enable/package/overrideLocalDns), so the operator grant
  # is done via an activation script instead: idempotent, and non-fatal if
  # tailscaled isn't up yet on first activation.
  system.activationScripts.tailscaleOperator.text = lib.optionalString (cfg.operator != null) ''
    ${pkgs.tailscale}/bin/tailscale set --operator=${cfg.operator} || true
  '';

  # The healthcheck is a systemd timer + shoutrrr; there is no launchd
  # equivalent here. Fail loudly rather than silently ignoring the option.
  assertions = [
    {
      assertion = !cfg.healthcheck.enable;
      message = ''
        nix-components.tailscale.healthcheck.enable is NixOS-only and cannot
        be used on darwin: it is implemented as a systemd service + timer.
      '';
    }
  ];
}
