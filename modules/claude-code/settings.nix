{
  config,
  lib,
  pkgs,
  claudeCodeNix,
  codexCliNix,
  codexPluginCcSource,
  ...
}:
{
  # codex-plugin-cc's hooks/commands shell out to the `codex` CLI, so it must
  # be on PATH regardless of whether ./codex.nix is also imported.
  #
  # Only add the raw package when nothing else already provides bin/codex,
  # otherwise buildEnv fails with "two given paths contain a conflicting
  # subpath: .../codex-<ver>/bin/codex and .../codex/bin/codex". When
  # ./codex.nix is imported it sets programs.codex.enable = true, and upstream
  # home-manager (via programs.codex.package) installs codex already. The two
  # conditions are exact complements, so codex is always on PATH exactly once.
  home.packages = lib.optional (
    !(config.programs.codex.enable or false)
  ) codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  programs.claude-code = {
    enable = true;
    package = claudeCodeNix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    # Lets Claude Code delegate tasks to / request review from the codex CLI.
    # Claude-only: opencode.nix and codex.nix don't understand the
    # .claude-plugin format, so this isn't fed through skills.nix.
    plugins = [ "${codexPluginCcSource}/plugins/codex" ];
    settings = {
      env = {
        CLAUDE_CODE_DISABLE_ARTIFACT = "1";
        CLAUDE_CODE_DISABLE_WORKFLOWS = "1";
        DISABLE_ERROR_REPORTING = "1";
        DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
        DISABLE_AUTOUPDATER = "1";
        DISABLE_UPDATES = "1";
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      };
      permissions = {
        allow = [
          "Bash(nix flake check *)"
          "Bash(gh run watch *)"
          "Bash(doggo *)"
          "Bash(npm view *)"
          "Bash(defuddle parse *)"
          "Bash(npm config get *)"
          "Bash(npm config list*)"
          "Bash(aws iam list-*)"
          "Bash(aws iam get-*)"
          "Bash(aws route53 list-*)"
          "Bash(dmidecode *)"
          "Bash(sudo dmidecode *)"
          "Bash(paseo ls*)"
          "Bash(npm test)"
          "Bash(npm run lint)"
          "Bash(backlog task list*)"
          # All MCP servers are aggregated behind one mcpm endpoint (server key
          # `mcpm`, injected via the home-manager plugin). mcpm's FastMCP proxy
          # prefixes each underlying server: tool `nix` on the `nixos` server is
          # exposed as `nixos_nix`, etc.
          "mcp__plugin_claude-code-home-manager_mcpm__context7_query-docs"
          "mcp__plugin_claude-code-home-manager_mcpm__context7_resolve-library-id"
          "mcp__plugin_claude-code-home-manager_mcpm__playwright_browser_take_screenshot"
          "mcp__plugin_claude-code-home-manager_mcpm__playwright_browser_navigate"
          "mcp__plugin_claude-code-home-manager_mcpm__nixos_nix"
          "mcp__paseo__list_pending_permissions"
        ];
      };
      hooks = {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${config.home.homeDirectory}/.claude/hooks/rtk-rewrite.sh";
              }
              {
                type = "command";
                command = "${config.home.homeDirectory}/.claude/hooks/block-ssh-rg-cd.sh";
              }
            ];
          }
        ];
      };
      statusLine = {
        type = "command";
        command = "${config.home.homeDirectory}/.claude/statusline-command.sh";
        padding = 0;
      };
    };
  };
}
