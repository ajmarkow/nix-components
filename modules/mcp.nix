{ config, lib, pkgs, claudeCodeNix, codexCliNix, ... }:
let
  cfg = config.nix-components.mcp;
  mcpLib = import ./lib/mcp.nix { inherit lib pkgs; };
  system = pkgs.stdenv.hostPlatform.system;

  # extraProfiles lets a consuming host (e.g. nix-server's n8n server, which only
  # makes sense on that one host) merge in host-local profiles alongside the
  # built-in ones, without putting host-specific config in this shared repo.
  allProfiles = mcpLib.profiles // cfg.extraProfiles;
  profileNames = builtins.attrNames allProfiles;

  # Every profile's server names must be disjoint from every other profile's --
  # codex's active file is built by naive concatenation (renderCodexActive
  # below), and any two profiles sharing a server name would silently produce a
  # duplicate TOML table. Enforced as a real assertion (below), not just a
  # comment, so a collision fails eval loudly instead of producing broken TOML.
  allServerNames = lib.concatMap (p: builtins.attrNames p.servers) (lib.attrValues allProfiles);

  fragmentDir = "${config.home.homeDirectory}/.local/share/nix-components/mcp-profiles";

  # One store artifact per agent per profile. These never contain resolved
  # secret values, only placeholders or environment variable names.
  perProfileArtifacts = lib.mapAttrs (name: profile: {
    claudeJson =
      (pkgs.formats.json { }).generate "claude-mcp-${name}.json" (mcpLib.toClaudeCodeFragment profile);
    opencodeJson =
      (pkgs.formats.json { }).generate "opencode-mcp-${name}.json" (mcpLib.toOpencodeFragment profile);
    codexToml = pkgs.writeText "codex-mcp-${name}.toml" (mcpLib.toCodexFragment profile);
  }) allProfiles;

  fragmentFiles = lib.concatMapAttrs (name: artifacts: {
    ".local/share/nix-components/mcp-profiles/claude-code/${name}.json".source = artifacts.claudeJson;
    ".local/share/nix-components/mcp-profiles/opencode/${name}.json".source = artifacts.opencodeJson;
    ".local/share/nix-components/mcp-profiles/codex/${name}.toml".source = artifacts.codexToml;
  }) perProfileArtifacts;

  # Shared "merge these profile names into one agent-active file" logic --
  # pkgs/mcp-profile.nix (the runtime swap script) re-implements the same
  # algorithm in shell against the same fragment files, so a deploy-time default
  # and a runtime swap always produce byte-identical output for the same input.
  renderClaudeActive = names: pkgs.runCommand "claude-mcp-active.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -s '{mcpServers: (map(.mcpServers) | add)}' \
      ${lib.concatMapStringsSep " " (n: "${perProfileArtifacts.${n}.claudeJson}") names} > $out
  '';
  renderOpencodeActive = names: pkgs.runCommand "opencode-mcp-active.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -s '{mcp: (map(.mcp) | add)}' \
      ${lib.concatMapStringsSep " " (n: "${perProfileArtifacts.${n}.opencodeJson}") names} > $out
  '';
  renderCodexActive = names: lib.concatMapStringsSep "\n" (n: mcpLib.toCodexFragment allProfiles.${n}) names;
in
{
  options.nix-components.mcp = {
    enable = lib.mkEnableOption "shared, swappable MCP server configuration";

    enabledProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # = current per-agent behavior before this module existed; also what every
      # deploy resets a runtime `mcp-profile` swap back to.
      default = [ "core" "github" "context7" ];
      description = ''
        Default MCP server profiles activated on deploy. Names must exist in
        modules/lib/mcp.nix's `profiles` or in `extraProfiles`. Override at
        runtime with `mcp-profile <names...>` -- no rebuild needed, see
        pkgs/mcp-profile.nix -- but every deploy resets back to this default.
      '';
    };

    extraProfiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.servers = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
            default = { };
            description = "Server definitions for this profile, same shape as modules/lib/mcp.nix's profiles.<name>.servers.";
          };
        }
      );
      default = { };
      description = ''
        Host-local profiles merged alongside the built-in ones (e.g. nix-server's
        n8n server, which only makes sense on that specific host and talks to a
        container running there). Server names must not collide with any
        built-in or other extra profile's servers.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.length allServerNames == lib.length (lib.unique allServerNames);
        message = "nix-components.mcp: two profiles define the same server name -- see modules/lib/mcp.nix and nix-components.mcp.extraProfiles";
      }
      {
        assertion = builtins.all (n: builtins.elem n profileNames) cfg.enabledProfiles;
        message = "nix-components.mcp.enabledProfiles references a profile name that doesn't exist in modules/lib/mcp.nix's profiles or nix-components.mcp.extraProfiles";
      }
      {
        assertion = lib.length cfg.enabledProfiles == lib.length (lib.unique cfg.enabledProfiles);
        message = "nix-components.mcp.enabledProfiles contains duplicate profile names";
      }
      {
        assertion =
          lib.length (lib.attrNames mcpLib.profiles) + lib.length (lib.attrNames cfg.extraProfiles)
          == lib.length (lib.attrNames allProfiles);
        message = "nix-components.mcp.extraProfiles defines a profile name that collides with a built-in profile in modules/lib/mcp.nix";
      }
    ];

    programs.claude-code.package =
      lib.mkIf (config.programs.claude-code.enable or false) (lib.mkForce null);
    programs.codex.package = lib.mkIf (config.programs.codex.enable or false) (lib.mkForce null);

    home.file = fragmentFiles // {
      # "Active" files -- dedicated, agent-read-only, never written by the agent
      # itself. .force is required so a deploy can always reclaim them after
      # `mcp-profile` has overwritten them locally (same reason nix-server's
      # existing ~/.claude/settings.json needs .force).
      ".config/mcp-profiles/claude-active.json" = {
        force = true;
        source = renderClaudeActive cfg.enabledProfiles;
      };
      ".config/mcp-profiles/opencode-active.json" = {
        force = true;
        source = renderOpencodeActive cfg.enabledProfiles;
      };
      ".codex/active.config.toml" = {
        force = true;
        text = renderCodexActive cfg.enabledProfiles;
      };
    };

    # opencode reads this natively at every invocation, merged additively at a
    # fixed precedence layer -- never written back to by opencode itself.
    home.sessionVariables.OPENCODE_CONFIG = "${config.home.homeDirectory}/.config/mcp-profiles/opencode-active.json";

    home.packages =
      [ (pkgs.callPackage ../pkgs/mcp-profile.nix { inherit profileNames fragmentDir; }) ]
      # Only install each wrapper when that agent is actually enabled in this
      # home config -- e.g. nix-server's root user imports claude-code but not
      # codex, so a `codex` wrapper there would be pointless.
      #
      # Wrap the RAW claude-code-nix/codex-cli-nix package directly, not
      # config.programs.{claude-code,codex}.finalPackage. The package options
      # are forced to null above so upstream home-manager's own
      # `home.packages = lib.mkIf (cfg.package != null) [ cfg.finalPackage ];`
      # (modules/programs/claude-code.nix in home-manager) does NOT also try
      # to install the raw binary -- that would collide with the wrapper
      # below, since both provide bin/claude. finalPackage is therefore
      # null/unusable here by design.
      ++ lib.optional (config.programs.claude-code.enable or false) (
        pkgs.callPackage ../pkgs/claude-mcp-wrapper.nix {
          claudeCodePackage = claudeCodeNix.packages.${system}.default;
        }
      )
      ++ lib.optional (config.programs.codex.enable or false) (
        pkgs.callPackage ../pkgs/codex-mcp-wrapper.nix {
          codexPackage = codexCliNix.packages.${system}.default;
        }
      );
  };
}
