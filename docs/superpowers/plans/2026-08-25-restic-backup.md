# Restic Backup Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `homeModules.restic` module to `nix-components` that configures restic backups to a shared Backblaze B2 bucket, with one restic repository per host.

**Architecture:** The module is a thin wrapper. home-manager already ships `services.restic.backups.<name>`, which on Linux creates the systemd user service, the timer, repository auto-creation, `forget --prune`, exclude handling, and a `restic-<name>` restore wrapper. This module implements none of that. It exposes a small `services.resticBackup` namespace, encodes the shared B2 repository convention and secret file paths, and delegates everything else to `services.restic.backups.b2`.

**Tech Stack:** Nix, flake-parts, home-manager (`release-26.05`), restic, Backblaze B2.

**Spec:** `docs/superpowers/specs/2026-08-25-restic-backup-design.md`

---

## Background the implementer needs

Read this before starting. It explains decisions that look arbitrary otherwise.

**This repo exports home-manager modules only.** `home-modules.nix` reads every top-level `modules/*.nix` file and exports it as `flake.homeModules.<basename>`. Creating `modules/restic.nix` is therefore enough to export it. Do **not** edit `flake.nix` or `home-modules.nix` to register the module.

**Linux only.** Upstream's restic module marks `exclude`, `initialize`, `pruneOpts`, `timerConfig`, `runCheck`, and several others as `readOnly` when `!pkgs.stdenv.hostPlatform.isLinux`, pending launchd support (home-manager issue #7924). On macOS it creates the wrapper script and nothing else — no service, no timer. The target hosts are `nix-server` and `nix-pixelbook`, both Linux. `nix-mac` uses a different backup tool and is out of scope.

**`environmentFile` and `passwordFile` must be typed `lib.types.str`, never `lib.types.path`.** A `path`-typed option makes Nix copy the file into the store at evaluation time. These files hold B2 credentials and the repository password. Typing them as `path` would both leak secrets into a world-readable store and fail evaluation on any machine where the file is absent. Upstream types them `nullOr str` for the same reason.

**Two secret files, not one.** Upstream asserts exactly one of `passwordFile` or `passwordCommand` is set, so the repository password cannot be supplied through `environmentFile`.

**Never run `home-manager switch` or any rebuild command in this repo.** It is a management server holding configs for several hosts. Verification is `nix flake check`; deployment is GitHub Actions CI.

**Verified upstream facts** (home-manager `release-26.05`, `modules/services/restic.nix`, byte-identical to `master`):

- The service and the timer are both named `restic-backups-<name>`, so with backup name `b2` they are `restic-backups-b2`.
- `Service.Environment` is a list of `KEY=value` strings including `RESTIC_REPOSITORY=<repository>`.
- `Service.EnvironmentFile` is set to `environmentFile` verbatim when non-null.
- `timerConfig` defaults to `{ OnCalendar = "daily"; Persistent = true; }`.
- `createWrapper` defaults to `true`, putting `restic-b2` on `PATH`.
- `home-manager.lib.homeManagerConfiguration` takes `{ pkgs, modules, lib ? pkgs.lib, check ? true, extraSpecialArgs ? {}, minimal ? false }` and returns an attrset with `.config`.
- `"26.05"` is a valid `home.stateVersion` enum value.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `flake.nix` | Modify (`inputs` block, after line 54) | Add the `home-manager` input, following `nixpkgs` |
| `flake.lock` | Regenerated | Adds `home-manager` node only; `nixpkgs` rev must not move |
| `modules/restic.nix` | Create | The whole module: options, assertions, delegation |
| `tests/restic-module.nix` | Create | The evaluation check derivation, kept out of `per-system.nix` |
| `per-system.nix` | Modify (`checks` at line 25) | Wires the check in, Linux only |
| `README.md` | Modify (module table, line 27-41) | One row plus a usage section |

---

### Task 1: Add the home-manager flake input

The eval check in Task 2 needs `home-manager.lib.homeManagerConfiguration`. The repo has no home-manager input today.

**Files:**
- Modify: `flake.nix:53-54`
- Regenerated: `flake.lock`

- [ ] **Step 1: Record the current nixpkgs revision**

This repo shares its `nixpkgs` pin with `nix-mac`, `nix-server`, and `nix-pixelbook`. Adding an input must not move it. Capture the current value so Step 4 can prove it did not change.

```bash
jq -r '.nodes.nixpkgs.locked.rev' /Users/ajmarkow/Documents/nix-components/flake.lock | tee /tmp/nixpkgs-rev-before
```

Expected: a 40-character git SHA printed once.

- [ ] **Step 2: Add the input**

In `flake.nix`, inside the `inputs` block, immediately after the `backlog-md` lines (currently lines 53-54) and before the closing `};` of `inputs`:

```nix
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
```

`release-26.05` matches the `nixos-26.05` nixpkgs pin. The `follows` keeps a single nixpkgs in the closure.

- [ ] **Step 3: Lock the new input**

`nix flake lock` adds missing inputs without updating existing ones. Do **not** run `nix flake update`.

```bash
nix flake lock /Users/ajmarkow/Documents/nix-components
```

Expected: output mentioning `added input 'home-manager'` (and its transitive inputs). No line mentioning `updated input 'nixpkgs'`.

- [ ] **Step 4: Verify the nixpkgs pin did not move**

```bash
jq -r '.nodes.nixpkgs.locked.rev' /Users/ajmarkow/Documents/nix-components/flake.lock > /tmp/nixpkgs-rev-after
diff /tmp/nixpkgs-rev-before /tmp/nixpkgs-rev-after && echo "PIN UNCHANGED"
```

Expected: `PIN UNCHANGED`.

If it differs, **stop**. Revert `flake.lock` with `rtk git -C /Users/ajmarkow/Documents/nix-components checkout flake.lock` and report the problem — the shared pin must not be bumped from this repo.

- [ ] **Step 5: Verify the flake still evaluates**

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: exits 0, no error output. The existing `diff-viewer` check is evaluated but not built.

- [ ] **Step 6: Commit**

```bash
rtk git -C /Users/ajmarkow/Documents/nix-components add flake.nix flake.lock
rtk git -C /Users/ajmarkow/Documents/nix-components diff --staged
rtk git -C /Users/ajmarkow/Documents/nix-components commit -m "build(flake): add home-manager input for module eval checks"
```

Show the staged diff to the user and wait for approval before running the commit — this repo requires it.

---

### Task 2: Write the failing evaluation check

`nix flake check --no-build` evaluates flake outputs shallowly and will not instantiate a home-manager module. This check builds a throwaway `homeConfiguration` so a typo or bad option reference fails in CI instead of on the server.

The check is Linux-only. The module asserts on non-Linux, so running it on `x86_64-darwin` or `aarch64-darwin` would fail by design.

**Files:**
- Modify: `per-system.nix:25-29`
- Create: `tests/restic-module.nix`

- [ ] **Step 1: Write the check**

Replace the single `checks.diff-viewer = ...` attribute (currently lines 25-29) with a `checks` attrset. The existing `diff-viewer` derivation is unchanged; it just moves inside the braces.

```nix
      checks = {
        diff-viewer = pkgs.runCommand "diff-viewer-tests" { } ''
          cd ${./.}
          PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 -m unittest tests/test_diff_viewer_header.py
          touch "$out"
        '';
      }
      # The restic module targets Linux only: upstream home-manager creates no
      # service and no timer on other platforms, so the module asserts on them.
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        restic-module = import ./tests/restic-module.nix {
          inherit lib pkgs;
          homeManagerLib = inputs.home-manager.lib;
          resticModule = ./modules/restic.nix;
        };
      };
```

`lib` and `inputs` are already in scope — `per-system.nix` opens with `{ lib, inputs, ... }:` and the `perSystem` function closes over both.

- [ ] **Step 2: Write the check derivation**

The check lives in its own file so `per-system.nix` stays a wiring file.

Create `tests/restic-module.nix`:

```nix
# Evaluation check for modules/restic.nix.
#
# `nix flake check --no-build` does not instantiate home-manager modules, so
# this builds a throwaway homeConfiguration and forces the values the module is
# responsible for. Linux only -- see per-system.nix.
{
  lib,
  pkgs,
  homeManagerLib,
  resticModule,
}:

let
  baseHome = {
    home = {
      username = "testuser";
      homeDirectory = "/home/testuser";
      stateVersion = "26.05";
    };
  };

  mkConfig =
    resticBackup:
    (homeManagerLib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        resticModule
        baseHome
        { services.resticBackup = resticBackup; }
      ];
    }).config;

  failedAssertions =
    cfg: map (a: a.message) (lib.filter (a: !a.assertion) cfg.assertions);

  # A fully specified host. Must produce a working unit and zero assertions.
  good = mkConfig {
    enable = true;
    hostName = "test-host";
    bucket = "test-bucket";
    paths = [ "/home/testuser/documents" ];
    exclude = [ "**/node_modules" ];
  };

  goodFailures = failedAssertions good;

  service = good.systemd.user.services."restic-backups-b2";
  timer = good.systemd.user.timers."restic-backups-b2";

  # Only the repository entry, so the derivation does not gain a store
  # reference to openssh via the PATH= entry that upstream also emits.
  repoEnv = lib.filter (lib.hasPrefix "RESTIC_REPOSITORY=") service.Service.Environment;
in

if goodFailures != [ ] then
  throw "restic module rejected a valid configuration: ${lib.concatStringsSep "; " goodFailures}"
else
  pkgs.runCommand "restic-module-eval" { } ''
    test '${lib.concatStringsSep "," repoEnv}' = 'RESTIC_REPOSITORY=b2:test-bucket:test-host'
    test '${service.Service.EnvironmentFile}' = '/etc/nixos/secrets/restic.env'
    test '${timer.Timer.OnCalendar}' = 'daily'
    touch "$out"
  ''
```

Do not interpolate `timer.Timer.Persistent` — it is a bool, and `${}` on a bool is an evaluation error.

- [ ] **Step 3: Run the check to verify it fails**

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: FAIL. `modules/restic.nix` does not exist yet, so evaluation errors with something like `path '/nix/store/.../modules/restic.nix' does not exist` or `getting status of .../modules/restic.nix: No such file or directory`.

This is the red state. Do not commit here — Task 3 commits both files together once green.

---

### Task 3: Implement the module

**Files:**
- Create: `modules/restic.nix`

- [ ] **Step 1: Write the module**

Create `modules/restic.nix`:

```nix
# Restic backups to a shared Backblaze B2 bucket, one repository per host.
#
# This is a thin wrapper around home-manager's services.restic. Upstream owns
# the systemd service, the timer, repository initialization, forget/prune, and
# the restic-b2 restore wrapper. This module only encodes the shared B2
# convention and the secret file locations.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.resticBackup;
in
{
  options.services.resticBackup = {
    enable = lib.mkEnableOption "restic backups to the shared Backblaze B2 bucket";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "nix-server";
      description = ''
        Subdirectory of the shared bucket this host backs up into, giving it
        its own restic repository at `b2:<bucket>:<hostName>`. Hosts therefore
        never contend for one repository lock, at the cost of no deduplication
        between hosts.

        Set explicitly rather than derived from the runtime hostname: a host
        that renames itself would otherwise silently start a new repository
        and a fresh full backup.
      '';
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "aj-backups";
      description = ''
        Backblaze B2 bucket shared by every host. Not a secret, so it lives in
        Nix rather than in the environment file.
      '';
    };

    paths = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [ "/home/aj/documents" ];
      description = "Paths to back up.";
    };

    exclude = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [ "**/node_modules" ];
      description = ''
        Patterns to exclude. See
        <https://restic.readthedocs.io/en/stable/040_backup.html#excluding-files>.
      '';
    };

    timerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      description = ''
        Passed through to the systemd timer. `Persistent` makes a host that was
        powered off at the scheduled time run the backup after it next boots.
        `RandomizedDelaySec` keeps several hosts from hitting B2 at the same
        instant. See {manpage}`systemd.timer(5)`.
      '';
    };

    pruneOpts = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
      description = ''
        Policy for `restic forget --prune`, which upstream runs in the same
        service invocation as the backup. Roughly 17 snapshots are retained.
      '';
    };

    environmentFile = lib.mkOption {
      # Deliberately str, not path: a path-typed option would copy this file
      # into the world-readable Nix store at evaluation time, and would fail to
      # evaluate on any machine where the file is absent.
      type = lib.types.str;
      default = "/etc/nixos/secrets/restic.env";
      description = ''
        File holding `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY`, in
        {manpage}`systemd.exec(5)` EnvironmentFile format. Provisioned out of
        band. Never generated by Nix, never committed.
      '';
    };

    passwordFile = lib.mkOption {
      # str, not path -- same reason as environmentFile above.
      type = lib.types.str;
      default = "/etc/nixos/secrets/restic-password";
      description = ''
        File holding the restic repository password. A separate file from
        `environmentFile` because upstream asserts that exactly one of
        `passwordFile` or `passwordCommand` is set, so the password cannot be
        supplied as an environment variable. Provisioned out of band.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = ''
          services.resticBackup supports Linux only. On other platforms
          home-manager's services.restic creates the restic-b2 wrapper script
          and nothing else -- no service, no timer -- pending launchd support
          (home-manager issue #7924). Enabling it on macOS would silently back
          nothing up.
        '';
      }
      {
        assertion = cfg.hostName != "";
        message = ''
          services.resticBackup.hostName must be set. It names this host's
          subdirectory in the shared B2 bucket.
        '';
      }
      {
        assertion = cfg.bucket != "";
        message = ''
          services.resticBackup.bucket must be set to the shared Backblaze B2
          bucket name.
        '';
      }
      {
        assertion = cfg.paths != [ ];
        message = ''
          services.resticBackup.paths must list at least one path to back up.
        '';
      }
    ];

    services.restic = {
      enable = true;

      # Named "b2" rather than after the host so the restore wrapper is always
      # `restic-b2`, and so hosts have a stable option path to reach through on
      # for upstream options this module does not re-export, for example
      # `services.restic.backups.b2.runCheck = true`.
      backups.b2 = {
        repository = "b2:${cfg.bucket}:${cfg.hostName}";
        initialize = true;
        inherit (cfg)
          paths
          exclude
          timerConfig
          pruneOpts
          environmentFile
          passwordFile
          ;
      };
    };
  };
}
```

- [ ] **Step 2: Run the check to verify it passes**

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: exits 0, no error output.

Troubleshooting:

- Fails on `RESTIC_REPOSITORY` — the repository string is wrong.
- `The option 'services.restic...' does not exist` — the resolved home-manager is older than the module. Confirm the input locked to `release-26.05`.
- `restic module rejected a valid configuration: <message>` where the message is not one of the four written in Step 1 — home-manager contributed an assertion of its own about the throwaway test config. Fix the test config in `tests/restic-module.nix` to satisfy it; do not weaken the module.

- [ ] **Step 3: Format**

```bash
nix fmt /Users/ajmarkow/Documents/nix-components
rtk git -C /Users/ajmarkow/Documents/nix-components diff --stat
```

Expected: `nixfmt-rfc-style` reformats nothing, or only cosmetic whitespace in the new files.

- [ ] **Step 4: Re-run the check after formatting**

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
rtk git -C /Users/ajmarkow/Documents/nix-components add modules/restic.nix tests/restic-module.nix per-system.nix
rtk git -C /Users/ajmarkow/Documents/nix-components diff --staged
rtk git -C /Users/ajmarkow/Documents/nix-components commit -m "feat(restic): add restic backup module for shared B2 bucket"
```

Show the staged diff to the user and wait for approval before committing.

---

### Task 4: Cover the assertions

Task 3's check only proves a valid config works. The assertions are the part that stops a half-configured host from silently backing nothing up, so they need their own coverage.

**Files:**
- Modify: `tests/restic-module.nix`

- [ ] **Step 1: Write the failing test**

In `tests/restic-module.nix`, add these bindings to the `let` block, immediately after `goodFailures`:

```nix
  # Each of these omits exactly one required setting and must be rejected.
  badCases = {
    missingHostName = {
      enable = true;
      bucket = "test-bucket";
      paths = [ "/home/testuser/documents" ];
    };
    missingBucket = {
      enable = true;
      hostName = "test-host";
      paths = [ "/home/testuser/documents" ];
    };
    missingPaths = {
      enable = true;
      hostName = "test-host";
      bucket = "test-bucket";
    };
  };

  unrejected = lib.attrNames (
    lib.filterAttrs (_: c: failedAssertions (mkConfig c) == [ ]) badCases
  );

  # An unset module must stay inert: no assertions, no units.
  disabled = mkConfig { enable = false; };
  disabledFailures = failedAssertions disabled;
  disabledHasUnit = disabled.systemd.user.services ? "restic-backups-b2";
```

Then replace the final `if goodFailures != [ ] then ... else ...` expression with:

```nix
if goodFailures != [ ] then
  throw "restic module rejected a valid configuration: ${lib.concatStringsSep "; " goodFailures}"
else if unrejected != [ ] then
  throw "restic module accepted invalid configurations: ${lib.concatStringsSep ", " unrejected}"
else if disabledFailures != [ ] then
  throw "restic module asserted while disabled: ${lib.concatStringsSep "; " disabledFailures}"
else if disabledHasUnit then
  throw "restic module created restic-backups-b2 while disabled"
else
  pkgs.runCommand "restic-module-eval" { } ''
    test '${lib.concatStringsSep "," repoEnv}' = 'RESTIC_REPOSITORY=b2:test-bucket:test-host'
    test '${service.Service.EnvironmentFile}' = '/etc/nixos/secrets/restic.env'
    test '${timer.Timer.OnCalendar}' = 'daily'
    touch "$out"
  ''
```

- [ ] **Step 2: Run the check to confirm it passes**

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: exits 0. The assertions written in Task 3 already satisfy these cases.

- [ ] **Step 3: Prove the test actually detects a regression**

A test that has never failed is not yet a test. Temporarily weaken one assertion in `modules/restic.nix` — change

```nix
        assertion = cfg.hostName != "";
```

to

```nix
        assertion = true;
```

Then run:

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
```

Expected: FAIL with `restic module accepted invalid configurations: missingHostName`.

- [ ] **Step 4: Restore the assertion**

Change `assertion = true;` back to `assertion = cfg.hostName != "";`, then:

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
rtk git -C /Users/ajmarkow/Documents/nix-components diff modules/restic.nix
```

Expected: check exits 0, and `git diff` on `modules/restic.nix` is empty — proving the file is back to its committed state.

- [ ] **Step 5: Commit**

```bash
nix fmt /Users/ajmarkow/Documents/nix-components
rtk git -C /Users/ajmarkow/Documents/nix-components add tests/restic-module.nix
rtk git -C /Users/ajmarkow/Documents/nix-components diff --staged
rtk git -C /Users/ajmarkow/Documents/nix-components commit -m "test(restic): cover required-option assertions and disabled state"
```

Show the staged diff to the user and wait for approval before committing.

---

### Task 5: Document the module

**Files:**
- Modify: `README.md:27-41` (module table) and the section following it

- [ ] **Step 1: Add the table row**

In the module table in `README.md`, insert this row in alphabetical position — between the `packages.nix` row and the `starship.nix` row:

```markdown
| `restic.nix` | Restic backups to a shared Backblaze B2 bucket, one repository per host. Linux only |
```

- [ ] **Step 2: Add a usage section**

Insert this immediately after the paragraph about `modules/lib/` (currently line 42), before the `## Packages` heading:

````markdown
### `restic.nix`

Wraps home-manager's `services.restic`. Each host backs up to its own
subdirectory of one shared B2 bucket, so hosts never contend for a repository
lock.

```nix
imports = [ inputs.nix-components.homeModules.restic ];

services.resticBackup = {
  enable   = true;
  hostName = "nix-server";          # -> b2:aj-backups:nix-server
  bucket   = "aj-backups";
  paths    = [ "/home/aj/documents" ];
  exclude  = [ "**/node_modules" ];
};
```

Defaults: daily timer with `Persistent = true`, repository auto-created on
first run, and `restic forget --prune` after each backup keeping 7 daily,
4 weekly, and 6 monthly snapshots.

Options this module does not re-export are reachable directly, because it
writes into the same option tree:

```nix
services.restic.backups.b2.runCheck = true;
```

Restores need no manual environment setup — `createWrapper` puts `restic-b2`
on `PATH` with the repository and credentials already set:

```bash
restic-b2 snapshots
restic-b2 restore latest --target /tmp/restore
```

**Linux only.** On macOS upstream creates the wrapper script and nothing else,
so the module asserts rather than pretending to be scheduled. See
home-manager issue #7924.

**Required secrets**, provisioned out of band on each host. Never generated by
Nix, never committed:

| File | Contents | Mode |
|---|---|---|
| `/etc/nixos/secrets/restic.env` | `B2_ACCOUNT_ID=...` and `B2_ACCOUNT_KEY=...` | `0400` |
| `/etc/nixos/secrets/restic-password` | The repository password, alone on one line | `0400` |

Both paths are configurable via `services.resticBackup.environmentFile` and
`services.resticBackup.passwordFile`.
````

- [ ] **Step 3: Verify the README renders and nothing else broke**

```bash
nix flake check --no-build /Users/ajmarkow/Documents/nix-components
rtk git -C /Users/ajmarkow/Documents/nix-components diff --stat README.md
```

Expected: check exits 0; the diff touches only `README.md`.

- [ ] **Step 4: Commit**

```bash
rtk git -C /Users/ajmarkow/Documents/nix-components add README.md
rtk git -C /Users/ajmarkow/Documents/nix-components diff --staged
rtk git -C /Users/ajmarkow/Documents/nix-components commit -m "docs(restic): document the restic backup module"
```

Show the staged diff to the user and wait for approval before committing.

---

### Task 6: Final verification

**Files:** none modified unless a linter flags something.

- [ ] **Step 1: Lint**

```bash
nix develop /Users/ajmarkow/Documents/nix-components --command statix check /Users/ajmarkow/Documents/nix-components
nix develop /Users/ajmarkow/Documents/nix-components --command deadnix /Users/ajmarkow/Documents/nix-components/modules/restic.nix /Users/ajmarkow/Documents/nix-components/tests/restic-module.nix /Users/ajmarkow/Documents/nix-components/per-system.nix
```

Expected: no findings on the new files. `deadnix` may flag the unused `config` argument in `modules/restic.nix` — it is used, via `config.services.resticBackup`, so that would be a false positive. Fix any genuine finding and re-run Step 2.

- [ ] **Step 2: Full check, including building the check derivation**

Unlike `--no-build`, this actually builds `restic-module-eval` and runs its `test` assertions. It stays cheap because the check touches only environment strings, never `ExecStart`, so restic itself is never built.

```bash
nix flake check /Users/ajmarkow/Documents/nix-components
```

Expected: exits 0.

Do not read success from a pipe's exit code. Run this command bare and check its own exit status.

- [ ] **Step 3: Confirm the module is exported**

`home-modules.nix` wraps each module in a function, so `homeModules.restic` is a lambda, not an attrset. Test for a function — `?` on a lambda is an evaluation error.

```bash
nix eval --raw /Users/ajmarkow/Documents/nix-components#homeModules.restic --apply 'm: if builtins.isFunction m then "exported" else "MISSING"'
```

Expected: `exported`.

- [ ] **Step 4: Confirm the tree is clean**

```bash
rtk git -C /Users/ajmarkow/Documents/nix-components status --short
```

Expected: empty output. Anything listed is uncommitted work from an earlier task.

- [ ] **Step 5: Report**

Report to the user:
- the commits made,
- that `nix flake check` passes,
- that nothing is deployed yet — CI deploys on push, and the two secret files must exist on `nix-server` and `nix-pixelbook` before the first backup run will succeed.

Do not push unless the user asks.

---

## Out of scope

Confirmed during design. Do not implement these:

- macOS support — blocked upstream on home-manager #7924.
- A NixOS system-level module for root-owned paths.
- `restic check` runs — reachable by hosts via `services.restic.backups.b2.runCheck`.
- Backup failure alerting.
- Multiple named backup sets per host — a host needing a second set defines `services.restic.backups.<other>` directly.
- Creating the B2 bucket or application key.
- Placing the secret files on hosts.
