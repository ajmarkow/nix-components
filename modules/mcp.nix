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
  # `active` tag; `mcpm profile run active` aggregates them behind one stdio
  # endpoint. Contains only placeholders and env-var names, never secret
  # values.
  serversJson = (pkgs.formats.json { }).generate "mcpm-servers.json" (
    mcpLib.serverConfigs {
      activeProfiles = cfg.enabledProfiles;
      inherit (cfg) extraServers;
    }
  );

  # The single, fixed MCP entry every agent points at. It never changes --
  # runtime profile swaps rewrite servers.json, not this -- so each agent
  # declares it natively through its own module, no binary wrapper.
  aggregator = {
    command = "mcpm";
    args = [
      "profile"
      "run"
      "active"
    ];
  };

  claudeEnabled = config.programs.claude-code.enable or false;
  codexEnabled = config.programs.codex.enable or false;
  opencodeEnabled = config.programs.opencode.enable or false;
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

    # One native aggregator entry per enabled agent. Each agent's own module
    # writes it to that agent's native config -- no wrapper, no --mcp-config /
    # --profile flag injection.
    programs.claude-code.mcpServers = lib.mkIf claudeEnabled { mcpm = aggregator; };
    programs.codex.settings.mcp_servers = lib.mkIf codexEnabled { mcpm = aggregator; };
    programs.opencode.settings.mcp = lib.mkIf opencodeEnabled {
      mcpm = {
        type = "local";
        command = [ aggregator.command ] ++ aggregator.args;
        enabled = true;
      };
    };

    home.packages = [
      (pkgs.callPackage ../pkgs/mcp-profile.nix { profileNames = allProfileNames; })
    ];
  };
}
