import type { Plugin } from "@opencode-ai/plugin";

// Memory guard for the edit/write tool layer (same deny class as
// Claude Code's memory-guard.sh). Deny-only: throws to abort the call,
// never rewrites, so no race with the secretty wrap in secretty.ts or
// the Bash deny plugin in deny.ts.
//
// Documented gap: tool.execute.before carries no user prompt, so the
// `remember` exception the Claude Code/Codex hooks enforce via the
// session transcript is NOT enforceable in this schema. Global paths
// are denied unconditionally (fail closed).
//
// Scope is global paths only: the global AGENTS.md
// (~/.config/opencode/AGENTS.md) and any auto-memory path. Repo-level
// AGENTS.md/CLAUDE.md stay writable: agents edit those as normal task
// output.
const isGuardedPath = (filePath: unknown): boolean => {
  if (typeof filePath !== "string" || filePath.length === 0) return false;
  if (/(^|\/)\.config\/opencode\/AGENTS\.md$/.test(filePath)) return true;
  return /(^|\/)memory\//.test(filePath);
};

export const MemoryGuardPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "edit" && input.tool !== "write") return;

      const filePath = output.args.filePath ?? output.args.path;
      if (isGuardedPath(filePath)) {
        throw new Error(
          "Blocked: no writes to global AGENTS.md or auto-memory via " +
            input.tool +
            " (no `remember` exception: this hook carries no user prompt).",
        );
      }
    },
  };
};
