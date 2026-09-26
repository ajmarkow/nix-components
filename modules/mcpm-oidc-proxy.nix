# This file must stay a top-level modules/*.nix file: home-modules.nix
# auto-exports it as homeModules.mcpm-oidc-proxy by readDir'ing this
# directory (top-level regular files only).
#
# Home-manager half of the "second door" for mcpm (see modules/mcp.nix,
# the home-manager half of mcpm itself, and os-modules/mcpm-serve.nix, the
# NixOS-system half of mcpm's *first* door). This module runs the OIDC-gated
# sidecar (pkgs/mcpm-oidc-proxy.nix) that fronts the same mcpm backend for
# clients that cannot reach the tailnet -- see
# nix-server/plans/mcpm-claude-connector-oidc.md for the full design. The
# existing tailnet door (svc:mcpm via os-modules/mcpm-serve.nix) is
# completely untouched by this module.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-components.mcpmOidcProxy;

  # A systemd user service never sources zsh init, so it starts with none of
  # the OIDC_* secrets the sidecar needs -- same reasoning as modules/mcp.nix's
  # serviceScript, reusing the same secrets-file-sourcing idiom.
  serviceScript = pkgs.writeShellScript "mcpm-oidc-proxy-start" ''
    set -eu
    if [ -r /etc/nixos/secrets/mcpm-oidc-proxy.env ]; then
      set -a
      . /etc/nixos/secrets/mcpm-oidc-proxy.env
      set +a
    fi
    exec ${lib.getExe pkgs.mcpm-oidc-proxy}
  '';
in
{
  options.nix-components.mcpmOidcProxy = {
    enable = lib.mkEnableOption "the OIDC-gated public sidecar in front of the local mcpm aggregate";
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    systemd.user.services.mcpm-oidc-proxy = {
      Unit = {
        Description = "mcpm public connector: OIDC-gated FastMCP proxy in front of mcpm";
        # The sidecar's own OIDCProxy fetches Authelia's OIDC discovery
        # document synchronously at construction and crashes at startup if
        # it isn't reachable yet -- ordering after mcpm.service doesn't fix
        # that (different dependency), but starting after the backend it
        # proxies to at least avoids a guaranteed-empty upstream on the
        # calls that do get through before Authelia is confirmed live.
        After = [ "mcpm.service" ];
      };
      Service = {
        ExecStart = "${serviceScript}";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        # FastMCP's OAuthProxy persists its token cache to a DiskStore under
        # $HOME/.local/share/fastmcp/oauth-proxy (fastmcp's own default data
        # dir, not something this module configures) -- confirmed live
        # 2026-09-26: ProtectHome=read-only alone left it unable to mkdir
        # that path and it crash-looped on every start.
        ReadWritePaths = [ "%h/.local/share/fastmcp" ];
        PrivateTmp = true;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
