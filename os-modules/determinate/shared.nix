# Shared option surface and cachix push hook used by both
# os-modules/determinate/darwin.nix and os-modules/determinate/nixos.nix.
{
  # Determinate Nix wiring plus the substituter / trusted-key / trusted-user
  # baseline shared by every host repo: nix-mac, nix-server, nix-pixelbook.
  #
  # Deliberately NOT in `modules/`: `nix.*`, `determinateNix.*` and
  # `determinate.*` are NixOS / nix-darwin *system* namespaces, and
  # home-modules.nix auto-exports every modules/*.nix as a homeModule.
  #
  # Why the settings live behind our own `nix-components.determinate.*` list
  # options instead of being written straight into the upstream attributes:
  # both `determinateNix.customSettings` (nix-darwin) and `nix.settings`
  # (NixOS) are freeform submodules typed `attrsOf (either atom (listOf
  # atom))`. An undeclared key like `extra-substituters` therefore resolves to
  # `either`, which *errors* on a second definition rather than concatenating
  # the lists. So if this module wrote the key directly, no host could ever
  # add a cache of its own without `mkForce` and a full copy of the baseline.
  # A plain `listOf str` option merges across definitions, which is what we
  # want: nix-components sets the baseline, hosts append.
  sharedSettings =
    { lib, pkgs, ... }:
    {
      key = "nix-components-determinate-shared-settings";

      options.nix-components.determinate = {
        pushCache = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Push every locally built store path to
              {option}`nix-components.determinate.pushCache.name` via a
              `post-build-hook`.

              Off by default: it needs a `CACHIX_AUTH_TOKEN` provisioned
              out-of-band on the host, and a host that pushes nothing useful
              (or has no token) should not be running the hook at all.

              Enabled on the two x86_64-linux hosts, which share an
              architecture and so actually serve each other. The Mac is
              deliberately pull-only — its aarch64-darwin paths would only ever
              serve itself and nix-components' darwin CI leg, which does its
              own pushing from the runner.
            '';
          };

          name = lib.mkOption {
            type = lib.types.str;
            default = "ajmarkow";
            description = "Cachix cache name to push to.";
          };

          secretsFile = lib.mkOption {
            type = lib.types.str;
            default =
              if pkgs.stdenv.isDarwin then
                "/etc/nix-darwin/secrets/cachix.env"
              else
                "/etc/nixos/secrets/cachix.env";
            defaultText = "/etc/nixos/secrets/cachix.env (/etc/nix-darwin/... on darwin)";
            description = ''
              File defining `CACHIX_AUTH_TOKEN`, sourced by the hook at build
              time so the token never enters the Nix store. Root-owned 0600.
              Path convention follows modules/agent-dropbox.nix.
            '';
          };
        };

        substituters = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Binary caches added to every host, as `extra-substituters`. Hosts
            append to this list rather than replacing it.
          '';
        };

        trustedPublicKeys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Public keys for {option}`nix-components.determinate.substituters`,
            added as `extra-trusted-public-keys`. A cache without a matching
            key here is silently ignored, so the two lists must stay in step.
          '';
        };

        trustedUsers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Users granted `trusted-users`. This is what lets nix honor
            `extra-substituters` and `extra-trusted-public-keys` declared by a
            flake input's own `nixConfig`, instead of ignoring them as
            untrusted. Hosts add their own login user.
          '';
        };
      };

      config.nix-components.determinate = {
        # Lists live in ../../caches.nix, shared with the flake nixConfig
        # parity check and nix-cache-doctor.
        inherit (import ../../caches.nix) substituters trustedPublicKeys;

        trustedUsers = [ "root" ];
      };
    };

  # The cachix push hook, shared because both platforms need the same script and
  # only the option it lands in differs: nix-darwin's whole `nix.*` tree is inert
  # under `nix.enable = false`, so on darwin this has to go into
  # `determinateNix.customSettings` instead of `nix.settings`. `post-build-hook`
  # is not in Determinate's disallowedOptions list, so the custom conf accepts it.
  #
  # Script copied verbatim from nix-server's modules/common.nix, which was the
  # only host doing this, with the cache name and secrets path parameterised:
  #   - `set -f` + `IFS=' '` because $OUT_PATHS is a space-separated list that
  #     must not be glob-expanded.
  #   - guarded on the secrets file so a host without a token is a no-op rather
  #     than a failed build.
  #   - `|| true` so a cachix outage never fails a build.
  pushHook =
    {
      lib,
      pkgs,
      config,
    }:
    let
      cfg = config.nix-components.determinate.pushCache;
    in
    lib.mkIf cfg.enable (
      toString (
        pkgs.writeShellScript "cachix-push" ''
          set -f
          export IFS=' '
          if [ -f ${cfg.secretsFile} ]; then
            . ${cfg.secretsFile}
            export CACHIX_AUTH_TOKEN
            echo "$OUT_PATHS" | xargs -r ${pkgs.cachix}/bin/cachix push ${cfg.name} || true
          fi
        ''
      )
    );
}
