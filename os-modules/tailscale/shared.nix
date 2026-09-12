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
}
