{ config, lib, pkgs, ... }:
let
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
  startScript = pkgs.writeShellScript "diff-viewer-start" ''
    ${pkgs.tailscale}/bin/tailscale serve --bg --set-path=${servePath} ${toString port} || true
    exec ${pkgs.static-web-server}/bin/static-web-server \
      --host 127.0.0.1 --port ${toString port} \
      --root ${outputDir} \
      --directory-listing true \
      --log-level warn
  '';

  cleanupCmd = "${pkgs.findutils}/bin/find ${outputDir} -name '*.html' -mtime +30 -delete";
in
lib.mkMerge [
  {
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
]
