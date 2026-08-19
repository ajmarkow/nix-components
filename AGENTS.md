# Agent Instructions

## Adding MCP servers

Do not create `mcp.json` files manually. This repo manages MCP configuration declaratively through Nix. See [adding-mcp.md](docs/adding-mcp.md) for where and how to add an MCP server entry.

## nixpkgs searches

Prefer the `nixos` MCP server (`nix` / `nix_versions` tools) to query nixpkgs — it hits live APIs and is more current than the CLI. Fall back to `nix search <package>` when the MCP server is unavailable. Do NOT spawn agents to search nixpkgs or clone the repo—it's massive. Always check for official packages before installing globally via npm.

## Flake structure (flake-parts)

This flake uses [flake-parts](https://flake.parts) to split outputs across files. System-independent outputs (e.g. `homeModules`) go inside the `flake = { ... }` block in `flake.nix`. Per-system outputs (e.g. `packages`) are defined in `perSystem` modules and imported via the top-level `imports` list.

`packages.nix` at the repo root is one such module. Other flakes consume its outputs as:

```nix
inputs.nix-components.packages.${system}.ripgrep
inputs.nix-components.packages.${system}.summarize
```

To add a new per-system output, either extend `packages.nix` or add a new file and import it in `flake.nix`.

## CLAUDE.md / AGENTS.md are Nix-generated — never edit them directly

The global `~/.claude/CLAUDE.md` (Claude Code) and `~/.config/opencode/AGENTS.md` (opencode) share one source string in `modules/lib/claude-md-content.nix`, imported by `modules/claude-code-claude-md.nix` and `modules/opencode.nix` respectively. Do not edit the generated markdown files directly, and do not inline the text back into either consuming module — read `modules/lib/claude-md-content.nix`'s own header comment for why (it caused an infinite-recursion eval failure once). Any changes to the shared system instructions must go into `modules/lib/claude-md-content.nix`.

## New files must be git-tracked before `nix flake check`

Nix will refuse to evaluate files that are not tracked by Git, even if they exist on disk. After creating a new `.nix` file, run `git add <file>` before running `nix flake check` or any `nix build`.

## Companion repo

The companion server repo is named **`nix-server`** (at `~/paseo-projects/nix-server`). Do not use the old name `server-2-config`.

## Claude Code skills

Skills registered with `programs.claude-code.commands` come from two sources:

- **Local skills** — directories under `skills/` in this repo, committed directly
- **Upstream paseo skills** — fetched at build time from `github:getpaseo/paseo` via the `paseo-skills` flake input

The merge happens in `modules/claude-code.nix`. Do not commit paseo skills into `skills/` — they are read directly from the locked flake input at evaluation time.

To update the upstream paseo skills to their latest version:

```bash
nix flake update paseo-skills
```

To add a new local skill, create `skills/<name>/SKILL.md`. It will be picked up automatically.

## Linting and dead code

Two linters are available in the devShell (`nix develop`):

- **statix** — catches Nix antipatterns (e.g. `with pkgs;`, `rec` where unnecessary, deprecated syntax)
  - `statix check` — report warnings
  - `statix fix` — auto-fix safe issues

- **deadnix** — finds unused `let` bindings and function arguments
  - `deadnix` — report unused bindings
  - `deadnix --edit` — auto-remove them

Run both before committing any Nix changes. Fix `statix` warnings manually if `statix fix` doesn't cover them; `deadnix --edit` is safe to apply automatically.

<!-- BACKLOG.MD GUIDELINES START -->
<!-- backlog.md-instructions-version: 1.47 -->
<CRITICAL_INSTRUCTION>

## Backlog.md Workflow

This project uses Backlog.md for task and project management.

**When a request involves creating, updating, planning, searching, or finalizing tasks, run `backlog instructions overview` first.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Use the detailed guides when needed:
- `backlog instructions task-creation` for creating or splitting tasks
- `backlog instructions task-execution` for planning and implementation workflow
- `backlog instructions task-finalization` for completion and handoff

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.

</CRITICAL_INSTRUCTION>
<!-- BACKLOG.MD GUIDELINES END -->
