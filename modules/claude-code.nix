{ config
, pkgs
, pkgs-unstable
, inputs
, ...
}:
{
  home.packages = [
    pkgs-unstable.rtk
    pkgs.uv
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

  home.file.".claude/CLAUDE.md".text = ''
    # Bash Tool Guidelines — MANDATORY

    ## ⚠️ CRITICAL: Every Bash command MUST start with `rtk`

    **No exceptions.** Prefix every single Bash tool call with `rtk`. This applies to ALL commands: git, cp, mkdir, ls, grep, cat, find, npm, nix, gh, paseo — everything. Unsupported commands pass through unchanged, so there is zero downside and no reason to ever omit it.

    ```bash
    # CORRECT — always do this:
    rtk git status
    rtk git push origin main
    rtk cp file.txt dest/
    rtk mkdir -p .github/workflows
    rtk ls ~/projects
    rtk paseo ls

    # WRONG — never do this:
    git status
    cp file.txt dest/
    mkdir -p .github/workflows
    ```

    ## Inter-Agent Messaging

    When the user asks you to message, notify, or send something to another agent or repo, **use `paseo`** — not files, git, or any other mechanism.

    Find the target agent, then send:
    ```bash
    paseo ls -a -g                         # list all agents across all directories
    paseo send <id> "message or task"      # id can be shortened if unambiguous
    ```

    If no agent is running for the target, start one:
    ```bash
    paseo run "task" --detach --name <name>
    ```

    Prefer `paseo send` to an existing agent over starting a duplicate. Other commands:
    ```bash
    paseo attach <id>   # stream output live
    paseo wait <id>     # block until agent finishes
    paseo stop <id>     # terminate
    ```
  '';

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
    package = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    enableMcpIntegration = true;
    commands.c-and-p = ''
      Commit all staged and unstaged changes using a conventional commit message, then push.

      Steps:
      1. Run `git status` and `git diff` to understand what changed.
      2. Stage all relevant changes (prefer specific files over `git add -A`).
      3. Write a conventional commit message: `<type>(<scope>): <short summary>`
         - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
         - Scope is optional but encouraged
         - Summary should be lowercase, imperative, no period
      4. Commit the changes.
      5. Push to the current remote tracking branch (or `origin <current-branch>` if unset).
    '';
    commands.add-mcp = ''
      Add a new MCP server to the nix-components claude-code.nix module.

      Steps:
      1. Ask the user: "What should this MCP server be called?" (e.g. "context7", "paseo")
      2. Ask the user: "What is the documentation URL for this MCP server?"
      3. Fetch the docs URL. Find the exact connection config for Claude Code or a generic HTTP/stdio entry.
         Determine the correct Nix format:
         - stdio:       `{ command = "..."; args = [ "..." ]; }`
         - HTTP+apikey: `{ type = "http"; url = "https://..."; }` with a `headers` attrset if needed — use `requireEnv "VAR_NAME"` for secrets (see mcp.nix for the pattern)
         - HTTP+OAuth:  `{ type = "http"; url = "https://.../oauth"; }` (no headers needed)
      4. Open ~/paseo-projects/nix-components/modules/claude-code.nix and add the entry inside `programs.claude-code.mcpServers = { ... };`
      5. Also update ~/paseo-projects/nix-components/adding-mcp.md if anything about the process is new or worth noting.
      6. Commit the change with a short message and push.
      7. Tell the user what was added and remind them to run nixos-rebuild / home-manager switch for it to take effect.
    '';
    mcpServers = {
      paseo = {
        command = "paseo";
        args = [ "mcp" ];
      };
      nixos = {
        command = "uvx";
        args = [ "mcp-nixos" ];
      };
      context7 = {
        type = "http";
        url = "https://mcp.context7.com/mcp/oauth";
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
      };
    };
  };
}
