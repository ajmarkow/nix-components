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
      description = ''
        Base local mcpm HTTP endpoint. Only its port number is used, as the
        start of the probe range below -- mcpm itself can still land on a
        higher port (see the probe loop's comment), so this is a starting
        point to discover from, not a value trusted as-is.
      '';
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
        pkgs.curl
        pkgs.gnused
      ];
      script = ''
        set -eu
        base_port=$(echo "${cfg.target}" | sed -E 's#^https?://[^:]+:([0-9]+).*#\1#')

        # mcpm's own port-probe can still land on a port other than
        # base_port (its find_available_port walks up to 9 ports past the
        # one it was asked for -- see pkgs/mcpm.nix's SO_REUSEADDR patch for
        # why that can happen even when base_port is free). Rather than
        # trust a fixed port, find whichever one mcpm actually answers on
        # and register that, so this reconciles reality instead of an
        # assumption -- self-healing against a wrong port, not just a
        # boot-time tailscaled auth race.
        for _ in $(seq 1 60); do
          for offset in $(seq 0 9); do
            port=$((base_port + offset))
            # A bare GET without an SSE Accept header still gets a 406 from
            # mcpm's streamable-HTTP endpoint -- that response, not a 200,
            # is the proof of life here (see plan-obsidian-agentic.md).
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$port/mcp" || echo 000)
            if [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
              if tailscale serve --service=${cfg.service} --bg --https=${toString cfg.httpsPort} "http://127.0.0.1:$port"; then
                exit 0
              fi
            fi
          done
          sleep 5
        done
        echo "mcpm-serve: no live mcpm endpoint found / tailscale serve did not register after 5 minutes" >&2
        exit 1
      '';
    };

    systemd.timers.mcpm-tailscale-serve = {
      description = "Reconcile ${cfg.service} registration";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        # Short enough that a wrong-port drift (e.g. the mcpm.service
        # restart race this exists for) self-heals within a minute rather
        # than sitting broken for up to 15.
        OnUnitActiveSec = "1min";
        Unit = "mcpm-tailscale-serve.service";
      };
    };
  };
}
