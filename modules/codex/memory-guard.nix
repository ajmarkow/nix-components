{ ... }:
{
  # Memory guard for the Write/Edit tool layer (same deny class as
  # Claude Code's memory-guard.sh). Codex's apply_patch tool sends the
  # patch body (not a file path) in tool_input.command, so target paths
  # are matched as free text. Shares that script's transcript-based
  # `remember` check; see modules/claude-code/memory-guard.nix for the
  # per-agent wiring gaps.
  #
  # Scope is global paths only: the global AGENTS.md (~/.codex/AGENTS.md)
  # and any auto-memory path. Repo-level AGENTS.md/CLAUDE.md stay
  # writable: agents edit those as normal task output.
  #
  # Deny-only by design: Codex starts same-event command hooks
  # concurrently and resolves competing rewrites by completion order, so
  # this hook never rewrites — only exit 2 denies — and cannot race the
  # secretty wrapper in ./secretty.nix. Wired into hooks.json in
  # ./secretty.nix (same file, so deny script and wiring cannot drift).
  home.file.".codex/hooks/memory-guard.sh" = {
    executable = true;
    text = builtins.readFile ./memory-guard.sh;
  };
}
