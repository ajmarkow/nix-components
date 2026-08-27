# Returns the two OS-level Tailscale modules. os-modules.nix assembles them into
# flake.darwinModules / flake.nixosModules; they are not flake outputs on their
# own, for the same reason as determinate.nix — flake-parts treats
# `flake.darwinModules` as a freeform attribute and so rejects two modules both
# defining it.
#
# Takes no arguments, unlike determinate.nix: there is no upstream flake module
# to import here, so `inputs` is not needed.
let
  # Tailscale baseline shared by every host repo: nix-mac, nix-server,
  # nix-pixelbook. All three had their own copy, in three different shapes
  # (nix-server inline in modules/common.nix next to sshd, nix-pixelbook in
  # aj-modules/nixos/tailscale.nix, nix-mac inline in flake.nix), each carrying a
  # hand-written duplicate of the operator-grant rationale below.
  #
  # Deliberately NOT in `modules/`: `services.tailscale.*` and `systemd.services.*`
  # are NixOS / nix-darwin *system* namespaces, and home-modules.nix auto-exports
  # every modules/*.nix as a homeModule.
  #
  # There is no `enable` option — importing the module enables tailscale, matching
  # os-modules/determinate.nix.
  sharedSettings =
    { lib, ... }:
    {
      key = "nix-components-tailscale-shared-settings";

      options.nix-components.tailscale = {
        operator = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "ajmarkow";
          description = ''
            User granted "operator" rights over the local tailscaled, so it can
            run `tailscale serve`/`funnel` without root or interactive sudo.

            Needed by this repo's diff-viewer home-manager module, which runs
            `tailscale serve --bg --set-path=/diffs ...` as that user to publish
            rendered diffs over the tailnet. Without the grant, tailscaled
            rejects those calls with "Access denied: serve config denied" and
            diff URLs 404.

            `null` grants nobody. The two platforms reach the same result by
            different means: NixOS has `services.tailscale.extraSetFlags`,
            nix-darwin has no equivalent option so it goes through an activation
            script instead.
          '';
        };

        healthcheck = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Poll `tailscale status` every 2 minutes, restart tailscaled when
              it is down or hung, and alert via shoutrrr after 3 consecutive
              failures.

              NixOS only — the darwin variant asserts this is off.

              Off by default: it needs a `SHOUTRRR_URL` provisioned out-of-band
              in {option}`nix-components.tailscale.healthcheck.secretsFile`, and
              only matters on a host whose remote access is gated on the tailnet
              in the first place. Enabled on nix-server, which is that host.
            '';
          };

          secretsFile = lib.mkOption {
            type = lib.types.str;
            default = "/etc/nixos/secrets/tailscale-alert.env";
            description = ''
              File defining `SHOUTRRR_URL`, read as an `EnvironmentFile` so the
              webhook never enters the Nix store. Root-owned 0600. Path
              convention follows os-modules/determinate.nix.

              Optional at run time (the unit prefixes it with `-`): an
              unprovisioned host still restarts tailscaled, it just logs to the
              journal instead of alerting.
            '';
          };
        };
      };
    };
in
{
  # macOS.
  darwin =
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
      _file = ./tailscale.nix;
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
    };

  # NixOS.
  nixos =
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
      _file = ./tailscale.nix;
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
    };
}
