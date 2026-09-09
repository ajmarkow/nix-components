{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-components.mcp;
  mcpLib = import ./lib/mcp.nix {
    inherit lib pkgs;
    homeDirectory = config.home.homeDirectory;
  };

  # mcpm's global registry. Every catalog and extraServers entry carries the
  # fixed `all` tag; the mcpm service aggregates them behind one persistent
  # HTTP endpoint. Contains only placeholders and env-var names, never secret
  # values. Server mode only -- clients point at the central endpoint and
  # need no local registry.
  serversJson = (pkgs.formats.json { }).generate "mcpm-servers.json" (
    mcpLib.serverConfigs { inherit (cfg) extraServers; }
  );

  mcpmPort = 6276;

  # The single, fixed URL every agent points at, served centrally from
  # nix-server over the tailnet. It never changes, so each agent declares it
  # natively through its own module, no binary wrapper. Backed by the
  # always-on mcpm service on nix-server rather than a per-session stdio
  # spawn, so agents connect to warm servers instead of cold-starting all of
  # them (and racing the client's connect timeout) every session.
  #
  # Each agent's home-manager module has a different remote-MCP shape --
  # Claude Code uses `type = "http"`, opencode uses `type = "remote"`, Codex
  # infers HTTP transport from the presence of `url` alone -- so this is kept
  # per-agent rather than one shared record.
  claudeAggregator = {
    type = "http";
    url = cfg.endpoint;
  };
  codexAggregator = {
    url = cfg.endpoint;
  };
  opencodeAggregator = {
    type = "remote";
    url = cfg.endpoint;
    enabled = true;
  };

  claudeEnabled = config.programs.claude-code.enable or false;
  codexEnabled = config.programs.codex.enable or false;
  opencodeEnabled = config.programs.opencode.enable or false;

  serviceDescription = "mcpm MCP server aggregator";

  # A systemd user service never sources zsh init, so it starts with none of
  # the secrets mcpm needs to resolve each mounted server's ${VAR} references
  # (GITHUB_MCP_TOKEN, CONTEXT7_API_KEY, N8N_MCP_AUTH_TOKEN,
  # OPENROUTER_API_KEY, ...). Reuse the per-server *-mcp.env files nix-server's
  # deploy pipeline already writes to /etc/nixos/secrets/ (github-mcp.env,
  # context7-mcp.env, n8n-mcp.env, todoist-mcp.env, ...) for exactly this
  # purpose, plus opencode.env for the openrouter bearer key -- see
  # common.nix's own sourcing of these same files for the paseo daemon and
  # interactive shells.
  # Glob-based and best-effort so this stays a no-op on hosts/OSes that don't
  # provision that directory: mcpm just starts with whatever subset of
  # secrets it finds, same as if none were provisioned at all.
  #
  # mcpm silently falls back to another port when the requested one is taken
  # (find_available_port in its profile run command), which would leave the
  # tailscale serve registration pointing at a dead port. Refuse to start
  # instead so a conflict is loud in the journal, not a silent wrong-port
  # serve.
  serviceScript = pkgs.writeShellScript "mcpm-start" ''
    set -eu
    for _secret_env in /etc/nixos/secrets/*-mcp.env /etc/nixos/secrets/opencode.env; do
      if [ -r "$_secret_env" ]; then
        set -a
        . "$_secret_env"
        set +a
      fi
    done
    if (echo > /dev/tcp/127.0.0.1/${toString mcpmPort}) 2>/dev/null; then
      echo "mcpm: port ${toString mcpmPort} is already in use -- refusing to start (no automatic fallback)" >&2
      exit 1
    fi
    exec ${lib.getExe pkgs.mcpm} profile run --http all --port ${toString mcpmPort}
  '';
in
{
  options.nix-components.mcp = {
    enable = lib.mkEnableOption "shared MCP server configuration via mcpm";

    server = {
      enable = lib.mkEnableOption "run the central mcpm aggregate on this host";
    };

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://mcpm.tail772f0.ts.net/mcp";
      description = ''
        URL every enabled agent points at. Served centrally from nix-server
        over the tailnet; only server mode runs mcpm locally.
      '';
    };

    extraServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = ''
        Host-local servers merged into the catalog on the server host (e.g.
        nix-server's n8n server, which only makes sense where that container
        runs). Same shape as modules/lib/mcp.nix's catalog entries: either
        `command`/`args`/`env` (stdio) or `url`/`headerName`/`headerVar`
        (remote). Server names must not collide with a built-in one. Every
        entry joins the fixed `all` aggregate.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion =
              (lib.intersectLists (lib.attrNames mcpLib.catalog) (lib.attrNames cfg.extraServers)) == [ ];
            message = "nix-components.mcp.extraServers defines a server name that collides with a built-in server in modules/lib/mcp.nix";
          }
        ];

        # One native aggregator entry per enabled agent, all pointing at the
        # central tailnet endpoint -- no wrapper, no --mcp-config flag
        # injection.
        programs = {
          claude-code.mcpServers = lib.mkIf claudeEnabled { mcpm = claudeAggregator; };
          codex.settings.mcp_servers = lib.mkIf codexEnabled { mcpm = codexAggregator; };
          opencode.settings.mcp = lib.mkIf opencodeEnabled { mcpm = opencodeAggregator; };
        };
      }

      (lib.mkIf cfg.server.enable {
        home.file = {
          ".config/mcpm/servers.json" = {
            force = true;
            source = serversJson;
          };

          # ReadWritePaths (below) bind-mounts this into the sandboxed mcpm
          # unit, which requires the source to already exist on the real
          # filesystem -- unlike .config/mcpm above, nothing else creates these,
          # so the service fails at the NAMESPACE step with "No such file or
          # directory" without them. Linux-only consumer, but an empty dir is
          # harmless on Darwin too, so it's unconditional like the entry above.
          ".cache/mcpm/npm/.keep".text = "";
          ".cache/mcpm/uv/.keep".text = "";
          ".cache/mcpm/uv-tools/.keep".text = "";
        };

        # Runs mcpm's FastMCP proxy once, kept warm by systemd/launchd, bound
        # to loopback only -- the tailnet reaches it through `tailscale serve`,
        # never directly. Sandboxed to this user's own state; no container,
        # since every backend here is a trusted first- or second-party server
        # sharing this host's Infisical-injected secrets anyway.
        systemd.user.services = lib.mkIf pkgs.stdenv.isLinux {
          mcpm = {
            Unit = {
              Description = serviceDescription;
              After = [ "network.target" ];
              # mcpm reads servers.json once at startup, so a catalog change alone
              # left this long-lived process serving the previous generation's
              # config -- the new servers.json sat on disk, ignored, until
              # something else restarted the unit. Nothing else here references
              # that file (it arrives via home.file), so the unit was byte-identical
              # across the deploy and home-manager had no reason to restart it.
              # Naming the store path makes the unit change whenever the catalog
              # does.
              X-Restart-Triggers = [ "${serversJson}" ];
            };
            Service = {
              ExecStart = "${serviceScript}";
              Restart = "on-failure";
              RestartSec = 2;
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = "read-only";
              ReadWritePaths = [
                "%h/.config/mcpm"
                # Bind-mount target for each catalog server's npx/uvx package
                # cache (modules/lib/mcp.nix's cacheEnv, passed directly in
                # servers.json -- systemd's own Environment= here never reaches
                # those subprocesses, see that file's comment). Previously those
                # caches pointed at PrivateTmp's private /tmp, which is torn down
                # and recreated on every service restart/redeploy, forcing every
                # server to re-fetch its packages from scratch each time --
                # several minutes of cold start before tools/list even returned.
                "%h/.cache/mcpm"
                # obsidian-mcp reads/writes the vault
                # directly at this fixed path (see the catalog entry below and
                # nix-server's modules/obsidian.nix, which provisions and syncs
                # it) -- outside %h, so ProtectSystem=strict leaves it read-only
                # without this, and obsidian-mcp fails every call with
                # VAULT_PERMISSION_DENIED.
                "/var/lib/obsidian-sync/vault"
              ];
              PrivateTmp = true;
            };
            Install.WantedBy = [ "default.target" ];
          };
        };

        launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
          mcpm = {
            enable = true;
            config = {
              ProgramArguments = [ "${serviceScript}" ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "${config.home.homeDirectory}/.local/state/mcpm.log";
              StandardErrorPath = "${config.home.homeDirectory}/.local/state/mcpm.log";
            };
          };
        };
      })
    ]
  );
}
