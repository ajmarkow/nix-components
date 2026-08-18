# Remote Paseo Access for Off-Server Agents — Design

Date: 2026-08-18
Status: approved (design), pending implementation

## Problem

The paseo daemon runs on one host (paseo.aj-cloud.cc). Agents on other
hosts (Mac, pixelbook, future machines) cannot run `paseo` commands: the
CLI targets the local socket by default, and remote targeting requires a
password. Passing the password inline (`--host tcp://...?password=...`)
leaks it into shell history, process lists, and agent transcripts.

## Facts the design relies on

- The paseo CLI resolves the daemon host from `--host`, then the
  `PASEO_HOST` env var (`dist/utils/client.js`,
  `resolveDaemonHostCandidates`).
- It resolves the password from the host URI, then the `PASEO_PASSWORD`
  env var. So host and password can travel separately, and the password
  never has to appear on a command line.
- nix-components' `modules/zsh.nix` already evals
  `infisical export --format=dotenv-export` (project
  `0bd4a4d8-f58e-4bad-9d65-c16ee9aeae7e`, env `prod`) at every
  interactive shell init, on every host, bootstrapped from
  `~/.config/infisical-token`. Claude Code agent shells snapshot this
  profile, so they inherit the same env.
- The daemon endpoint is `tcp://paseo.aj-cloud.cc:443?ssl=true`
  (reverse-proxied TLS on 443; port 6767 is not externally open).

## Design

Split config from secret. No wrapper scripts, no new secret framework.

### 1. Secret: `PASEO_PASSWORD` in Infisical (manual, one-time)

Add `PASEO_PASSWORD` to the prod env of the existing Infisical project.
Distribution is automatic via the existing shell-init export. Agents and
tooling never store or print the value.

### 2. Config: `PASEO_HOST` via a nix-components module option

New home-manager module `modules/paseo-remote.nix` in nix-components:

- Declares `nix-components.paseo.remoteHost` (`types.nullOr types.str`), default
  `"tcp://paseo.aj-cloud.cc:443?ssl=true"`.
- When non-null, appends `export PASEO_HOST=<value>` to
  `programs.zsh.initContent`, ordered after the Infisical eval so the
  nix-declared value always wins.
- The paseo server host (nix-server) sets `nix-components.paseo.remoteHost = null`
  so on-server agents keep the local socket.

This is the repo's first `mkOption` — keep it minimal (one option, one
module, imported wherever zsh.nix already is).

### 3. Agent guidance: update `modules/lib/claude-md-content.nix`

Amend the existing paseo section:

- Plain `paseo ls / send / run ...` works from any host; env vars handle
  remote targeting. No `--host` needed.
- NEVER put `password=` in a `--host` URI, and never echo
  `PASEO_PASSWORD`.
- If paseo reports unauthorized or unreachable: check
  `infisical login` / `~/.config/infisical-token`, then open a fresh
  shell. Do not hunt for the password.
- Headless/non-zsh contexts (cron, launchd) use the nix-built
  `paseo-headless` wrapper (shipped by `modules/paseo-remote.nix`), which
  sets PASEO_HOST/PASEO_PASSWORD internally and execs paseo. Agents never
  compose infisical commands; the raw fetch exists only inside the
  reviewed wrapper. (Revised during implementation review from an inline
  command example, which would have taught agents a reusable
  secret-fetching pattern.)

### Secrets

- `PASEO_PASSWORD` — Required. Daemon password for paseo.aj-cloud.cc,
  stored only in Infisical prod and in the daemon's own config.

## Rotation SOP

1. Change the daemon password in nix-server's paseo configuration and
   deploy via CI.
2. Update `PASEO_PASSWORD` in Infisical prod to match.
3. New shells pick it up automatically; long-lived shells need a restart
   or re-source. No client-host redeploys.

## New-host bootstrap SOP

1. Deploy the host's nix config (pulls in nix-components zsh module and
   `paseo-remote.nix`).
2. Place the Infisical machine token at `~/.config/infisical-token`
   (or `infisical login`).
3. Open a shell, run `paseo ls` — it should list agents on
   paseo.aj-cloud.cc.

## Failure modes

- Password missing: the existing Infisical loader prints a visible
  stderr warning at shell init.
- Password rotated but Infisical stale: paseo auth error; guidance in
  CLAUDE.md points at the rotation SOP.
- Paseo server host: unaffected (`remoteHost = null`, local socket).

## Verification

On this Mac after deploy: fresh shell, `echo ${PASEO_HOST:?unset}` shows
the URI (never test the password this way), and bare `paseo ls` lists
the remote agents. On the server: `paseo status` still shows the local
daemon.

## Files to change

- `nix-components/modules/paseo-remote.nix` (new)
- `nix-components/modules/zsh.nix` or the module list that imports it
  (wire-up only, if needed)
- `nix-components/modules/lib/claude-md-content.nix` (paseo section)
- `nix-server` host config: `nix-components.paseo.remoteHost = null` (separate repo,
  after the nix-components bump)
