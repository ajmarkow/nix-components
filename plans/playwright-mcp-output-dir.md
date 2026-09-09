# Fix: MCP servers writing outside the mcpm sandbox's writable paths

Primary fix is playwright (actively failing). Step 2 redirects mcp-remote's
config dir for the same reason, before it bites.

## Symptom

Playwright MCP calls fail on nixos-host with:

```
Error: EROFS: read-only file system, open '/var/lib/paseo/.playwright-mcp/page-2026-09-09T15-13-35-014Z.yml'
```

The journal shows this recurring, not a one-off:

```bash
journalctl --user-unit mcpm-active-profile --since "7 days ago" | grep EROFS
```

## Root cause

Three facts combine:

1. `playwright-mcp` runs as a child of the shared `mcpm-active-profile` user
   service, not per-session. Confirmed: PID of `playwright-mcp-internal/cli.js`
   has PPID = the `mcpm profile run --http active` process, cgroup
   `.../mcpm-active-profile.service`.
2. That unit sets `ProtectHome = "read-only"` (`modules/mcp.nix:174`). Its
   `ReadWritePaths` cover only `%h/.config/mcpm`, `%h/.cache/mcpm`, and the
   obsidian vault. Everything else under `$HOME` is a read-only bind mount.
3. `playwright-mcp` defaults its output directory to `<cwd>/.playwright-mcp`.
   The service inherits cwd `$HOME`, so that resolves to
   `/var/lib/paseo/.playwright-mcp` — inside the read-only region.

Any write to the output dir fails: spilled snapshots (`page-*.yml`, written when
a snapshot is too large to return inline), screenshots, traces, PDFs.

Not the cause: no missing browser (`PLAYWRIGHT_BROWSERS_PATH` points at a store
path, read-only is fine), no permission problem on the `paseo` user (the
directory is `paseo`-owned and writable outside the unit's namespace).

## Fix

Point the server at a directory that is already read-write inside the unit's
namespace. `%h/.cache/mcpm` is bind-mounted read-write, so a subdirectory of it
needs no new `ReadWritePaths` entry and no `.keep` placeholder — the server
creates it on first use.

### 1. `modules/lib/mcp.nix` — catalog entry

```nix
playwright = {
  profiles = [ "core" ];
  command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
  args = [
    "--headless"
    "--isolated"
    # Default output dir is <cwd>/.playwright-mcp, and the server inherits
    # cwd $HOME from mcpm-active-profile, whose ProtectHome=read-only makes
    # that path unwritable -- every screenshot and spilled snapshot failed
    # with EROFS. This subtree is already in the unit's ReadWritePaths.
    "--output-dir"
    "${homeDirectory}/.cache/mcpm/playwright"
  ];
};
```

`homeDirectory` is already a parameter of this file and is how `cacheEnv` builds
its paths, so the value lands in `servers.json` as an absolute path. No shell
expansion is involved — mcpm resolves `${VAR}` references in `env` only.

This is the same bug class the `cacheEnv` comment at the top of the file already
describes: a child server defaulting a write path to `$HOME`, which the service
sandboxes read-only. npx and uvx were redirected; playwright's output dir was
missed.

### 2. `modules/lib/mcp.nix` — redirect mcp-remote's config dir

Same class of problem, not yet failing. `mcp-remote` puts its OAuth state in
`$MCP_REMOTE_CONFIG_DIR` or `~/.mcp-auth` (`mcp-auth-config.ts`,
`getConfigDir`), which is read-only in the sandbox. Today `github`, `context7`,
and `n8n` all pass a static bearer header, so the write paths
(`client_info.json`, `tokens.json`, code verifier) never run — `~/.mcp-auth/
mcp-remote-v1` is empty on disk, which confirms it. But a token that starts
returning 401 drops mcp-remote into the OAuth flow, and that flow cannot write.
`openrouter` is OAuth-only and hits this immediately.

Add to `cacheEnv`:

```nix
# mcp-remote persists OAuth client registration and tokens here, defaulting
# to ~/.mcp-auth -- read-only under mcpm-active-profile. Nothing writes it
# while the static bearer headers work, but a 401 falls back to the OAuth
# flow, which would then fail on an unwritable path.
MCP_REMOTE_CONFIG_DIR = "${homeDirectory}/.cache/mcpm/mcp-auth";
```

`cacheEnv` is merged into every server's `env`, so this reaches all four
mcp-remote entries and is inert for the rest — same as the existing npm and uv
vars. mcp-remote creates the directory itself (`mkdir` recursive), so no
`.keep` is needed. No migration either: the old location holds no state.

### 3. `modules/lib/claude-md-content.nix` — Playwright / Screenshots section

The current rule ("save screenshots to a subdirectory of the repo") can no
longer be followed. `mcpm` is one long-lived service shared by every agent and
every repo; it has no idea which repo called it, so a relative filename resolves
against the global output dir, never the caller's working tree.

Rewrite the section to say: screenshots land in
`~/.cache/mcpm/playwright/`; copy one into the repo only if it needs to be
committed, and into a subdirectory, never the repo root. Use the
`adding-to-claude-md` skill for this edit.

### 4. Verify

```bash
cd /var/lib/paseo/paseo-projects/nix-components && nix flake check --no-build
```

Commit and push. CI runs `home-manager switch`. After the deploy:

```bash
systemctl --user show mcpm-active-profile -p ExecStart   # new store path
```

Then start a fresh session (MCP servers connect at session start) and take a
screenshot. Confirm the file appears under `~/.cache/mcpm/playwright/` and the
journal logs no new EROFS.

For step 2 there is nothing to trigger — the OAuth path stays dormant. Confirm
the variable reached the child instead:

```bash
grep -c MCP_REMOTE_CONFIG_DIR ~/.config/mcpm/servers.json   # expect 8
```

Then delete the now-unused `~/.mcp-auth` (it is empty).

## Audit: does any other catalog server need write access?

Checked all eight entries in `modules/lib/mcp.nix` against the unit's writable
set (`%h/.config/mcpm`, `%h/.cache/mcpm`, the obsidian vault, and PrivateTmp).

| Server                    | Writes               | Status                                                                                                                                                    |
| ------------------------- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nixos` (uvx mcp-nixos)   | uv caches only       | OK — redirected by `cacheEnv`; `caches.py`/`config.py` hold everything in memory, no `open`/`mkdir`/`sqlite`/`pickle` calls                               |
| `playwright`              | output dir           | **Broken** — this plan                                                                                                                                    |
| `github` (mcp-remote)     | none in steady state | OK — mcp-remote writes `~/.mcp-auth` only on the OAuth paths (`client_info.json`, `tokens.json`, code verifier). Static bearer header, so those never run |
| `context7` (mcp-remote)   | none in steady state | OK — same                                                                                                                                                 |
| `n8n` (mcp-remote)        | none in steady state | OK — same                                                                                                                                                 |
| `openrouter` (mcp-remote) | `~/.mcp-auth`        | Would fail — OAuth-only, so it must persist tokens. Fixed by step 2, though it stays unusable until the headless-OAuth problem is solved separately       |
| `todoist` (npx)           | npm cache only       | OK — redirected; all its caches are in-process fields                                                                                                     |
| `obsidian` (npx)          | the vault            | OK — vault is in `ReadWritePaths`; `homedir()` is used only to expand a leading `~/` in the `--vault` argument                                            |

mcpm itself is also clean: `~/.mcpm` is touched only by `mcpm install`, and
`~/.local/share/mcpm/frpc` only by the tunnel/share feature. Neither runs under
`profile run --http`.

Empirical backing: seven days of unit logs contain filesystem errors from
playwright only — 36 `EROFS` and 2 `ENOENT ... mkdir`, every one of them on
`/var/lib/paseo/.playwright-mcp`. The `Failed to set up mount namespacing`
entries from Sep 4 are the missing `.cache/mcpm` bind source, already fixed by
the `.keep` files.

The four mcp-remote servers are OK only because their static bearer headers keep
the OAuth write paths dormant. Step 2 of the fix removes that dependency.

## Notes

- `modules/git.nix` has an uncommitted change in the working tree that is
  unrelated to this fix. Do not sweep it into this commit.
- Related, not fixed here: `--allow-unrestricted-file-access` is off, so file
  access is restricted to "workspace roots, or cwd if no roots are configured".
  cwd is `$HOME`, which is both broader than any single repo and read-only.
  Uploads from a repo path may still fail. Revisit only if it actually bites.

## Secrets

None.
