{ ... }:
{
  home.file.".claude/hooks/block-ssh-rg-cd.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code PreToolUse hook — blocks direct host connections and bare rg.
      # ssh/scp/sftp: this agent must never open a connection to a remote host (see
      #   CLAUDE.md). Only the connecting form matches — the command name must be
      #   followed by whitespace or end-of-line. Local helpers (ssh-add, ssh-keygen,
      #   ssh-agent) and ~/.ssh/ paths stay allowed so the agent can diagnose its own
      #   SSH identity; blocking those is what made a past failure undebuggable.
      # bare rg: use `rtk semble search` instead of ripgrep for code search.

      CMD=$(jq -r '.tool_input.command // empty')

      # Stage 1 — bare rg. Checked for every command, git included.
      if echo "$CMD" | grep -Eq '^\s*rg\b'; then
        echo "Blocked: use rtk semble search instead of rg." >&2
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
}
