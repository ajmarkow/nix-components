{
  config,
  lib,
  pkgs,
  claudeCodeNix,
  codexPluginCcSource,
  ...
}:
{
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
        CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
        # core.pager=delta (modules/git.nix) is global for the interactive
        # terminal experience. The Bash tool presents a TTY to child
        # processes, so without this override `git diff`/`log`/`show` launch
        # delta's interactive pager, which blocks forever waiting for
        # keypress input no agent can send. GIT_PAGER wins over core.pager,
        # so this disables paging for agent sessions only.
        GIT_PAGER = "cat";
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
              # Atuin shell-history capture (docs.atuin.sh/latest/guide/agent-hooks).
              # `atuin hook claude-code` is the runtime handler `atuin hook
              # install claude-code` would otherwise wire up for you — written
              # by hand here because the installer targets this very
              # settings.json, which home-manager generates (see hooks.nix's
              # own header comment on why imperative installers can't touch
              # generated files).
              #
              # Deliberate semantic choice: Claude Code runs every matching
              # PreToolUse hook in parallel against the SAME original
              # tool_input (see rtk-rewrite.sh's comment below), so this hook
              # sees the command the agent asked for, not rtk-rewrite.sh's
              # rewritten/secretty-wrapped version that actually executes.
              # That means atuin's history will show the agent's intent
              # rather than the literal process — e.g. `rg foo` rather than
              # the `rtk semble search`-equivalent substitution, or the
              # unwrapped command rather than its secretty-wrapped form. This
              # is the more useful record for later searching/auditing
              # agent behavior, so it's kept rather than chained after
              # rtk-rewrite.sh (which would require serializing the two hooks
              # and racing their updatedInput, per that file's own note).
              {
                type = "command";
                command = "${lib.getExe config.programs.atuin.package} hook claude-code";
              }
            ];
          }
          # Write|Edit memory guard (script lives in ./memory-guard.nix next
          # to hooks.nix; entry here so all PreToolUse matchers stay in one
          # list literal). Denies global CLAUDE.md (~/.claude/CLAUDE.md) and
          # auto-memory writes without explicit user `remember` approval —
          # see memory-guard.nix for scope and per-agent wiring gaps.
          {
            matcher = "Write|Edit";
            hooks = [
              {
                type = "command";
                command = "${config.home.homeDirectory}/.claude/hooks/memory-guard.sh";
              }
            ];
          }
        ];
        # PostToolUse/PostToolUseFailure both map to atuin's `history end`
        # (exit code + duration); PreToolUse above is `history start`. Same
        # binary invocation for all three — atuin tells them apart from the
        # hook_event_name field in the JSON it reads off stdin.
        PostToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${lib.getExe config.programs.atuin.package} hook claude-code";
              }
            ];
          }
        ];
        PostToolUseFailure = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${lib.getExe config.programs.atuin.package} hook claude-code";
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
