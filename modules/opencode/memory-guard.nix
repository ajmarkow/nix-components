_: {
  # Memory guard for the edit/write tool layer (same deny class as
  # Claude Code's memory-guard.sh). Deny-only: throws to abort the call,
  # never rewrites, so no race with the secretty wrap in ./secretty.nix
  # or the Bash deny plugin in ./deny.ts. Wired together in ./hooks.nix.
  #
  # Documented gap: tool.execute.before carries no user prompt, so the
  # `remember` exception the Claude Code/Codex hooks enforce via the
  # session transcript is NOT enforceable in this schema. Global
  # instruction/memory paths are denied unconditionally (fail closed).
  # See modules/claude-code/memory-guard.nix for the full per-agent table.
  #
  # Scope is global paths only: the global AGENTS.md
  # (~/.config/opencode/AGENTS.md) and any auto-memory path. Repo-level
  # AGENTS.md/CLAUDE.md stay writable: agents edit those as normal task
  # output.
  xdg.configFile."opencode/plugins/memory-guard.ts".text = builtins.readFile ./memory-guard.ts;
}
