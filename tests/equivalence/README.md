# drv-equivalence harness

Proves that a change to this repo produces byte-identical derivations, 1:1,
across two git revisions. Background and design: `plans/drv-equivalence-harness.md`
in the repo root.

The primitive: a Nix derivation path is input-addressed and recursive, so if
a top-level `drvPath` is unchanged, the whole build closure beneath it is
byte-identical. The tools compare sorted `<attrpath> <drvPath>` manifests
across two revisions -- no builds required anywhere.

## Tools

- **`scripts/drv-manifest.sh <flakeref> [-- <extra nix eval args>]`** -- emits
  the manifest for a single flakeref. Enumerates `packages`/`checks`/
  `devShells`/`formatter` per system, and the flat `homeConfigurations`/
  `nixosConfigurations`/`darwinConfigurations` groups when present. Works
  unmodified against both the main flake and the `tests/equivalence`
  sub-flake -- whichever groups a given flake doesn't have are skipped
  silently. An attr that genuinely exists (confirmed by `builtins.attrNames`)
  but fails to evaluate is recorded as `ERROR` rather than dropped, so a
  broken new file shows as drift instead of a silent skip.

- **`scripts/assert-same-drvs.sh <baseline-ref> [--tier2] [--tier3 <repo>...]`**
  -- the actual test. Diffs this repo's own manifest (Tier 1) between
  `<baseline-ref>` and the working tree, evaluating the baseline directly via
  a `git+file://<repo>?rev=<sha>` flakeref (no worktree to create or clean
  up). `--tier2` additionally diffs `tests/equivalence` with `nix-components`
  overridden to each revision in turn. `--tier3 <repo>...` does the same
  against each given real downstream repo's system closure. A repo that
  fails to evaluate is reported as a warning and skipped, not a silent pass.
  On drift, prints a `nix derivation show -r` diff hint per changed attr, to
  narrow the mismatch down to the exact input derivation that moved.

## Tier 2 -- this sub-flake

Instantiates every `homeModules.<name>`/`nixosModules.<name>`/
`darwinModules.<name>` nix-components exports, end to end, against minimal
stub configs (`stubUser`/`stubNixos`/`stubDarwin` in `flake.nix`). This is
the tier Tier 1 can't cover on its own: `home-manager`/`nix-darwin`/`nixvim`
are not inputs of the main flake at all, so no homeModule is ever
instantiated there. Kept as its own flake with its own lock so those three
inputs never enter the main flake's lock -- every downstream consumer
already provides its own.

One representative system per config type (`x86_64-linux` for home/nixos,
`aarch64-darwin` for darwin) rather than all four -- Tier 1 already proves
every plain package/check/devShell/formatter across all four systems; this
tier exists to prove the module surface instantiates and stays stable, which
only needs one Linux and one Darwin target.

`overlays.default` is deliberately not re-tested here -- its contents are
exactly `pkgs/*.nix`, already covered byte-for-byte by Tier 1's
`packages.<system>` comparison.

## Tier 3 -- real consumers (local only, not wired into CI)

Run by hand against the sibling checkouts on this management server:

```bash
# from the repo root
./scripts/assert-same-drvs.sh <baseline-ref> --tier3 \
  /var/lib/paseo/projects/nix-server \
  /var/lib/paseo/projects/nix-mac \
  /var/lib/paseo/projects/nix-pixelbook
```

Exact attrpaths `drv-manifest.sh` resolves for each (via the flat-group
suffix table, no configuration needed -- names are discovered dynamically):

| Repo            | Attribute                                                                        |
| --------------- | -------------------------------------------------------------------------------- |
| `nix-server`    | `nixosConfigurations."nixos-host".config.system.build.toplevel`                  |
| `nix-pixelbook` | `nixosConfigurations."pixelbook-go".config.system.build.toplevel`                |
| `nix-mac`       | `darwinConfigurations."AJ-MARKOW-WORK-MACBOOK-PRO".config.system.build.toplevel` |

Deliberately not wired into `.github/workflows/drv-equivalence.yml`:
`nix-components` is public and all three consumers are private, so a CI job
would need a new PAT/deploy-key secret with read access to all three, for no
benefit over running it here where they're already checked out.

**Darwin-eval note:** evaluating a `darwinSystem`/`nix-mac` config is pure
evaluation, same as `nixosSystem`, and has been confirmed to work from this
Linux management server -- no macOS runner needed. If a future nix-darwin
version introduces a host-platform-coupled default that breaks that, fall
back to running that one comparison from a Mac (or the `aarch64-darwin`
runner `check.yml` already uses) rather than blocking the other two.

## Known limit

`tests/mcpm-central.nix` (in the repo root, unrelated to this harness) does
`builtins.readFile ../modules/mcp.nix` and asserts `lib.hasInfix` on the raw
text. Splitting `modules/mcp.nix` into multiple files will fail that check
even when every derivation this harness checks is provably identical --
that's a fix for the refactor itself, not something this harness can or
should paper over.

## This proves sameness, not correctness

The harness proves the post-refactor derivations are identical to the
pre-refactor ones. It cannot tell you the pre-refactor derivation was right
in the first place.
