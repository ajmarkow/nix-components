# Agent Instructions

## Adding MCP servers

Do not create `mcp.json` files manually. This repo manages MCP configuration declaratively through Nix. See [adding-mcp.md](docs/adding-mcp.md) for where and how to add an MCP server entry.

## nixpkgs searches

Use `nix search <package>` to query nixpkgs from the CLI. Do NOT spawn agents to search nixpkgs or clone the repo—it's massive. Always check for official packages before installing globally via npm.

Example: `nix search serverless` to see if an npm package has a nixpkgs equivalent.

## Flake structure (flake-parts)

This flake uses [flake-parts](https://flake.parts) to split outputs across files. System-independent outputs (e.g. `homeModules`) go inside the `flake = { ... }` block in `flake.nix`. Per-system outputs (e.g. `packages`) are defined in `perSystem` modules and imported via the top-level `imports` list.

`packages.nix` at the repo root is one such module. Other flakes consume its outputs as:

```nix
inputs.nix-components.packages.${system}.ripgrep
inputs.nix-components.packages.${system}.summarize
```

To add a new per-system output, either extend `packages.nix` or add a new file and import it in `flake.nix`.

## CLAUDE.md is Nix-generated — never edit it directly

The global `~/.claude/CLAUDE.md` is built by `modules/claude-code-claude-md.nix`. Do not edit the markdown file directly. Any changes to Claude's system instructions must go into that Nix file instead.

## New files must be git-tracked before `nix flake check`

Nix will refuse to evaluate files that are not tracked by Git, even if they exist on disk. After creating a new `.nix` file, run `git add <file>` before running `nix flake check` or any `nix build`.

## Inter-agent messaging via paseo

When dispatching work to another agent, prefer `paseo send <id> "..."` if an agent for that repo is already running. Only use `paseo run` to start a new agent when none exists. Default to the Sonnet model when spawning new agents.

The companion server repo is named **`nix-server`** (at `~/paseo-projects/nix-server`). Do not use the old name `server-2-config`.

Never run `find /nix/store` — the store is massive and the command will hang indefinitely. Use `which`, `nix-env -q`, or PATH inspection to locate binaries instead.

## Linting and dead code

Two linters are available in the devShell (`nix develop`):

- **statix** — catches Nix antipatterns (e.g. `with pkgs;`, `rec` where unnecessary, deprecated syntax)
  - `statix check` — report warnings
  - `statix fix` — auto-fix safe issues

- **deadnix** — finds unused `let` bindings and function arguments
  - `deadnix` — report unused bindings
  - `deadnix --edit` — auto-remove them

Run both before committing any Nix changes. Fix `statix` warnings manually if `statix fix` doesn't cover them; `deadnix --edit` is safe to apply automatically.
