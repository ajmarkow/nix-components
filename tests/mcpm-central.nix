# Module evaluation checks for the central mcpm service.
#
# Called from perSystem's checks with real `lib` and `pkgs`. Everything here
# is pure evaluation -- no builds, no sandbox -- so `nix flake check
# --no-build` executes every assertion.
{ lib, pkgs }:
let
  homeDirectory = "/home/test";

  # Plain nixpkgs has no mcpm package -- the real one arrives via this
  # flake's overlay (pkgs/mcpm.nix). Stub just enough for lib.getExe.
  testPkgs = pkgs.extend (
    _: _: {
      mcpm = pkgs.runCommand "mcpm" { } ''
        mkdir -p $out/bin
        touch $out/bin/mcpm
        chmod +x $out/bin/mcpm
      '';
    }
  );

  mcpLib = import ../modules/lib/mcp.nix {
    inherit lib homeDirectory;
    pkgs = testPkgs;
  };

  rendered = mcpLib.serverConfigs { };

  stubModule = {
    options = {
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
      };
      home = {
        homeDirectory = lib.mkOption { type = lib.types.str; };
        file = lib.mkOption { type = lib.types.attrsOf lib.types.anything; };
        packages = lib.mkOption { type = lib.types.listOf lib.types.anything; };
      };
      programs = {
        claude-code = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          mcpServers = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
        codex = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          settings = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
        opencode = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          settings = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
      };
      systemd.user.services = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      launchd.agents = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
    };
  };

  evalMcp =
    extraConfig:
    lib.evalModules {
      modules = [
        { _module.args.pkgs = testPkgs; }
        (import ../modules/mcp.nix)
        stubModule
        {
          home.homeDirectory = homeDirectory;
          nix-components.mcp.enable = true;
          programs = {
            claude-code.enable = true;
            codex.enable = true;
            opencode.enable = true;
          };
        }
        extraConfig
      ];
    };

  client = (evalMcp { }).config;
  server = (evalMcp { nix-components.mcp.server.enable = true; }).config;

  endpoint = "https://mcpm.tail772f0.ts.net/mcp";

  catalogNames = lib.attrNames mcpLib.catalog;

  # ExecStart points at a store script, so the flags live in module source,
  # not in the evaluated string. Read the source directly -- pure eval.
  mcpSource = builtins.readFile ../modules/mcp.nix;

  checks = [
    {
      name = "client agents point at the central URL";
      ok =
        client.programs.claude-code.mcpServers.mcpm.url == endpoint
        && client.programs.codex.settings.mcp_servers.mcpm.url == endpoint
        && client.programs.opencode.settings.mcp.mcpm.url == endpoint;
    }
    {
      name = "client mode creates no local services or registry";
      ok =
        !(client.home.file ? ".config/mcpm/servers.json")
        && client.systemd.user.services == { }
        && client.launchd.agents == { };
    }
    {
      name = "server mode renders every catalog server in all";
      ok = lib.all (n: rendered.${n}.profile_tags == [ "all" ]) catalogNames;
    }
    {
      name = "n8n is present in the fixed aggregate";
      ok = rendered ? n8n && rendered.n8n.profile_tags == [ "all" ];
    }
    {
      name = "server mode runs the mcpm service from profile run --http all";
      ok = server.systemd.user.services ? mcpm && lib.hasInfix "profile run --http all" mcpSource;
    }
    {
      name = "removed enabledProfiles option is absent";
      ok = !(lib.hasAttr "enabledProfiles" (evalMcp { }).options.nix-components.mcp);
    }
    {
      name = "removed mcp-profile package is absent";
      ok = !(builtins.readDir ../pkgs ? "mcp-profile.nix");
    }
  ];

  failed = lib.filter (c: !c.ok) checks;
in
{
  inherit checks;
  ok = failed == [ ];
  message = lib.concatMapStringsSep "\n" (c: "mcpm-central check FAILED: ${c.name}") failed;
}
