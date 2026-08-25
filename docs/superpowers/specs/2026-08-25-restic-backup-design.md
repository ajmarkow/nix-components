# Restic backup module — design

Date: 2026-08-25

## Goal

Give `nix-components` a reusable home-manager module that sets up restic backups
to a shared Backblaze B2 bucket. Each host writes to its own subdirectory of that
bucket. Hosts configure their own paths, excludes, and schedule.

Target hosts: `nix-server` and `nix-pixelbook`. Both are Linux.

`nix-mac` is out of scope. It uses a different backup tool.

## Key decision: wrap upstream, do not reimplement

home-manager already ships `services.restic.backups.<name>`
(`modules/services/restic.nix`). On Linux it creates:

- a `restic-backups-<name>` systemd user service
- a systemd user timer, configured through `timerConfig`
- repository auto-creation through `initialize`
- `restic forget --prune` after the backup, through `pruneOpts`
- exclude-pattern handling through `exclude`
- a `restic-<name>` wrapper script on `PATH`, through `createWrapper`, with all
  repository environment variables preset

That is the whole feature. This module therefore does **not** implement backup
logic, scheduling, or pruning. It only encodes the shared B2 convention and the
secret file locations, then delegates.

On non-Linux platforms the upstream module creates the wrapper script and
nothing else — no service, no timer. Options `exclude`, `initialize`,
`pruneOpts`, `timerConfig`, `runCheck`, `extraBackupArgs`,
`backupPrepareCommand`, `backupCleanupCommand`, and `dynamicFilesFrom` are all
marked `readOnly` off Linux, pending upstream launchd support
(home-manager issue #7924). This is the reason `nix-mac` is out of scope, and
the reason this module asserts on non-Linux rather than degrading quietly.

Verified against home-manager `release-26.05`, which is byte-identical to
`master` for this file at the time of writing.

## Module

New file `modules/restic.nix`. The existing `home-modules.nix` scanner
auto-exports every top-level `modules/*.nix` file, so it becomes
`homeModules.restic` with no change to `flake.nix` or `home-modules.nix`. The
module needs no special `_module.args`.

### Host-facing options

Namespace `services.resticBackup`, chosen so it does not collide with the
upstream `services.restic` tree that it configures.

| Option | Type | Default |
|---|---|---|
| `enable` | bool | `false` |
| `hostName` | str | `""` — must be set when enabled |
| `bucket` | str | `""` — must be set when enabled |
| `paths` | list of str | `[]` — must be non-empty when enabled |
| `exclude` | list of str | `[]` |
| `timerConfig` | attrs | `{ OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "1h"; }` |
| `pruneOpts` | list of str | `[ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ]` |
| `environmentFile` | str | `/etc/nixos/secrets/restic.env` |
| `passwordFile` | str | `/etc/nixos/secrets/restic-password` |

Example host usage:

```nix
services.resticBackup = {
  enable   = true;
  hostName = "nix-server";
  bucket   = "aj-backups";
  paths    = [ "/home/aj/documents" ];
  exclude  = [ "**/node_modules" ];
};
```

### What it sets

```nix
services.restic.enable = true;
services.restic.backups.b2 = {
  repository      = "b2:${cfg.bucket}:${cfg.hostName}";
  environmentFile = cfg.environmentFile;
  passwordFile    = cfg.passwordFile;
  inherit (cfg) paths exclude timerConfig pruneOpts;
  initialize      = true;
};
```

The backup is named `b2`, a fixed literal rather than the host name. This keeps
the wrapper command stable at `restic-b2` on every host, and gives hosts a
stable option path to reach through on.

### No escape hatch

`services.resticBackup` deliberately does not re-export every upstream option,
and does not provide an `extraConfig` passthrough. Both are unnecessary: the
module writes into the same option tree, so a host that wants an unexposed
upstream option sets it directly, and the module system merges the two
definitions.

```nix
services.restic.backups.b2.runCheck = true;
```

### Assertions

Fire when `enable` is true:

- `hostName` is not empty
- `bucket` is not empty
- `paths` is not empty
- `pkgs.stdenv.hostPlatform.isLinux`

The platform assertion carries a message naming home-manager issue #7924 and
pointing at the missing launchd support, so importing on a mac fails at build
with an explanation rather than installing a wrapper that never runs.

## Repository layout

`b2:<bucket>:<hostName>` — one shared bucket, one restic repository per host
under its own prefix.

Consequence: no deduplication between hosts. Accepted. The alternative, a single
repository shared by all hosts, would dedupe but introduces lock contention
between concurrent backups and couples every host to one password.

## Secrets

Both files are provisioned out of band. Nix never generates them. Neither is
ever committed. This follows the `agent-dropbox.nix` precedent of an
out-of-store secrets file.

Two files are required, not one, because the upstream module asserts that
exactly one of `passwordFile` or `passwordCommand` is set. `RESTIC_PASSWORD`
therefore cannot be supplied through `environmentFile`.

| Secret | File | Required |
|---|---|---|
| `B2_ACCOUNT_ID` | `/etc/nixos/secrets/restic.env` | Required |
| `B2_ACCOUNT_KEY` | `/etc/nixos/secrets/restic.env` | Required |
| restic repository password | `/etc/nixos/secrets/restic-password` | Required |

The bucket name is not a secret and stays in Nix.

A missing secrets file makes the systemd service fail. That is intended. A
backup job that quietly does nothing is worse than one that fails visibly, so
this module does not copy `agent-dropbox.nix`'s silent-skip behaviour.

## Retention

Default `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`, roughly 17 retained
snapshots. `restic forget --prune` runs in the same service invocation as the
backup, which is upstream behaviour when `pruneOpts` is non-empty. No second
timer.

## Schedule

Default `OnCalendar = "daily"` with `Persistent = true` and
`RandomizedDelaySec = "1h"`. `Persistent` makes a host that was powered off at
the scheduled time run the backup after it next boots.

## Restore

`createWrapper` defaults to true upstream, so `restic-b2` lands on `PATH` with
the repository, password file, and B2 credentials already set. Restores and
snapshot listing need no manual environment setup:

```
restic-b2 snapshots
restic-b2 restore latest --target /tmp/restore
```

## Verification

`nix flake check --no-build` evaluates flake outputs shallowly. It does not
instantiate a home-manager module, so it cannot catch a typo or a bad option
reference inside `modules/restic.nix`.

The repo has no `home-manager` flake input today. This design adds one, plus a
`checks.<system>` entry that evaluates a throwaway `homeConfiguration` importing
`homeModules.restic` with the module enabled. The check asserts the
`restic-backups-b2` systemd user unit is generated.

The new input also makes eval checks cheap for every future module in this repo,
which is the main reason to accept the cost.

`home-manager` follows the repo's existing `nixpkgs` input. Per repo policy the
`nixpkgs` pin is shared across `nix-components`, `nix-mac`, `nix-server`, and
`nix-pixelbook`, and is not bumped here.

## Documentation

Add one row to the module table in `README.md`. No change to `modules/lib/` —
this module has no prose shared with another module.

## Out of scope

- macOS support. Blocked upstream on home-manager #7924.
- A NixOS system-level module for backing up root-owned paths.
- `restic check` runs. Available to hosts through
  `services.restic.backups.b2.runCheck` if wanted.
- Backup failure alerting.
- Multiple named backup sets per host. One set per host is enough for both
  target hosts; a host needing a second set can define
  `services.restic.backups.<other>` directly.
