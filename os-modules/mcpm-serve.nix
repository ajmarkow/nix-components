# Publishes the central mcpm aggregate as the Tailscale Service svc:mcpm.
#
# NixOS only, enabled only on nix-server: it owns the sole mcpm process
# (nix-components.mcp.server.enable for its paseo user), bound to loopback.
# This registration is what puts the tailnet HTTPS endpoint in front of it --
# no Funnel, no LAN/public port, mcpm itself never leaves 127.0.0.1.
#
# Deliberately NOT in `modules/`: `systemd.*` is a NixOS *system* namespace,
# and home-modules.nix auto-exports every modules/*.nix as a homeModule.
#
# There is a timer because `tailscale serve` only writes tailscaled's config:
# at boot this unit usually runs before tailscaled has authenticated, so one
# shot would fail with "Logged out." and never retry. Re-registering every
# 15 minutes also heals any drift without touching the running mcpm process.
#
# Access control is Tailscale identity only -- the whole-tailnet grant lives
# in the tailnet admin console (src ["*"], dst ["svc:mcpm"], ip ["443"]),
# not here. No application token.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-components.mcpmServe;
in
{
  key = "nix-components-mcpm-serve";

  options.nix-components.mcpmServe = {
    enable = lib.mkEnableOption "publish the local mcpm aggregate as a Tailscale Service";

    service = lib.mkOption {
      type = lib.types.str;
      default = "svc:mcpm";
      description = "Tailscale Service name mcpm is published as.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = ''
        HTTPS port on the service address. Port 443 here is safe: it binds
        the service's own virtual address, not the host's tailnet IP, so it
        cannot collide with a host reverse proxy the way `tailscale serve`
        on 443 without --service would.
      '';
    };

    target = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:6276";
      description = "Local mcpm HTTP endpoint the service proxies to.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.mcpm-tailscale-serve = {
      description = "Register ${cfg.service} pointing at the local mcpm aggregate";
      after = [
        "tailscaled.service"
        "network.target"
      ];
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.tailscale
        pkgs.coreutils
      ];
      script = ''
        set -eu
        for _ in $(seq 1 60); do
          if tailscale serve --service=${cfg.service} --bg --https=${toString cfg.httpsPort} ${cfg.target}; then
            exit 0
          fi
          sleep 5
        done
        echo "mcpm-serve: tailscale serve did not register after 5 minutes" >&2
        exit 1
      '';
    };

    systemd.timers.mcpm-tailscale-serve = {
      description = "Reconcile ${cfg.service} registration";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "15min";
        Unit = "mcpm-tailscale-serve.service";
      };
    };
  };
}
