{ config
, lib
, pkgs
, claudeCodeNix
, codexCliNix
, codexPluginCcSource
, paseoSkillsSource
, superpowersSkillsSource
, obsidianSkillsSource
, awsSkillsSource
, ...
}:
let
  # readSkills is shared with opencode.nix (./lib/skills.nix) so both agents
  # expose the same set of skills as slash commands. Merge precedence (later
  # wins on name collision): paseo-skills -> superpowers -> obsidian ->
  # aws-skills -> local ../skills. Local always wins, so any skill this repo
  # already ships (e.g. test-driven-development) keeps its local version even
  # though upstream sources also define a skill with the same name.
  inherit (import ./lib/skills.nix { inherit lib; }) readSkills;
  skillCommands =
    (readSkills (paseoSkillsSource + "/skills")) //
    (readSkills (superpowersSkillsSource + "/skills")) //
    (readSkills (obsidianSkillsSource + "/skills")) //
    (readSkills awsSkillsSource) //
    (readSkills ../skills);
in
# One attrset, deliberately. This module used to be three attrsets joined with `//`,
# which is a shallow update: each block's `home` replaced the previous one, so all but
# the last block's home.file and home.packages were silently discarded. Keep everything
# in a single attrset so that cannot happen again.
#
# CLAUDE.md is NOT defined here. It lives in ./claude-code-claude-md.nix, which is
# exported as its own home module and imported separately by consumers. Merging it in
# would define home.file.".claude/CLAUDE.md" twice and fail the switch. The prose itself
# lives in ./lib/claude-md-content.nix (shared with opencode.nix's AGENTS.md) — edit
# that file, not this one or claude-code-claude-md.nix.
#
# The statusline and hooks below need `jq`, `gh`, and `git` on PATH. Those come from
# ./packages.nix, which owns tool packages for all hosts.
{
  # codex-plugin-cc's hooks/commands shell out to the `codex` CLI, so it must
  # be on PATH regardless of whether ./codex.nix is also imported.
  home.packages = [ codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default ];

  home.file.".claude/statusline-command.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code status line script
      #
      # Two rows:
      #   1. where you are   — directory, branch, session name, account
      #   2. how it is going — model, context meter, CI, rate limits

      input=$(cat)

      # One jq pass for every field, to keep the render cheap.
      # Unit separator, not tab: tab is IFS whitespace, so bash would collapse
      # consecutive empty fields and shift every value left.
      IFS=$'\x1f' read -r model cwd used_pct session_name limit_5h limit_7d <<<"$(
        printf '%s' "$input" | jq -r '[
          (.model | if type == "object" then .display_name else . end) // "Unknown Model",
          (.workspace.current_dir // .cwd // ""),
          (.context_window.used_percentage // ""),
          (.session_name // ""),
          (.rate_limits.five_hour.used_percentage // ""),
          (.rate_limits.seven_day.used_percentage // "")
        ] | map(tostring) | join("\u001f")'
      )"

      # Git branch (skip lock to avoid blocking)
      git_branch=""
      if git_out=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
        git_branch="$git_out"
      fi

      # GitHub CI status for the current branch.
      # Cached with a 60s TTL; refresh runs detached so the status line never blocks on gh.
      ci_state=""
      if [ -n "$git_branch" ]; then
        cache_key=$(printf '%s@%s' "$cwd" "$git_branch" | cksum | cut -d' ' -f1)
        cache_file="''${TMPDIR:-/tmp}/claude-ci-''${cache_key}"
        if [ ! -f "$cache_file" ] || [ -n "$(find "$cache_file" -mmin +1 2>/dev/null)" ]; then
          : >> "$cache_file"
          (
            # gh resolves the repo from its working directory, which is not $cwd here.
            cd "$cwd" || exit
            gh run list --limit 1 --branch "$git_branch" \
              --json status,conclusion \
              --jq '.[0] | if .status != "completed" then .status else .conclusion end' \
              2>/dev/null > "''${cache_file}.new" \
              && mv "''${cache_file}.new" "$cache_file" \
              || { rm -f "''${cache_file}.new"; touch "$cache_file"; }
          ) </dev/null >/dev/null 2>&1 &
          disown 2>/dev/null || true
        fi
        ci_state=$(head -n1 "$cache_file" 2>/dev/null)
      fi

      # ANSI colors
      RESET=$'\033[0m'
      BOLD=$'\033[1m'
      CYAN=$'\033[36m'
      GREEN=$'\033[32m'
      YELLOW=$'\033[33m'
      RED=$'\033[31m'
      DIM=$'\033[2m'

      # Dimmed pipe between groups, so the separators recede and the values stay bright.
      SEP="''${DIM}│''${RESET}"

      # Joins non-empty segments with SEP; absent fields leave no dangling separator.
      joined=""
      join_segs() {
        local seg
        joined=""
        for seg in "$@"; do
          [ -n "$seg" ] || continue
          if [ -n "$joined" ]; then joined+=" ''${SEP} ''${seg}"; else joined="$seg"; fi
        done
      }

      # Green under 50%, yellow from 50%, red from 80%.
      pct_color=""
      set_pct_color() {
        if [ "$1" -ge 80 ]; then pct_color="$RED"
        elif [ "$1" -ge 50 ]; then pct_color="$YELLOW"
        else pct_color="$GREEN"
        fi
      }

      bar_out=""
      make_bar() {
        local pct=$1 width=$2 filled i
        filled=$(( (pct * width + 50) / 100 ))
        [ "$filled" -gt "$width" ] && filled=$width
        [ "$filled" -lt 0 ] && filled=0
        bar_out=""
        for ((i = 0; i < filled; i++)); do bar_out+="█"; done
        for ((i = filled; i < width; i++)); do bar_out+="░"; done
      }

      # Context meter
      ctx_display=""
      if [ -n "$used_pct" ]; then
        ctx_int=''${used_pct%.*}
        set_pct_color "$ctx_int"
        make_bar "$ctx_int" 10
        ctx_display="''${DIM}ctx''${RESET} ''${pct_color}''${bar_out} ''${ctx_int}%''${RESET}"
      fi

      # CI status
      case "$ci_state" in
        success)                 ci_display="''${GREEN}ci ok''${RESET}" ;;
        failure|timed_out)       ci_display="''${RED}ci fail''${RESET}" ;;
        cancelled|action_required|startup_failure)
                                 ci_display="''${YELLOW}ci ''${ci_state}''${RESET}" ;;
        in_progress|queued|requested|waiting|pending)
                                 ci_display="''${YELLOW}ci running''${RESET}" ;;
        "")                      ci_display="" ;;
        *)                       ci_display="''${DIM}ci ''${ci_state}''${RESET}" ;;
      esac

      # Rate limits (Pro/Max only; each window can be absent independently)
      limits_display=""
      for window in "5h:$limit_5h" "7d:$limit_7d"; do
        label=''${window%%:*}
        value=''${window#*:}
        [ -n "$value" ] || continue
        value_int=''${value%.*}
        set_pct_color "$value_int"
        [ -n "$limits_display" ] && limits_display+=" "
        limits_display+="''${DIM}''${label}''${RESET} ''${pct_color}''${value_int}%''${RESET}"
      done

      # Session name
      session_display=""
      if [ -n "$session_name" ]; then
        session_display="''${DIM}[''${session_name}]''${RESET}"
      fi

      # Account email — read live from ~/.claude.json
      account_display=""
      account_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
      if [ -n "$account_email" ]; then
        account_display="''${DIM}''${account_email}''${RESET}"
      fi

      # Branch segment
      branch_display=""
      [ -n "$git_branch" ] && branch_display="''${DIM}''${git_branch}''${RESET}"

      # Row 1: where you are. Row 2: how it is going.
      join_segs "''${BOLD}''${CYAN}''${cwd##*/}''${RESET}" "$branch_display" "$session_display" "$account_display"
      printf '%s\n' "$joined"

      join_segs "''${GREEN}''${model}''${RESET}" "$ctx_display" "$ci_display" "$limits_display"
      printf '%s\n' "$joined"
    '';
  };

  home.file.".claude/hooks/block-ssh-rg-cd.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code PreToolUse hook — blocks direct host connections, bare rg, and cd.
      # ssh/scp/sftp: this agent must never open a connection to a remote host (see
      #   CLAUDE.md). Only the connecting form matches — the command name must be
      #   followed by whitespace or end-of-line. Local helpers (ssh-add, ssh-keygen,
      #   ssh-agent) and ~/.ssh/ paths stay allowed so the agent can diagnose its own
      #   SSH identity; blocking those is what made a past failure undebuggable.
      # bare rg: use `rtk semble search` instead of ripgrep for code search.
      # cd: use absolute paths instead of changing directory mid-command.

      CMD=$(jq -r '.tool_input.command // empty')

      # Stage 1 — cd and bare rg. Checked for every command, git included.
      if echo "$CMD" | grep -Eq '^\s*rg\b|(^|;|&&)\s*cd\s'; then
        echo "Blocked: use rtk semble search instead of rg. Use absolute paths instead of cd." >&2
        exit 2
      fi

      # Stage 2 — ssh/scp/sftp. Skipped for git, which cannot open an interactive
      # host connection and routinely carries "ssh" as free text (commit messages,
      # grep patterns, branch names). Trying to tell argument from message text with
      # one regex is what kept blocking legitimate commits.
      # GIT_SSH_COMMAND="ssh -i key" only configures git's transport, so drop the
      # assignment before deciding whether this is a git command.
      SCAN=$(printf '%s' "$CMD" | sed -E 's/^[[:space:]]*GIT_SSH_COMMAND=("[^"]*"|[^[:space:]]*)[[:space:]]*//')

      case "$SCAN" in
        git\ *|rtk\ git\ *|/*/git\ *) exit 0 ;;
      esac

      if echo "$SCAN" | grep -Eq '(^|[^[:alnum:]._-])(ssh|scp|sftp)([[:space:]]|$)'; then
        echo "Blocked: no direct ssh/scp/sftp to a host. ssh-add, ssh-keygen, .ssh/ paths and git commands are allowed." >&2
        exit 2
      fi

      exit 0
    '';
  };

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
    commands = skillCommands;
    # Lets Claude Code delegate tasks to / request review from the codex CLI.
    # Claude-only: opencode.nix and codex.nix don't understand the
    # .claude-plugin format, so this isn't fed through skills.nix.
    plugins = [ "${codexPluginCcSource}/plugins/codex" ];
    settings = {
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
          "mcp__plugin_claude-code-home-manager_context7__query-docs"
          "mcp__plugin_claude-code-home-manager_playwright__browser_take_screenshot"
          "mcp__plugin_claude-code-home-manager_playwright__browser_navigate"
          "mcp__plugin_claude-code-home-manager_context7__resolve-library-id"
          "mcp__plugin_claude-code-home-manager_nixos__nix"
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
