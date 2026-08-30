# Returns the two OS-level Beszel *agent* modules. os-modules.nix assembles them
# into flake.darwinModules / flake.nixosModules; they are not flake outputs on
# their own, for the same reason as determinate.nix — flake-parts treats
# `flake.darwinModules` as a freeform attribute and so rejects two modules both
# defining it.
#
# Takes no arguments, like tailscale.nix: there is no upstream flake module to
# import here.
#
# Agent only, never the hub. The hub stays a single rootless-podman container in
# nix-server (services.podman.containers.beszel); nothing about it is shared.
let
  # Beszel agent baseline shared by every host repo: nix-mac, nix-server,
  # nix-pixelbook. All three had their own copy, in three different shapes
  # (nix-server inline in modules/common.nix on top of nixpkgs'
  # services.beszel.agent, nix-mac as a hand-installed Homebrew formula from the
  # henrygd/beszel tap running as an unmanaged `brew services` job).
  #
  # Deliberately NOT in `modules/`: `services.beszel.*`, `systemd.services.*` and
  # `launchd.daemons.*` are NixOS / nix-darwin *system* namespaces, and
  # home-modules.nix auto-exports every modules/*.nix as a homeModule.
  #
  # There is no `enable` option — importing the module runs the agent, matching
  # os-modules/tailscale.nix and os-modules/determinate.nix.
  sharedSettings =
    { lib, ... }:
    {
      key = "nix-components-beszel-agent-shared-settings";

      options.nix-components.beszel.agent = {
        hubKey = lib.mkOption {
          type = lib.types.str;
          example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...";
          description = ''
            Public key the agent accepts hub connections from — beszel's `KEY`,
            shown in the hub's "Add System" dialog.

            No default on purpose. This repo is public and the host repos that
            consume it are private. The value is a *public* key, so committing
            it would leak no credential, but it identifies the hub, so it is set
            per host instead.
          '';
        };

        hubUrl = lib.mkOption {
          type = lib.types.str;
          example = "https://beszel.example.com";
          description = ''
            URL the agent opens its outgoing WebSocket to — beszel's `HUB_URL`.
            Together with {option}`nix-components.beszel.agent.tokenFile` this is
            what lets the agent register itself, so the host never has to be
            added in the hub's UI first.

            No default, for the same reason as
            {option}`nix-components.beszel.agent.hubKey`.
          '';
        };

        tokenFile = lib.mkOption {
          type = lib.types.str;
          description = ''
            File holding the hub's universal registration token
            (`/settings/tokens` in the hub), handed to the agent as `TOKEN_FILE`
            so the token never enters the Nix store. Root-owned 0600.

            One universal token covers every host, so the same value is
            provisioned everywhere (`BESZEL_UNIVERSAL_TOKEN` in Infisical) and
            each agent registers itself on first connect.

            Defaults per platform, because the two have no shared secrets
            convention: `/etc/nixos/secrets/beszel-token` on NixOS, which is
            where nix-server's existing provisioning pipeline already writes, and
            `/etc/beszel-agent/token` on darwin.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 45876;
          description = ''
            Port the agent listens on — beszel's `LISTEN`.

            Only the legacy inbound path uses it: with `HUB_URL` and a token set,
            the agent dials *out* to the hub and needs nothing opened. Left
            configurable because the agent listens either way, and a co-located
            hub may still reach it directly.
          '';
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Open {option}`nix-components.beszel.agent.port` to the network.

            NixOS only — the darwin variant asserts this is off.

            Off by default: the universal-token flow is outbound-only, so a host
            whose hub is remote never needs it. Turn it on only for a hub that
            connects inbound.
          '';
        };

        smartmon.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Let the agent read S.M.A.R.T. data via smartctl.

            NixOS only — the darwin variant asserts this is off, because the
            implementation is a udev rule, the `disk` group and two Linux
            capabilities.

            Without it the agent's systemd hardening (PrivateDevices, empty
            capability set, no `disk` group) blocks smartctl outright, so the hub
            shows no disk health however smartmontools is installed. Worth
            enabling on a host with real disks; pointless on one without.
          '';
        };

        extraEnvironment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            EXTRA_FILESYSTEMS = "sdb,sdc";
          };
          description = ''
            Extra agent environment variables, merged over the ones this module
            sets. Public — they land in the Nix store, so never a secret.

            See <https://beszel.dev/guide/environment-variables#agent>.
          '';
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
      cfg = config.nix-components.beszel.agent;
      # The agent persists its identity here. On NixOS the upstream module leaves
      # this to the agent's own default; a launchd daemon starts in / with no
      # writable cwd, so it has to be named.
      dataDir = "/var/lib/beszel-agent";
    in
    {
      _file = ./beszel-agent.nix;
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
    };

  # NixOS.
  nixos =
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
      _file = ./beszel-agent.nix;
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
    };
}
