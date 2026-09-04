{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-components.mcp;
  mcpLib = import ./lib/mcp.nix { inherit lib pkgs; };

  allProfileNames = mcpLib.profileNames cfg.extraServers;

  # mcpm's global registry. Every server in an enabled profile carries the
  # `active` tag; the mcpm-active-profile service aggregates them behind one
  # persistent HTTP endpoint. Contains only placeholders and env-var names,
  # never secret values.
  serversJson = (pkgs.formats.json { }).generate "mcpm-servers.json" (
    mcpLib.serverConfigs {
      activeProfiles = cfg.enabledProfiles;
      inherit (cfg) extraServers;
    }
  );

  mcpmPort = 6276;
  mcpmUrl = "http://127.0.0.1:${toString mcpmPort}/mcp";

  # The single, fixed URL every agent points at. It never changes -- runtime
  # profile swaps rewrite servers.json, not this -- so each agent declares it
  # natively through its own module, no binary wrapper. Backed by the
  # always-on mcpm-active-profile service below rather than a per-session
  # stdio spawn, so agents connect to warm servers instead of cold-starting
  # all of them (and racing the client's connect timeout) every session.
  #
  # Each agent's home-manager module has a different remote-MCP shape --
  # Claude Code uses `type = "http"`, opencode uses `type = "remote"`, Codex
  # infers HTTP transport from the presence of `url` alone -- so this is kept
  # per-agent rather than one shared record.
  claudeAggregator = {
    type = "http";
    url = mcpmUrl;
  };
  codexAggregator = {
    url = mcpmUrl;
  };
  opencodeAggregator = {
    type = "remote";
    url = mcpmUrl;
    enabled = true;
  };

  claudeEnabled = config.programs.claude-code.enable or false;
  codexEnabled = config.programs.codex.enable or false;
  opencodeEnabled = config.programs.opencode.enable or false;

  serviceDescription = "mcpm active-profile MCP server aggregator";

  # A systemd user service never sources zsh init, so it starts with none of
  # the secrets mcpm needs to resolve each mounted server's ${VAR} references
  # (GITHUB_MCP_TOKEN, CONTEXT7_API_KEY, N8N_MCP_AUTH_TOKEN, ...). Reuse the
  # per-server *-mcp.env files nix-server's deploy pipeline already writes to
  # /etc/nixos/secrets/ (github-mcp.env, context7-mcp.env, n8n-mcp.env,
  # todoist-mcp.env, ...) for exactly this purpose -- see common.nix's own
  # sourcing of these same files for the paseo daemon and interactive shells.
  # Glob-based and best-effort so this stays a no-op on hosts/OSes that don't
  # provision that directory (e.g. nix-mac): mcpm just starts with whatever
  # subset of secrets it finds, same as if none were provisioned at all.
  serviceScript = pkgs.writeShellScript "mcpm-active-profile-start" ''
    set -eu
    for _secret_env in /etc/nixos/secrets/*-mcp.env; do
      if [ -r "$_secret_env" ]; then
        set -a
        . "$_secret_env"
        set +a
      fi
    done
    exec ${lib.getExe pkgs.mcpm} profile run --http active --port ${toString mcpmPort}
  '';
in
{
  options.nix-components.mcp = {
    enable = lib.mkEnableOption "shared MCP server configuration via mcpm";

    enabledProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "core" ];
      description = ''
        MCP profiles whose servers are active on deploy -- their servers get the
        `active` tag in mcpm's servers.json. Names must exist in
        modules/lib/mcp.nix's catalog or in `extraServers`. Override at runtime
        with `mcp-profile <names...>` (no rebuild, see pkgs/mcp-profile.nix);
        every deploy resets back to this default. `core` holds the always-used
        dev tools (nixos, playwright, context7, github); `productivity`
        (todoist, obsidian) and `extras` (openrouter) are off by default.
      '';
    };

    extraServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = ''
        Host-local servers merged into the catalog (e.g. nix-server's n8n
        server, which only makes sense on that host). Same shape as
        modules/lib/mcp.nix's catalog entries: a `profiles` list plus either
        `command`/`args`/`env` (stdio) or `url`/`headerName`/`headerVar`
        (remote). Server names must not collide with a built-in one.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.all (n: builtins.elem n allProfileNames) cfg.enabledProfiles;
        message = "nix-components.mcp.enabledProfiles references a profile with no servers in modules/lib/mcp.nix's catalog or nix-components.mcp.extraServers";
      }
      {
        assertion = lib.length cfg.enabledProfiles == lib.length (lib.unique cfg.enabledProfiles);
        message = "nix-components.mcp.enabledProfiles contains duplicate profile names";
      }
      {
        assertion =
          (lib.intersectLists (lib.attrNames mcpLib.catalog) (lib.attrNames cfg.extraServers)) == [ ];
        message = "nix-components.mcp.extraServers defines a server name that collides with a built-in server in modules/lib/mcp.nix";
      }
    ];

    # servers.json is a store symlink on deploy (the default `active` set) and
    # is replaced in place by `mcp-profile` at runtime; `force` lets each deploy
    # reclaim it.
    home.file.".config/mcpm/servers.json" = {
      force = true;
      source = serversJson;
    };

    # One native aggregator entry per enabled agent, all pointing at the same
    # persistent HTTP endpoint -- no wrapper, no --mcp-config / --profile flag
    # injection.
    programs.claude-code.mcpServers = lib.mkIf claudeEnabled { mcpm = claudeAggregator; };
    programs.codex.settings.mcp_servers = lib.mkIf codexEnabled { mcpm = codexAggregator; };
    programs.opencode.settings.mcp = lib.mkIf opencodeEnabled { mcpm = opencodeAggregator; };

    # Runs mcpm's FastMCP proxy once, kept warm by systemd/launchd, instead of
    # every agent session cold-starting all of an enabled profile's servers
    # over stdio -- that cold start (context7 + github + nixos + obsidian +
    # playwright + todoist, sequentially) routinely outran Claude Code's MCP
    # connect timeout. Sandboxed to this user's own state; no container, since
    # every backend here is a trusted first- or second-party server sharing
    # this host's Infisical-injected secrets anyway.
    systemd.user.services = lib.mkIf pkgs.stdenv.isLinux {
      mcpm-active-profile = {
        Unit = {
          Description = serviceDescription;
          After = [ "network.target" ];
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
            # obsidian-mcp (productivity profile) reads/writes the vault
            # directly at this fixed path (see the catalog entry below and
            # nix-server's modules/obsidian.nix, which provisions and syncs
            # it) -- outside %h, so ProtectSystem=strict leaves it read-only
            # without this, and obsidian-mcp fails every call with
            # VAULT_PERMISSION_DENIED. "-" prefix: optional, so hosts that
            # don't provision this directory (no obsidian.nix imported) don't
            # fail to start.
            "-/var/lib/obsidian-sync/vault"
          ];
          PrivateTmp = true;
          # npx (context7/github/n8n) and uvx (nixos) write their package
          # caches to ~/.npm and ~/.cache/uv by default -- both under the
          # read-only home above, which fails with EROFS under ProtectHome.
          # Redirect them into this unit's own private, writable /tmp instead
          # of widening ReadWritePaths.
          Environment = [
            "NPM_CONFIG_CACHE=/tmp/mcpm-npm-cache"
            "UV_CACHE_DIR=/tmp/mcpm-uv-cache"
          ];
        };
        Install.WantedBy = [ "default.target" ];
      };
    };

    launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
      mcpm-active-profile = {
        enable = true;
        config = {
          ProgramArguments = [ "${serviceScript}" ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${config.home.homeDirectory}/.local/state/mcpm-active-profile.log";
          StandardErrorPath = "${config.home.homeDirectory}/.local/state/mcpm-active-profile.log";
        };
      };
    };

    home.packages = [
      (pkgs.callPackage ../pkgs/mcp-profile.nix { profileNames = allProfileNames; })
    ];
  };
}
