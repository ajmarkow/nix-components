#!/usr/bin/env bash
# Deny Edit|Write to the global AGENTS.md (~/.codex/AGENTS.md) and
# any auto-memory path unless the latest user turn in the session
# transcript contains explicit `remember` approval. Exit 2 blocks
# the call. Repo-level AGENTS.md/CLAUDE.md stay writable.

input=$(cat)
command=$(jq -r '.tool_input.command // empty' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")

# apply_patch body or bare path: allow unless a guarded path matches.
if ! echo "$command" | grep -Eq '\.codex/AGENTS\.md|/memory/'; then
  exit 0
fi

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  last_user=$(jq -r 'select(.type == "user") | .message.content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end // empty' "$transcript" 2>/dev/null | tail -1)
  if echo "$last_user" | grep -Eiq '(^|[^[:alnum:]_])remember([^[:alnum:]_]|$)'; then
    exit 0
  fi
fi

echo "Blocked: no writes to global AGENTS.md or auto-memory without explicit user 'remember' approval in this turn." >&2
exit 2
