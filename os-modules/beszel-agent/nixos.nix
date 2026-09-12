# NixOS.
{ sharedSettings }:
{ config, lib, ... }:
let
  cfg = config.nix-components.beszel.agent;
  # systemd stages every LoadCredential= under $CREDENTIALS_DIRECTORY, which
  # for a system service is always /run/credentials/<unit>. Spelled out rather
  # than as the `%d` specifier: %d resolves to "$CREDENTIALS_DIRECTORY if
  # available", and a specifier that fails to resolve invalidates the whole
  # setting, which would fail silently into an agent that cannot authenticate.
  credentialDir = "/run/credentials/beszel-agent.service";
in
{
  _file = ./nixos.nix;
  key = "nix-components-beszel-agent-nixos";

  imports = [ sharedSettings ];

  nix-components.beszel.agent.tokenFile = lib.mkDefault "/etc/nixos/secrets/beszel-token";

  services.beszel.agent = {
    enable = true;
    smartmon.enable = cfg.smartmon.enable;

    # Always false, and the port is opened below instead. nixpkgs' own
    # openFirewall reads `environment.PORT` to decide which port to open, but
    # the agent's actual option is `LISTEN` — so a non-default port would
    # silently open 45876 while the agent listened somewhere else.
    openFirewall = false;

    environment = {
      KEY = cfg.hubKey;
      HUB_URL = cfg.hubUrl;
      LISTEN = toString cfg.port;
      TOKEN_FILE = "${credentialDir}/token";
    }
    // cfg.extraEnvironment;
  };

  # systemd reads the token as root, then re-exposes it under the unit's
  # credentials directory owned by the service user.
  #
  # The alternative — pointing TOKEN_FILE straight at cfg.tokenFile — does not
  # work: the agent runs as a DynamicUser under ProtectSystem=strict, so it
  # cannot read a root-owned 0600 file, and chowning the secret to
  # beszel-agent instead would require that user to already exist when the
  # secret is provisioned. On a fresh host it does not; provisioning runs
  # before the first rebuild creates the user.
  systemd.services.beszel-agent.serviceConfig.LoadCredential = [ "token:${cfg.tokenFile}" ];

  networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
}
