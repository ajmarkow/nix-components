{ config, lib, pkgs, ... }:
let
  cfg = config.services.diffViewer;
  outputDir = "${config.home.homeDirectory}/diff-viewer";
  port = 18092;
  servePath = "/diffs";

  # Wrapper so the same payload runs under both launchd and systemd.user:
  # (re)register the tailscale serve path on every start (idempotent — safe
  # to repeat), then exec the local file server. `tailscale serve` requires
  # operator permission on the local tailscaled (system config:
  # services.tailscale.extraSetFlags = [ "--operator=<user>" ]) — until that's
  # provisioned this silently no-ops (`|| true`) so the local server still
  # comes up, it's just unreachable over the tailnet until the grant lands.
  #
  # `--https=${tailnetPort}` is load-bearing: never let this default back to
  # 443. `tailscale serve --bg` on 443 leaves a persistent tailscaled listener
  # on the tailnet IP that survives service restarts. On a host that also
  # runs a reverse proxy (e.g. Traefik in podman) bound to the wildcard
  # address on 443, tailscaled wins the bind race at boot and the proxy can
  # never reclaim the port after any restart — which took down every routed
  # service on nixos-host on 2026-08-19. See nix-server commits 721f1f85
  # (Traefik pinned off wildcard as a partial mitigation) and a5c7a192 /
  # 4ca4996 (the deploy + rollback that triggered the outage). Fixed here by
  # keeping diff-viewer off 443 entirely.
  startScript = pkgs.writeShellScript "diff-viewer-start" ''
    ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.tailnetPort} --set-path=${servePath} ${toString port} || true
    exec ${pkgs.static-web-server}/bin/static-web-server \
      --host 127.0.0.1 --port ${toString port} \
      --root ${outputDir} \
      --directory-listing true \
      --log-level warn
  '';

  cleanupCmd = "${pkgs.findutils}/bin/find ${outputDir} -name '*.html' -mtime +30 -delete";
in
{
  options.services.diffViewer.tailnetPort = lib.mkOption {
    type = lib.types.port;
    default = 8443;
    description = ''
      Tailnet HTTPS port the diff-viewer skill is served on via
      `tailscale serve`. Must not be 443 — see the comment on
      `startScript` in this module for why.
    '';
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.tailnetPort != 443;
          message = ''
            services.diffViewer.tailnetPort must not be 443: tailscale serve
            --bg would then claim the tailnet IP's port 443 permanently,
            colliding with any host reverse proxy bound to the wildcard
            address. See the comment on `startScript` in
            modules/diff-viewer.nix for the incident this caused.
          '';
        }
      ];

      home.file."diff-viewer/.keep".text = "";
    }
    (lib.mkIf pkgs.stdenv.isDarwin {
      launchd.agents.diff-viewer-server = {
        enable = true;
        config = {
          ProgramArguments = [ "${startScript}" ];
          RunAtLoad = true;
          KeepAlive = true;
        };
      };
      launchd.agents.diff-viewer-cleanup = {
        enable = true;
        config = {
          ProgramArguments = [ "${pkgs.bash}/bin/bash" "-c" cleanupCmd ];
          StartInterval = 86400;
          RunAtLoad = false;
        };
      };
    })
    (lib.mkIf (!pkgs.stdenv.isDarwin) {
      systemd.user.services.diff-viewer-server = {
        Unit.Description = "Local static server for the diff-viewer skill, exposed via tailscale serve";
        Service = {
          ExecStart = "${startScript}";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
      systemd.user.services.diff-viewer-cleanup = {
        Unit.Description = "Delete diff-viewer HTML files older than 30 days";
        Service = {
          Type = "oneshot";
          ExecStart = cleanupCmd;
        };
      };
      systemd.user.timers.diff-viewer-cleanup = {
        Unit.Description = "Timer for diff-viewer-cleanup";
        Timer = {
          OnBootSec = "1h";
          OnUnitActiveSec = "1d";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ];
}
