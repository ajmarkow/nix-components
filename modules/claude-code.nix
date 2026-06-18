{ config
, pkgs
, pkgs-unstable
, lib
, paseoSkillsSource
, uv2nix
, pyprojectNix
, pyprojectBuildSystems
, claudeCodeNix
, ...
}:
let
  # CLAUDE.md configuration is split into its own module
  claudeCodeClaudeMd = import ./claude-code-claude-md.nix;
  summarize = import ../pkgs/summarize.nix { inherit pkgs; };
  semble = import ../pkgs/semble.nix {
    inherit pkgs uv2nix;
    pyproject-nix = pyprojectNix;
    pyproject-build-systems = pyprojectBuildSystems;
  };
  readSkills = dir: lib.mapAttrs'
    (name: _: lib.nameValuePair name (builtins.readFile (dir + "/${name}/SKILL.md")))
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));
  skillCommands =
    (readSkills ../skills) //
    (readSkills (paseoSkillsSource + "/skills"));
in
{
  home.packages = [
    pkgs-unstable.rtk
    pkgs.defuddle
    pkgs.nix-index
    pkgs.ripgrep
    pkgs.uv
    semble
    summarize
  ];

  home.file.".claude/statusline-command.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code status line script

      input=$(cat)

      model=$(echo "$input" | jq -r '(.model | if type == "object" then .display_name else . end) // "Unknown Model"')
      cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
      used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
      session_name=$(echo "$input" | jq -r '.session_name // empty')

      # Shorten home directory
      short_cwd="''${cwd/#$HOME/~}"

      # Git branch (skip lock to avoid blocking)
      git_branch=""
      if git_out=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
        git_branch=" $git_out"
      fi

      # ANSI colors
      RESET=$'\033[0m'
      BOLD=$'\033[1m'
      CYAN=$'\033[36m'
      GREEN=$'\033[32m'
      YELLOW=$'\033[33m'
      RED=$'\033[31m'
      DIM=$'\033[2m'

      # Context usage color
      ctx_color="$GREEN"
      if [ -n "$used_pct" ]; then
        used_int=''${used_pct%.*}
        if [ "$used_int" -ge 80 ]; then
          ctx_color="$RED"
        elif [ "$used_int" -ge 50 ]; then
          ctx_color="$YELLOW"
        fi
        ctx_display=" ''${ctx_color}ctx:''${used_int}%''${RESET}"
      else
        ctx_display=""
      fi

      # Session name display
      session_display=""
      if [ -n "$session_name" ]; then
        session_display=" ''${DIM}[''${session_name}]''${RESET}"
      fi

      # Account email — read live from ~/.claude.json
      account_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
      if [ -n "$account_email" ]; then
        account_prefix="''${DIM}Account: ''${account_email} |''${RESET} "
      else
        account_prefix=""
      fi

      printf "%s''${BOLD}''${CYAN}%s''${RESET}''${DIM}%s''${RESET} ''${GREEN}%s''${RESET}%s%s%s\n" \
        "$account_prefix" \
        "$short_cwd" \
        "$git_branch" \
        "$model" \
        "$ctx_display" \
        "$session_display"
    '';
  };

} // claudeCodeClaudeMd // {

  home.file.".claude/hooks/rtk-rewrite.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # rtk-hook-version: 3
      # RTK Claude Code hook — rewrites commands to use rtk for token savings.
      # Requires: rtk >= 0.23.0, jq
      #
      # This is a thin delegating hook: all rewrite logic lives in `rtk rewrite`,
      # which is the single source of truth (src/discover/registry.rs).
      # To add or change rewrite rules, edit the Rust registry — not this file.
      #
      # Exit code protocol for `rtk rewrite`:
      #   0 + stdout  Rewrite found, no deny/ask rule matched → auto-allow
      #   1           No RTK equivalent → pass through unchanged
      #   2           Deny rule matched → pass through (Claude Code native deny handles it)
      #   3 + stdout  Ask rule matched → rewrite but let Claude Code prompt the user

      if ! command -v jq &>/dev/null; then
        echo "[rtk] WARNING: jq is not installed. Hook cannot rewrite commands. Install jq: https://jqlang.github.io/jq/download/" >&2
        exit 0
      fi

      if ! command -v rtk &>/dev/null; then
        echo "[rtk] WARNING: rtk is not installed or not in PATH. Hook cannot rewrite commands. Install: https://github.com/rtk-ai/rtk#installation" >&2
        exit 0
      fi

      # Version guard: rtk rewrite was added in 0.23.0.
      # Older binaries: warn once and exit cleanly (no silent failure).
      RTK_VERSION=$(rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      if [ -n "$RTK_VERSION" ]; then
        MAJOR=$(echo "$RTK_VERSION" | cut -d. -f1)
        MINOR=$(echo "$RTK_VERSION" | cut -d. -f2)
        # Require >= 0.23.0
        if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -lt 23 ]; then
          echo "[rtk] WARNING: rtk $RTK_VERSION is too old (need >= 0.23.0). Upgrade: cargo install rtk" >&2
          exit 0
        fi
      fi

      INPUT=$(cat)
      CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

      if [ -z "$CMD" ]; then
        exit 0
      fi

      # Delegate all rewrite + permission logic to the Rust binary.
      REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null)
      EXIT_CODE=$?

      case $EXIT_CODE in
        0)
          # Rewrite found, no permission rules matched — safe to auto-allow.
          # If the output is identical, the command was already using RTK.
          [ "$CMD" = "$REWRITTEN" ] && exit 0
          ;;
        1)
          # No RTK equivalent — pass through unchanged.
          exit 0
          ;;
        2)
          # Deny rule matched — let Claude Code's native deny rule handle it.
          exit 0
          ;;
        3)
          # Ask rule matched — rewrite the command but do NOT auto-allow so that
          # Claude Code prompts the user for confirmation.
          ;;
        *)
          exit 0
          ;;
      esac

      ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
      UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')

      if [ "$EXIT_CODE" -eq 3 ]; then
        # Ask: rewrite the command, omit permissionDecision so Claude Code prompts.
        jq -n \
          --argjson updated "$UPDATED_INPUT" \
          '{
            "hookSpecificOutput": {
              "hookEventName": "PreToolUse",
              "updatedInput": $updated
            }
          }'
      else
        # Allow: rewrite the command and auto-allow.
        jq -n \
          --argjson updated "$UPDATED_INPUT" \
          '{
            "hookSpecificOutput": {
              "hookEventName": "PreToolUse",
              "permissionDecision": "allow",
              "permissionDecisionReason": "RTK auto-rewrite",
              "updatedInput": $updated
            }
          }'
      fi
    '';
  };

  programs.claude-code = {
    enable = true;
    package = claudeCodeNix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    enableMcpIntegration = true;
    commands = skillCommands;
    mcpServers = {
      nixos = {
        command = "uvx";
        args = [ "mcp-nixos" ];
      };
      context7 = {
        type = "http";
        url = "https://mcp.context7.com/mcp/oauth";
      };
      github = {
        type = "http";
        url = "https://api.githubcopilot.com/mcp/";
      };
      playwright = {
        command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
        args = [ "--headless" "--isolated" ];
      };
    };
    settings = {
      hooks = {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${config.home.homeDirectory}/.claude/hooks/rtk-rewrite.sh";
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
      enabledPlugins = {
        "ruby-lsp@claude-plugins-official" = true;
        "claude-md-management@claude-plugins-official" = true;
        "claude-code-setup@claude-plugins-official" = true;
        "superpowers@claude-plugins-official" = true;
        "obsidian@obsidian-skills" = true;
        "ralph-skills@ralph-marketplace" = true;
        "aws-common@aws-skills" = true;
        "serverless-eda@aws-skills" = true;
        "aws-agentic-ai@aws-skills" = true;
        "autonomous-agents@antigravity-awesome-skills" = true;
      };
      extraKnownMarketplaces = {
        "obsidian-skills" = {
          source = {
            source = "github";
            repo = "kepano/obsidian-skills";
          };
        };
        "ralph-marketplace" = {
          source = {
            source = "github";
            repo = "snarktank/ralph";
          };
        };
        "aws-skills" = {
          source = {
            source = "github";
            repo = "zxkane/aws-skills";
          };
        };
        "antigravity-awesome-skills" = {
          source = {
            source = "github";
            repo = "sickn33/antigravity-awesome-skills";
          };
        };
      };
    };
  };
}
