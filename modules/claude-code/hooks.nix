{ ... }:
{
  home.file.".claude/hooks/block-ssh-rg-cd.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code PreToolUse hook — blocks direct host connections, raw
      # search tools, secret-leaking process checks, auto-memory writes, and
      # local rebuilds. Denies with exit 2; any hook's deny blocks the call.
      # ssh/scp/sftp: this agent must never open a connection to a remote host (see
      #   CLAUDE.md). Only the connecting form matches — the command name must be
      #   followed by whitespace or end-of-line. Local helpers (ssh-add, ssh-keygen,
      #   ssh-agent) and ~/.ssh/ paths stay allowed so the agent can diagnose its own
      #   SSH identity; blocking those is what made a past failure undebuggable.
      # Search: use `rtk semble search` instead of ripgrep/find/grep -r for
      #   code search. Bare `rg` is unambiguous, but `grep` is only blocked
      #   with a recursive flag (-r/-R, alone or bundled like -ril).
      # ps: never run `ps aux` / `ps -ef` — argv may carry tokens. Use
      #   `ps -o pid,comm=` for process checks instead.
      # memory: auto-memory paths are guarded by memory-guard.sh at the
      #   Write/Edit layer; writes via shell redirection are denied here.
      #   Matched on the .claude/projects memory subtree and any /memory/
      #   path so agents cannot dodge by redirecting to an adjacent path.
      #   Repo-level instruction files stay writable via shell.
      # Rebuilds: this is a management server — never rebuild locally. CI
      #   deploys after commit+push.

      CMD=$(jq -r '.tool_input.command // empty')

      deny() {
        echo "Blocked: $1" >&2
        exit 2
      }

      # Stage 1 — search tools. Checked for every command, git included.
      # `git grep` is exempt: version-controlled code search, not
      # filesystem spelunking, so strip it before matching.
      NONGIT_GREP=$(printf '%s' "$CMD" | sed -E 's/git[[:space:]]+(grep|egrep|fgrep)/git-GREP-EXEMPT/g')
      if echo "$CMD" | grep -Eq '(^|[;&|(|`$]|\s)rg\b'; then
        deny "use rtk semble search instead of rg."
      fi
      if echo "$NONGIT_GREP" | grep -Eq '(^|[;&|(|`$]|\s)(grep|egrep|fgrep)[[:space:]]+[^;&|]*-[a-zA-Z]*[rR]'; then
        deny "use rtk semble search instead of grep -r."
      fi
      if echo "$CMD" | grep -Eq '(^|[;&|(|`$]|\s)find[[:space:]]+[^;&|]*-name\b'; then
        deny "use rtk semble search instead of find -name."
      fi

      # Stage 1b — argv-revealing process checks. `ps aux` / `ps -ef` and
      # kin print full command lines where tokens travel in argv. Explicit
      # `-o` output (e.g. `ps -o pid,comm=`) stays allowed: the caller
      # chose safe columns.
      if echo "$CMD" | grep -Eq '(^|[;&|(|`$]|\s)ps[[:space:]]+(aux[[:alnum:]]*|u[[:alnum:]]*|-([[:alnum:]]*[fF][[:alnum:]]*|[[:alnum:]]*u[[:alnum:]]*))([^[:alnum:]_]|$)' \
        && ! echo "$CMD" | grep -Eq '(^|[;&|(|`$]|\s)ps[[:space:]]+[^;&|]*-o[[:space:]]'; then
        deny "no argv-revealing ps (ps aux / ps -ef). Use ps -o pid,comm= instead."
      fi

      # Stage 1c — memory writes and local rebuilds via shell.
      if echo "$CMD" | grep -Eq '(>>?|>)\s*[^;&|]*\.claude/projects/[^;&| ]*memory|>>?\s*[^;&|]*/memory/'; then
        deny "no shell writes to auto-memory (prompt must contain explicit remember approval)."
      fi
      if echo "$CMD" | grep -Eq '(^|[;&|(|`$]|\s)(nixos-rebuild|home-manager)[[:space:]]+switch\b'; then
        deny "never rebuild locally — commit+push, CI deploys."
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
        deny "no direct ssh/scp/sftp to a host. ssh-add, ssh-keygen, .ssh/ paths and git commands are allowed."
      fi

      exit 0
    '';
  };

  home.file.".claude/hooks/rtk-rewrite.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # rtk-hook-version: 3
      # RTK Claude Code hook — rewrites commands to use rtk for token savings,
      # then wraps the result with secretty so its output gets redacted.
      # Requires: rtk >= 0.23.0, jq
      #
      # This is a thin delegating hook: all rtk rewrite logic lives in
      # `rtk rewrite`, which is the single source of truth
      # (src/discover/registry.rs). To add or change rewrite rules, edit the
      # Rust registry — not this file. Do not run `rtk init -g` against the
      # deployed copy of this script: it treats this as a legacy hook to
      # migrate/replace, which would silently drop the secretty wrap below.
      #
      # The secretty wrap lives here, in the same hook, rather than as a
      # second PreToolUse hook, because Claude Code runs all matching
      # PreToolUse hooks in parallel against the SAME original tool_input —
      # there is no chaining, so a second hook can't safely layer its own
      # updatedInput on top of this one's without a race. Composing both
      # transformations in one hook guarantees exactly one updatedInput.
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
          # If the output is identical, the command was already using RTK
          # (or RTK had nothing to add) — fall through to the secretty wrap
          # below using the original command.
          FINAL_CMD="$REWRITTEN"
          RTK_REASON="RTK auto-rewrite"
          [ "$CMD" = "$REWRITTEN" ] && RTK_REASON=""
          ;;
        1)
          # No RTK equivalent — still wrap with secretty below, unchanged.
          FINAL_CMD="$CMD"
          RTK_REASON=""
          ;;
        2)
          # Deny rule matched — let Claude Code's native deny rule handle it.
          # Do not wrap: the command will never run.
          exit 0
          ;;
        3)
          # Ask rule matched — rewrite the command but do NOT auto-allow, and
          # do NOT secretty-wrap: this is a deliberate human-review gate, and
          # the wrapped invocation would be unreadable in the confirmation
          # prompt. secretty protection resumes for whatever the user runs
          # next once they've approved this one.
          ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
          UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')
          jq -n \
            --argjson updated "$UPDATED_INPUT" \
            '{
              "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "updatedInput": $updated
              }
            }'
          exit 0
          ;;
        *)
          exit 0
          ;;
      esac

      # Wrap the final command with secretty so its output gets redacted
      # before Claude ever sees it. Degrade gracefully (run unwrapped) if
      # secretty isn't installed, matching rtk's own degrade-gracefully
      # pattern above rather than blocking the tool call outright.
      # Idempotency guard: pass through commands already wrapped (the agent
      # sometimes copies the visible wrapper into its next call; wrapping
      # again compounds quoting until bash fails to parse).
      if [[ "$FINAL_CMD" =~ ^[[:space:]]*[\'\"]?[^[:space:]\'\"]*secretty[\'\"]?[[:space:]] ]]; then
        WRAPPED_CMD="$FINAL_CMD"
      elif command -v secretty &>/dev/null; then
        QUOTED_CMD=$(printf '%q' "$FINAL_CMD")
        WRAPPED_CMD="secretty --config \"\$HOME/.config/secretty/config.yaml\" --no-init-hints --strict run -- bash -c $QUOTED_CMD"
      else
        WRAPPED_CMD="$FINAL_CMD"
      fi

      ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
      UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$WRAPPED_CMD" '.command = $cmd')

      # Every case reaching here (0 and 1) auto-allows: rewriting the command
      # to route through secretty changes the literal string Claude Code's
      # permission patterns would otherwise match against, so preserving the
      # normal allow-list UX (no extra prompt) requires this hook to make the
      # call itself. This does not bypass other hooks' own deny decisions —
      # e.g. block-ssh-rg-cd.sh's exit-2 denials still win regardless of what
      # this hook returns, since a deny from any hook blocks the tool call.
      REASON="''${RTK_REASON:-secretty redaction wrap}"
      jq -n \
        --argjson updated "$UPDATED_INPUT" \
        --arg reason "$REASON" \
        '{
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": $reason,
            "updatedInput": $updated
          }
        }'
    '';
  };
}
