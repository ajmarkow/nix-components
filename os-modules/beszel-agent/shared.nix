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
}
