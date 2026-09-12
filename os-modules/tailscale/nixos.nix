# NixOS.
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
  _file = ./nixos.nix;
  key = "nix-components-tailscale-nixos";

  imports = [ sharedSettings ];

  services.tailscale = {
    enable = true;
    extraSetFlags = lib.optional (cfg.operator != null) "--operator=${cfg.operator}";
  };

  systemd = {
    # Auto-restart tailscaled if it crashes (prevents lockout situations).
    services.tailscaled.serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };

    # tailscaled's Restart=on-failure above only covers crashes (process exit).
    # It does NOT cover a hung-but-alive process, nor a stalled/expired
    # tailnet link while the process itself stays up. On a host whose remote
    # access is gated on the tailscale0 interface, a silent outage locks us
    # out entirely. This timer polls `tailscale status` (bounded by
    # `timeout`, so a hang counts as a failure too), restarts tailscaled if
    # it's down or hung, and after 3 consecutive failed checks sends an alert
    # via shoutrrr so an outage doesn't go unnoticed until we happen to need
    # remote access.
    #
    # Lifted from nix-server, which had the only copy. The interval (2min)
    # and threshold (3) are hardcoded rather than options — no host needs to
    # vary them, and an interval option would desync from the timer's own
    # description.
    services.tailscale-healthcheck = lib.mkIf cfg.healthcheck.enable {
      description = "Check tailscaled health and alert on prolonged outage";
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = "-${cfg.healthcheck.secretsFile}";
      };
      path = [
        pkgs.tailscale
        pkgs.shoutrrr
        pkgs.jq
        pkgs.coreutils
        pkgs.systemd
      ];
      script = ''
        set -u
        STATE_FILE=/run/tailscale-healthcheck.failcount
        FAIL_THRESHOLD=3
        count=0
        # NOTE: `script` runs with `set -e`. A bare `[ cond ] && cmd` aborts
        # the whole script if cond is false — always use if-blocks here,
        # never that shorthand, or the common (file-missing /
        # not-yet-Running) case exits silently before the check runs.
        if [ -f "$STATE_FILE" ]; then
          count=$(cat "$STATE_FILE")
        fi

        healthy=0
        if state=$(timeout 10 tailscale status --json 2>/dev/null); then
          backend=$(echo "$state" | jq -r '.BackendState // "unknown"')
          if [ "$backend" = "Running" ]; then
            healthy=1
          fi
        fi

        if [ "$healthy" = "1" ]; then
          # Recovered: notify only if we'd previously escalated, then reset.
          if [ "$count" -ge "$FAIL_THRESHOLD" ] && [ -n "''${SHOUTRRR_URL:-}" ]; then
            shoutrrr send -u "$SHOUTRRR_URL" -m "tailscale on ${config.networking.hostName}: RECOVERED after $count failed checks" || true
          fi
          rm -f "$STATE_FILE"
          exit 0
        fi

        count=$((count + 1))
        echo "$count" > "$STATE_FILE"
        echo "tailscale-healthcheck: unhealthy (consecutive failures: $count), restarting tailscaled" >&2
        systemctl restart tailscaled || true

        if [ "$count" -eq "$FAIL_THRESHOLD" ]; then
          if [ -n "''${SHOUTRRR_URL:-}" ]; then
            shoutrrr send -u "$SHOUTRRR_URL" -m "tailscale on ${config.networking.hostName} has been DOWN for $count consecutive checks. Remote access via tailscale0 may be unavailable." || true
          else
            echo "tailscale-healthcheck: $count consecutive failures but SHOUTRRR_URL is unset — no alert sent, check journalctl -u tailscale-healthcheck" >&2
          fi
        fi
      '';
    };

    timers.tailscale-healthcheck = lib.mkIf cfg.healthcheck.enable {
      description = "Run tailscale-healthcheck every 2 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "2min";
        Unit = "tailscale-healthcheck.service";
      };
    };
  };
}
