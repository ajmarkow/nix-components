# macOS.
{ sharedSettings }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-components.beszel.agent;
  # The agent persists its identity here. On NixOS the upstream module leaves
  # this to the agent's own default; a launchd daemon starts in / with no
  # writable cwd, so it has to be named.
  dataDir = "/var/lib/beszel-agent";
in
{
  _file = ./darwin.nix;
  key = "nix-components-beszel-agent-darwin";

  imports = [ sharedSettings ];

  nix-components.beszel.agent.tokenFile = lib.mkDefault "/etc/beszel-agent/token";

  # nix-darwin has no services.beszel.agent — nixpkgs' module is NixOS-only —
  # so the agent is a plain launchd daemon. Root, like every launchd daemon,
  # which is also what lets it read the 0600 tokenFile directly: there is no
  # LoadCredential equivalent here.
  #
  # `command` rather than serviceConfig.ProgramArguments so nix-darwin wraps
  # the call in `wait4path /nix/store`. A daemon starts early enough at boot
  # to beat the store being mounted.
  launchd.daemons.beszel-agent = {
    command = lib.getExe' pkgs.beszel "beszel-agent";
    environment = {
      KEY = cfg.hubKey;
      HUB_URL = cfg.hubUrl;
      LISTEN = toString cfg.port;
      TOKEN_FILE = cfg.tokenFile;
      DATA_DIR = dataDir;
    }
    // cfg.extraEnvironment;
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/beszel-agent.log";
      StandardErrorPath = "/var/log/beszel-agent.log";
    };
  };

  system.activationScripts.beszelAgentDataDir.text = ''
    mkdir -p ${dataDir}
    chmod 700 ${dataDir}
  '';

  assertions = [
    {
      assertion = !cfg.openFirewall;
      message = ''
        nix-components.beszel.agent.openFirewall is NixOS-only. macOS has no
        nix-darwin-managed firewall to open, and the universal-token flow is
        outbound-only, so nothing needs opening.
      '';
    }
    {
      assertion = !cfg.smartmon.enable;
      message = ''
        nix-components.beszel.agent.smartmon.enable is NixOS-only: it is
        implemented as a udev rule, the `disk` group and Linux capabilities.
      '';
    }
  ];
}
