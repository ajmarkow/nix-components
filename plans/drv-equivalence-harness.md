# Derivation-equivalence harness for the nix-components refactor

## Context

`nix-components` has grown several files that mix unrelated concerns:
`modules/claude-code.nix` (455 L: skills + statusline script + 2 hook scripts +
credentials + options), `modules/lib/claude-md-content.nix` (421 L, ~35 topics in
one string), `modules/neovim.nix` (397 L), and three `os-modules/*.nix` files that
each pack `shared + darwin + nixos` into one file. We want to split these into
logically organized files.

The refactor must be **output-neutral**: every derivation the repo produces, and
every derivation its three consumer repos produce from it, must come out
byte-identical. That is not a safe assumption here, because several mechanisms in
this repo are sensitive to file layout and to exact string bytes:

- `home-modules.nix` builds `homeModules.<name>` by `readDir ./modules` on
  **top-level regular files only**. A new `modules/foo.nix` silently adds a new
  public output; moving a module into `modules/claude-code/` silently removes one.
- The same auto-glob runs twice over `pkgs/*.nix` (`per-system.nix` and
  `overlays.nix`), and recursively over `scripts/` (`modules/packages.nix`).
- `home.file.<x>.text`, `writeShellScript`, and `writeShellApplication` hash the
  exact string. Moving an inline bash script to a `.sh` file read with
  `builtins.readFile` changes the hash unless the bytes — including the trailing
  newline — match exactly.
- `_module.args` injection in `home-modules.nix` is keyed by **filename**
  (`namesNeedingSkillArgs`, `namesNeedingCliPackageArgs`, and the
  `lib.optionalAttrs (name == "...")` chain). Renaming or splitting
  `claude-code.nix`, `codex.nix`, `opencode.nix`, `packages.nix`, `git.nix`, or
  `obsidian-gui.nix` breaks that dispatch table.

Nothing in the repo catches any of this today. `nix flake check` runs three checks,
and **no homeModule is evaluated end-to-end anywhere** — `home-manager` is not even
a flake input.

This plan delivers **only the test harness**. The refactor itself is a separate,
later task. The harness is written and proven green against `main` first, so that
when the refactor lands we already trust the baseline.

## The primitive: `drvPath`

Nix derivation paths are input-addressed and recursive — the hash of
`/nix/store/…-foo.drv` covers every input derivation transitively. So if a
top-level `drvPath` is unchanged, the entire build closure beneath it is
byte-identical. Comparing sorted `attrpath → drvPath` manifests across two git
revisions is a complete 1:1 equality proof, and it needs no builds.

## Deliverables

### 0. Prep — make the two repo-copy checks hash-stable

`per-system.nix` currently does `cd ${./.}` in the `diff-viewer` and
`mcpm-environment` checks, which copies the **entire repo** into the store. Any
file added or moved changes those two derivations by construction, so they could
never satisfy the equality test.

Narrow them to the files they actually need, e.g.:

```nix
diff-viewer = pkgs.runCommand "diff-viewer-tests" { } ''
  PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 \
    ${./tests/test_diff_viewer_header.py}
  touch "$out"
'';
```

`tests/test_diff_viewer_header.py` also reads `scripts/diff-viewer-header.py`, so
pass that path in explicitly (env var or `sys.argv`) rather than relying on cwd.
Same shape for `mcpm-environment` / `tests/test_mcpm_env.py`.

Behaviour is identical; afterwards both checks are genuinely layout-stable and stay
inside the guarantee. **Do this first and confirm the tests still pass** — it is the
one intentional derivation change, and it belongs in its own commit before any
baseline is taken.

### 1. `scripts/drv-manifest.sh` — emit the manifest

One executable that prints sorted `<attrpath>\t<drvPath>` lines to stdout for a
given flake directory. Three tiers, selectable by flag so slow tiers can be skipped
locally.

**Tier 1 — direct derivation outputs (main flake, no new inputs).**
For each of the four systems in `flake.nix`, emit `drvPath` for every attribute
under `packages`, `checks`, `devShells`, and `formatter`. Discover the attribute
names with `nix flake show --json --all-systems` rather than hardcoding, so a
refactor that accidentally adds or drops a `pkgs/*.nix` shows up as an added or
removed manifest line, not just a changed hash.

**Tier 2 — synthetic module instantiation (`tests/equivalence/`, own lock file).**
This is the tier that covers `modules/` and `os-modules/`, the actual refactor
target. It needs `home-manager`, `nixvim` (for `modules/neovim.nix`), and
`nix-darwin` — inputs we do **not** want in the main `flake.lock`, since every
consumer would inherit those lock entries.

So it lives in a **separate sub-flake** at `tests/equivalence/flake.nix` with its
own `flake.lock`:

```nix
inputs = {
  nix-components.url = "path:../..";
  nixpkgs.follows = "nix-components/nixpkgs";
  home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
  nixvim       = { url = "github:nix-community/nixvim";       inputs.nixpkgs.follows = "nixpkgs"; };
  nix-darwin   = { url = "github:nix-darwin/nix-darwin";      inputs.nixpkgs.follows = "nixpkgs"; };
};
```

`path:../..` resolves relative to the sub-flake, so running it inside a git
worktree of the baseline automatically picks up that worktree's `nix-components`.
The main flake is untouched — no new inputs, no lock churn for `nix-server`,
`nix-mac`, or `nix-pixelbook`.

Outputs, all `drvPath`-only (evaluation, never a build):

- `homeConfigurations."each-<name>"` — one synthetic user per exported
  `homeModules.<name>`, importing that module **alone**. Isolates which module
  changed and covers modules no consumer imports.
- `homeConfigurations."all"` — every `homeModules.*` imported together. Catches
  the `_module.args` dedupe-by-`key` behaviour that `home-modules.nix` goes out of
  its way to arrange, and any cross-module option collision.
- `nixosConfigurations."all"` — a minimal `nixosSystem` importing every
  `nixosModules.*`; take `config.system.build.toplevel.drvPath`.
- `darwinConfigurations."all"` — same for `darwinModules.*`.
- `packages.<system>.overlay-<attr>` — `nixpkgs` with `overlays.default` applied,
  one attr per overlay output, so the overlay path is covered as well as the
  `packages` path.

Build the synthetic user/host stubs by hand (`home.username`, `home.homeDirectory`,
`home.stateVersion`, `system.stateVersion`, a `boot.loader` stub, a dummy
filesystem). No secrets and no `builtins.getEnv` are needed — `check.yml` already
documents that nothing in this repo reads the environment, and the MCP registry
holds only `${VAR}` placeholders.

Derive the attribute name list from `nix eval --json ..#homeModules --apply builtins.attrNames`
rather than hardcoding, so an added or dropped module is visible in the diff.

**Tier 3 — real consumers (cross-repo).**
For each of `nix-server`, `nix-mac`, `nix-pixelbook` at
`/var/lib/paseo/projects/<repo>`, evaluate their real system closure with this
checkout substituted in:

```
nix eval --raw <repo>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath \
  --override-input nix-components "$FLAKE_DIR"
```

All three pin `nix-components.url = "github:ajmarkow/nix-components"` with
`inputs.nixpkgs.follows`, so the override is a clean drop-in. Targets:

| Repo            | Attribute                          |
| --------------- | ---------------------------------- |
| `nix-server`    | `nixosConfigurations."nixos-host"` |
| `nix-pixelbook` | `nixosConfigurations.<host>`       |
| `nix-mac`       | `darwinConfigurations.<host>`      |

This is the ground truth — it proves the machines that actually consume this flake
build the same closure. Its blind spot is any module the three don't import, which
is exactly what Tier 2 covers.

Tier 3 needs those repos present on disk and their own inputs fetchable. Skip with a
loud warning (not a silent pass) when a repo is missing.

### 2. `scripts/assert-same-drvs.sh <baseline-ref>` — the actual test

1. `git worktree add` `<baseline-ref>` into a temp dir (`trap` cleanup on exit).
2. Run `drv-manifest.sh` against the worktree → `baseline.tsv`.
3. Run `drv-manifest.sh` against the working tree → `current.tsv`.
4. `diff -u` them. Non-empty diff → print it and `exit 1`.

Report the three failure classes separately, because they mean different things:

- **removed attrs** — a public output disappeared (the auto-glob stopped seeing a file)
- **added attrs** — a public output appeared (a split file leaked into `modules/` or `pkgs/`)
- **changed drvPath** — same attr, different content (usually a shell-script byte drift)

For a changed attr, print the `nix derivation show -r` diff hint so the next step is
obvious:

```
diff <(nix derivation show -r "$OLD" | jq -S .) <(nix derivation show -r "$NEW" | jq -S .)
```

That narrows a top-level mismatch down to the exact input derivation and env var
that moved — usually one `writeShellApplication` whose text gained or lost a newline.

### 3. `.github/workflows/drv-equivalence.yml` — CI

Runs `assert-same-drvs.sh` with the PR base as the baseline. Tier 1 + Tier 2 on
`ubicloud-standard-2` (x86_64-linux). Tier 3's `nix-mac` leg and Tier 2's
`darwinConfigurations` leg need a darwin evaluator — put those on the
`avrea-macos-latest-8-vcpu` runner that `check.yml` already uses.

Gate it to run only when the label `refactor` is present (or on
`workflow_dispatch`), so ordinary feature PRs that _intend_ to change derivations
are not blocked. `accept-flake-config: true`, matching `check.yml`.

**Do not touch `check.yml`.** This is an additional workflow alongside it.

## Files

| Path                                                         | Action                                                         |
| ------------------------------------------------------------ | -------------------------------------------------------------- |
| `per-system.nix`                                             | Prep: narrow `cd ${./.}` in `diff-viewer` + `mcpm-environment` |
| `tests/test_diff_viewer_header.py`, `tests/test_mcpm_env.py` | Take their input path from argv/env instead of cwd             |
| `scripts/drv-manifest.sh`                                    | New — emit sorted `attrpath\tdrvPath`                          |
| `scripts/assert-same-drvs.sh`                                | New — worktree + diff two revisions                            |
| `tests/equivalence/flake.nix`                                | New sub-flake — synthetic instantiation                        |
| `tests/equivalence/flake.lock`                               | New — generated, committed                                     |
| `.github/workflows/drv-equivalence.yml`                      | New workflow                                                   |
| `docs/` + `AGENTS.md`                                        | Short section: how to run it, and the layout hazards it guards |

Reuse `tests/mcpm-central.nix`'s existing `{ ok, message }` assertion shape where a
Nix-level assertion is wanted; reuse `modules/lib/skills.nix` (`readSkills`) rather
than re-globbing skills.

The new `.sh` and `.nix` files must be `git add`-ed before any `nix` command sees
them — Nix refuses to evaluate untracked files in a flake (`AGENTS.md`).

## Verification

The harness is only trustworthy if it is proven to be both green and red.

1. **Green on a no-op.** `scripts/assert-same-drvs.sh HEAD` on a clean tree must
   exit 0 with an empty diff. Also run it against `HEAD~1` for a commit known to
   touch only markdown — also expected green.
2. **Green across a genuinely inert change.** Add a Nix comment to
   `modules/starship.nix`, re-run — comments do not change derivations, so still 0.
3. **Red on a real change (the important one).** Deliberately break each class and
   confirm a non-zero exit and a useful message:
   - byte drift: add a trailing space inside one line of the `rtk-rewrite.sh`
     heredoc in `modules/claude-code.nix` → expect a changed `drvPath` on
     `homeConfigurations.each-claude-code` _and_ on the `nix-server` toplevel
   - dropped output: `git mv modules/starship.nix modules/starship/default.nix` →
     expect a **removed** `homeModules.starship` line
   - added output: `touch modules/scratch.nix` with a trivial module → expect an
     **added** line
     Revert each after confirming.
4. **`nix flake check` still passes** on the main flake after the Tier-0 prep, on
   both `x86_64-linux` and via CI on `aarch64-darwin`.
5. **CI dry run.** `workflow_dispatch` the new workflow against a scratch branch
   with one of the deliberate breakages above, and confirm it fails the PR.

Only after all five pass should the refactor branch start.

## Known limits, stated up front

- **Tier 3 needs network** for the consumer repos' own inputs, and the `nix-mac`
  leg needs a darwin evaluator. Locally, expect to run Tiers 1–2 and let CI cover
  the darwin legs.
- **`tests/mcpm-central.nix` asserts on source text**, not derivations — it does
  `builtins.readFile ../modules/mcp.nix` then `lib.hasInfix "profile run --http all"`,
  and checks `builtins.readDir ../pkgs` for absent files. Splitting `modules/mcp.nix`
  will fail that check even when every derivation is provably identical. That is a
  refactor-time fix, not a harness one, but it needs to be on the radar — the
  harness will (correctly) stay green while `nix flake check` goes red.
- **This proves sameness, not correctness.** It cannot tell you the pre-refactor
  derivation was right, only that the post-refactor one is identical.

## Board

Per the global rule, an Agentic/Todoist task must exist before implementation
starts. No task is created yet — plan mode is read-only. First action on approval:
find or create the task in **Queue**, then move it to **Active**.
