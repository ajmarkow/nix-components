# Remote Paseo Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let agents on any nix-managed host run `paseo` against the remote daemon at paseo.aj-cloud.cc without ever exposing the password.

**Architecture:** A new home-manager module exports `PASEO_HOST` (non-secret config); `PASEO_PASSWORD` arrives via the existing Infisical shell-init export in `modules/zsh.nix`. The paseo CLI natively reads both env vars, so no wrapper is needed. Agent guidance in CLAUDE.md is updated to match.

**Tech Stack:** nix-components home-manager modules, Infisical, paseo CLI (`@getpaseo/cli`).

**Spec:** `docs/superpowers/specs/2026-08-18-remote-paseo-access-design.md`

**Prerequisite (already done):** `PASEO_PASSWORD` is set in Infisical prod, project `0bd4a4d8-f58e-4bad-9d65-c16ee9aeae7e`. The pixelbook uses a different Infisical project — set `PASEO_PASSWORD` there when that project is created.

**Note on verification:** These are nix config changes; there is no unit-test framework. Each task verifies via `nix flake check --no-build` (evaluation) plus targeted `nix eval` assertions, with end-to-end verification in Task 4.

---

### Task 1: Create the paseo-remote home-manager module

**Files:**
- Create: `modules/paseo-remote.nix` (nix-components repo)

`home-modules.nix` auto-registers every `modules/*.nix` file as `homeModules.<name>`, so no wiring file changes are needed in this repo.

- [ ] **Step 1: Write the module**

Create `modules/paseo-remote.nix`:

```nix
{ lib, config, ... }:
{
  options.nix-components.paseo.remoteHost = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = "tcp://paseo.aj-cloud.cc:443?ssl=true";
    description = ''
      Paseo daemon host URI exported as PASEO_HOST in zsh. The password is
      NOT part of this URI; the CLI reads it separately from PASEO_PASSWORD,
      which the zsh module loads from Infisical. Set to null on a host that
      runs the daemon locally so the CLI uses the local socket.
    '';
  };

  config = lib.mkIf (config.nix-components.paseo.remoteHost != null) {
    # mkOrder 1500 (mkAfter) places this after zsh.nix's Infisical eval
    # (mkOrder 1000), so the nix-declared host always wins.
    programs.zsh.initContent = lib.mkOrder 1500 ''
      export PASEO_HOST="${config.nix-components.paseo.remoteHost}"
    '';
  };
}
```

- [ ] **Step 2: Verify the module self-registers and the flake evaluates**

Run from the nix-components repo root:

```bash
nix --extra-experimental-features "nix-command flakes" eval /Users/ajmarkow/Documents/nix-components#homeModules --apply 'ms: builtins.hasAttr "paseo-remote" ms'
```

Expected: `true`

```bash
nix --extra-experimental-features "nix-command flakes" flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: `all checks passed!`

- [ ] **Step 3: Commit (show diff to user first, per CLAUDE.md)**

```bash
rtk git -C /Users/ajmarkow/Documents/nix-components add modules/paseo-remote.nix
rtk git -C /Users/ajmarkow/Documents/nix-components commit -m "feat(paseo): add paseo-remote module exporting PASEO_HOST"
```

---

### Task 2: Update agent guidance in claude-md-content.nix

**Files:**
- Modify: `modules/lib/claude-md-content.nix` (nix-components repo, "Inter-Agent Messaging" section, near line 110)

- [ ] **Step 1: REQUIRED — invoke the `adding-to-claude-md` skill before editing**

That skill governs how additions to this file must be written. Follow it; the content below is the draft input to that process, not a bypass of it.

- [ ] **Step 2: Insert the remote-access rules**

In the `## Inter-Agent Messaging` section, after the paragraph ending "`paseo` does not need the `rtk` prefix." insert:

```markdown
**Remote daemon:** The paseo daemon runs on paseo.aj-cloud.cc, not on this
host. Plain `paseo` commands reach it automatically: `PASEO_HOST` is set by
nix, and `PASEO_PASSWORD` loads from Infisical at shell init.

- **NEVER** put `password=` in a `--host` URI, print `PASEO_PASSWORD`, or
  write it to a file. The env vars are the only sanctioned channel.
- If paseo reports unauthorized/unreachable: check `~/.config/infisical-token`
  (or run `infisical login`), then retry in a fresh shell. Do not hunt for
  the password.
- Headless contexts without zsh init (cron, launchd) may use exactly:
  `PASEO_PASSWORD=$(infisical secrets get PASEO_PASSWORD --plain --projectId=0bd4a4d8-f58e-4bad-9d65-c16ee9aeae7e --env=prod) paseo ...`
  — substitution straight into the consumer, never echoed.
```

- [ ] **Step 3: Verify the flake evaluates**

```bash
nix --extra-experimental-features "nix-command flakes" flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: `all checks passed!`

- [ ] **Step 4: Commit (show diff to user first)**

```bash
rtk git -C /Users/ajmarkow/Documents/nix-components add modules/lib/claude-md-content.nix
rtk git -C /Users/ajmarkow/Documents/nix-components commit -m "docs(claude-md): remote paseo access rules for off-server agents"
```

---

### Task 3: Push nix-components and deploy

- [ ] **Step 1: Push**

```bash
rtk git -C /Users/ajmarkow/Documents/nix-components push
```

- [ ] **Step 2: REQUIRED — invoke the `deploy-nix-components` skill**

It owns propagation (CI on nix-components, then the nix-components input bump on nix-server). Follow it rather than bumping by hand.

---

### Task 4: Wire into nix-mac and verify end-to-end

**Files:**
- Modify: `/etc/nix-darwin/flake.nix` (`home-manager.sharedModules` list, near line 340; `flake.lock` via targeted update)

- [ ] **Step 1: Bump only the nix-components input**

```bash
nix --extra-experimental-features "nix-command flakes" flake update nix-components --flake /etc/nix-darwin
```

Scope note: this targeted single-input bump is pre-approved by this plan. Do NOT update other inputs; never bump nixpkgs (shared pin across repos).

- [ ] **Step 2: Import the module**

In `/etc/nix-darwin/flake.nix`, in `home-manager.sharedModules`, after the line `inputs.nix-components.homeModules.zsh` add:

```nix
                  inputs.nix-components.homeModules.paseo-remote
```

The Mac uses the module's default `remoteHost`, so no option setting is needed.

- [ ] **Step 3: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" flake check --no-build /etc/nix-darwin
```

Expected: `all checks passed!`

- [ ] **Step 4: Commit and push (show diff to user first)**

```bash
rtk git -C /etc/nix-darwin add flake.nix flake.lock
rtk git -C /etc/nix-darwin commit -m "feat(paseo): target remote daemon via nix-components paseo-remote module"
rtk git -C /etc/nix-darwin push
```

- [ ] **Step 5: User applies and verifies (agent must not run rebuilds)**

Ask the user to run: `sudo darwin-rebuild switch --flake /etc/nix-darwin`, then in a **fresh shell**:

```bash
echo "${PASEO_HOST:?unset}"   # expect tcp://paseo.aj-cloud.cc:443?ssl=true
paseo ls                       # expect the agent list from paseo.aj-cloud.cc
```

Never verify the password by printing it; `paseo ls` succeeding IS the password check.

---

### Task 5: Server and pixelbook notes (no code in this plan)

- **nix-server:** no change required — it simply does not import `homeModules.paseo-remote`, so its agents keep the local socket. If a shared import list ever pulls the module in there, set `nix-components.paseo.remoteHost = null` for that host. (This refines the spec, which assumed an explicit null.)
- **nix-pixelbook:** when its Infisical project exists, set `PASEO_PASSWORD` there and import `homeModules.paseo-remote` the same way as Task 4 Step 2.
