{ ... }:
{
  # Memory guard script: denies Write|Edit to the global agent
  # instruction file and auto-memory unless the latest user turn in the
  # session transcript contains explicit `remember` approval. Evidence:
  # sessions 6f3c401, 3549758 wrote auto-memory then deleted it. Shell
  # redirections to memory paths are denied separately in each agent's
  # Bash hook (block-ssh-rg-cd.sh and its codex/opencode counterparts);
  # this script guards the Write/Edit tool layer, which shell hooks
  # cannot see.
  #
  # Scope is global paths only: ~/.claude/CLAUDE.md and auto-memory
  # (~/.claude/projects/*/memory). Repo-level CLAUDE.md/AGENTS.md stay
  # writable: agents edit those as normal task output.
  #
  # Wiring (hook schemas differ per agent):
  # - Claude Code: ./memory-guard.nix is imported by ../claude-code.nix;
  #   the PreToolUse Write|Edit entry lives in ./settings.nix (single
  #   definition — no same-leaf merge-order question). No hook payload
  #   carries the same-turn user prompt, so approval is read best-effort
  #   from the session transcript's latest user message. The transcript
  #   format is not a stable API; unparseable transcript means no
  #   approval was found and the guard denies (fail closed).
  # - Codex: ../codex/memory-guard.nix, wired in ../codex/hooks.nix
  #   (PreToolUse matcher Edit|Write, same transcript check, same
  #   caveat). Deny-only, so no race with the secretty wrapper despite
  #   Codex starting same-event hooks concurrently. Changing hooks.json
  #   re-triggers Codex's content-hash trust review (/hooks) on next start.
  # - Opencode: ../opencode/memory-guard.ts plugin (deny-only, no
  #   rewrite, so no race with secretty.ts or deny.ts). That event
  #   carries no user prompt, so the `remember` exception is NOT
  #   enforceable there; global paths are denied unconditionally.
  home.file.".claude/hooks/memory-guard.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Deny Write|Edit to the global CLAUDE.md (~/.claude/CLAUDE.md) and
      # any auto-memory path unless the latest user turn in the session
      # transcript contains explicit `remember` approval. Exit 2 blocks
      # the call; stdout JSON is ignored. Repo-level CLAUDE.md/AGENTS.md
      # stay writable.

      INPUT=$(cat)
      PATH_ARG=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
      TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

      is_guarded=0
      case "$PATH_ARG" in
        */.claude/CLAUDE.md|*/memory/*) is_guarded=1 ;;
      esac
      [ "$is_guarded" -eq 1 ] || exit 0

      # Latest user message text, tolerating string or content-block array
      # form. Anything unparseable means no approval was found.
      if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
        LAST_USER=$(jq -r 'select(.type == "user") | .message.content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end // empty' "$TRANSCRIPT" 2>/dev/null | tail -1)
        if echo "$LAST_USER" | grep -Eiq '(^|[^[:alnum:]_])remember([^[:alnum:]_]|$)'; then
          exit 0
        fi
      fi

      echo "Blocked: no writes to global CLAUDE.md or auto-memory without explicit user 'remember' approval in this turn." >&2
      exit 2
    '';
  };
}
