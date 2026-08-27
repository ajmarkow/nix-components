# Returns the two OS-level Determinate modules. os-modules.nix assembles them
# into flake.darwinModules / flake.nixosModules; they are not flake outputs on
# their own, because flake-parts treats `flake.darwinModules` as a freeform
# attribute and so rejects two modules both defining it.
{ inputs }:
let
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
        # Copied verbatim from nix-server's modules/common.nix, which was the
        # only repo with a real cache list. One wrong character in a key makes
        # nix quietly skip the cache with no error, so do not retype these.
        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://ajmarkow.cachix.org"
          "https://claude-code.cachix.org"
          # Declared in this flake's own nixConfig, so consumers were only
          # getting it when they happened to be a trusted user.
          "https://codex-cli.cachix.org"
          # Was hand-managed in ~/.config/nix/nix.conf on the Mac, which meant
          # devenv shells only hit the cache for that one user on that one host.
          "https://devenv.cachix.org"
        ];

        trustedPublicKeys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBc="
          "ajmarkow.cachix.org-1:6HxkDVfkPWy2esadGzUIj6vGzmMuQOgz3mimKT7J9sw="
          "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
          "codex-cli.cachix.org-1:1Br3H1hHoRYG22n//cGKJOk3cQXgYobUel6O8DgSing="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];

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
in
{
  # macOS. Determinate manages the Nix installation itself, entirely outside
  # nix-darwin: upstream's module only sets `nix.enable = mkForce false` and
  # writes /etc/nix/nix.custom.conf, /etc/nix/registry.json and
  # /etc/determinate/config.json. It installs no Nix and asserts nothing about
  # Determinate being present, so the .pkg installer
  # (https://install.determinate.systems/determinate-pkg/stable/Universal) must
  # have run on the machine BEFORE the first activation. Activating first makes
  # nix-darwin restore whatever unmanaged daemon is in
  # /nix/var/nix/profiles/default and leaves /etc/nix/nix.conf unmanaged, i.e.
  # no experimental-features, i.e. no flakes, i.e. no way to rebuild back out.
  #
  # Note that with `nix.enable = false` every other `nix.*` option becomes
  # silently inert — nix-darwin wraps its whole nix config in `handleUnmanaged`
  # with no warning. A host's leftover `nix.settings` / `nix.gc` /
  # `nix.optimise` blocks are dead code and should be deleted, not kept.
  darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      _file = ./determinate.nix;
      key = "nix-components-determinate-darwin";

      imports = [
        inputs.determinate.darwinModules.default
        sharedSettings
      ];

      determinateNix = {
        # Replaces the per-host `nix.gc` + `nix.optimise` pairs, which differed
        # (14d on the Mac, 30d on the pixelbook) and are inert under
        # `nix.enable = false` anyway. determinate-nixd collects in the
        # background against free disk space instead of a fixed age.
        determinateNixd.garbageCollector.strategy = lib.mkDefault "automatic";

        customSettings = {
          extra-substituters = config.nix-components.determinate.substituters;
          extra-trusted-public-keys = config.nix-components.determinate.trustedPublicKeys;
          # Plain `trusted-users`, so this *replaces* whatever Determinate's
          # own nix.conf lists rather than extending it — hence keeping "root"
          # in the baseline. (nix always trusts root regardless, but being
          # explicit here means the rendered nix.conf reads correctly.)
          trusted-users = config.nix-components.determinate.trustedUsers;

          # Into customSettings rather than nix.settings, because nix-darwin's
          # whole nix tree is inert under `nix.enable = false`. No darwin host
          # enables pushCache today (the Mac is pull-only), so this branch is
          # for symmetry rather than current use.
          post-build-hook = pushHook { inherit lib pkgs config; };
        };
      };
    };

  # NixOS. Fully declarative, no installer: upstream's module sets
  # `nix.package` to Determinate Nix, swaps the nix-daemon unit's ExecStart to
  # determinate-nixd, adds a determinate-nixd socket, and redirects the
  # generated nix.conf to /etc/nix/nix.custom.conf. Unlike the darwin path it
  # does NOT disable `nix.*`, so ordinary `nix.settings`, `nix.extraOptions`
  # and a `post-build-hook` all keep working — they just land in the custom
  # conf that determinate-nixd includes.
  #
  # The first `nixos-rebuild` after adding this needs
  #   --option extra-substituters https://install.determinate.systems
  #   --option extra-trusted-public-keys cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM=
  # or it builds Determinate Nix from source.
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      _file = ./determinate.nix;
      key = "nix-components-determinate-nixos";

      imports = [
        inputs.determinate.nixosModules.default
        sharedSettings
      ];

      nix = {
        # `extra-*` rather than the plain keys so this merges with, rather than
        # fights, a host that still has its own `nix.settings.substituters`
        # during the rollout.
        settings = {
          extra-substituters = config.nix-components.determinate.substituters;
          extra-trusted-public-keys = config.nix-components.determinate.trustedPublicKeys;
          # Renders as "root root <user>": nixpkgs' nix module defines
          # trusted-users in `config` (not as a `default`), so it merges with
          # ours rather than being replaced, and our baseline repeats "root".
          # Left alone deliberately — nix ignores the duplicate, and dropping
          # "root" from the baseline would weaken the darwin side, where this
          # same list replaces Determinate's own value instead of merging.
          trusted-users = config.nix-components.determinate.trustedUsers;

          # nix.settings works normally here: unlike the nix-darwin module, the
          # NixOS one does not disable `nix.*`. Enabled on this repo's two
          # x86_64-linux hosts; previously this hook lived only in nix-server.
          post-build-hook = pushHook { inherit lib pkgs config; };
        };

        # Garbage collection, and why it does not look like the darwin side.
        #
        # The two platforms cannot share one setting, because upstream does not
        # offer one. `nixosModules.default` declares only `determinate.enable`
        # and `determinate.edgeCacheSubstituters` — there is no
        # `garbageCollector` option — and it writes /etc/determinate/config.json
        # itself when edgeCacheSubstituters is set, so writing that file by hand
        # here would collide with it.
        #
        # What makes that acceptable: unlike the nix-darwin module, this one
        # does NOT disable `nix.*`, so NixOS's own `nix.gc` and `nix.optimise`
        # keep working normally and just write into nix.custom.conf. So the
        # darwin side delegates GC to determinate-nixd (free-space driven, no
        # age knob) and the NixOS side keeps an explicit age bound. Deliberate:
        # nix-server has had no GC policy at all, and an age bound we can read
        # beats depending on determinate-nixd's undocumented default.
        #
        # 14d/weekly carries over the shortest policy any host had: nix-mac's
        # 14d, originally a response to a 78%-full data volume. It tightens
        # nix-pixelbook's previous 30d, and nix-server gains a policy where it
        # had none. Tighter is the safer default for a shared baseline -- a
        # host that wants to keep generations longer can say so, since every
        # value below is a mkDefault.
        gc = {
          automatic = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
          options = lib.mkDefault "--delete-older-than 14d";
        };

        optimise.automatic = lib.mkDefault true;
      };
    };
}
