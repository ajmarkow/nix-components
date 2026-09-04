# Plan: `obsidian-gui.nix` in nix-components

## Context

`nix-server` now runs a headless `obsidian-mcp` setup: a vault at
`/var/lib/obsidian-sync/vault` kept in sync with S3 (`aj-agent-dropbox`,
prefix `obsidian-vault/`) via `rclone bisync` on a 2-minute systemd timer
(`nix-server/modules/obsidian.nix`, see `plan-obsidian-agentic.md` for the
full architecture). That vault is meant to be a shared "agentic" notebook —
agents write to it headlessly, and the user reads/edits it from GUI devices.

Today the GUI side is undocumented and unconfigured: nothing declares an
Obsidian install, vault, theme, or plugin set on `nix-mac` or
`nix-pixelbook`. This plan adds a `modules/obsidian-gui.nix` home-manager
module to `nix-components` that centralizes that GUI config so both hosts
converge on the same theme, plugin set, and S3-synced vault, without
duplicating config per host. It is intentionally **not** imported on
`nix-server`, which stays headless.

Two open implementation questions were resolved with the user before
writing this plan:

- Catppuccin **Frappe** flavor will be pinned via the **Style Settings**
  community plugin (added to the plugin list beyond the original ask,
  since the Catppuccin theme's flavor switch is normally driven by it).
- `nix-mac`'s existing system-level `pkgs.obsidian`
  (`environment.systemPackages`, `flake.nix:69`) will be **removed** in a
  follow-up edit so `obsidian-gui.nix` is the single owner of the package.

## Decisions

1. **Module name/location**: `nix-components/modules/obsidian-gui.nix`.
   Because `home-modules.nix` auto-exports every regular file directly
   under `modules/` as `homeModules.<filename minus .nix>`, this needs no
   edit to `home-modules.nix` unless it requires an injected flake input
   (see Theme below) — in which case one `lib.optionalAttrs (name ==
"obsidian-gui.nix") { _module.args.catppuccinObsidianSource =
inputs.catppuccin-obsidian; }` clause is added there, alongside a new
   `catppuccin-obsidian` flake input in `flake.nix`.

2. **Vault location on clients**: `${config.home.homeDirectory}/Vaults/Agentic`
   (module option, defaulted). Separate top-level vault, not nested in any
   Sync-managed vault — matches the isolation requirement already
   documented in `plan-obsidian-agentic.md` §2.

3. **Declarative scope**: the module manages specific files inside
   `.obsidian/` (`appearance.json`, `core-plugins.json`,
   `community-plugins.json`, each managed plugin's `data.json`, theme
   files, one CSS snippet) — not the whole `.obsidian/` directory. It does
   **not** touch plugin runtime state (search index, per-note settings,
   `workspace.json`), so those remain freely user-editable.

4. **Write mechanism, not symlinks**: Obsidian rewrites `core-plugins.json`
   / `community-plugins.json` at runtime whenever the user toggles a
   plugin from Settings. A `home.file` symlink into the Nix store is
   read-only and would break that. Instead, follow the `agent-dropbox.nix`
   precedent: a `home.activation` script (`lib.hm.dag.entryAfter
["writeBoundary"]`) that `install -m644`-copies each Nix-store-rendered
   JSON file into the live vault path. Files start from the declared
   baseline on every `home-manager switch` and are freely mutable by
   Obsidian in between switches.

5. **Cross-platform**: mirror `agent-dropbox.nix`'s `lib.mkMerge` +
   `pkgs.stdenv.isDarwin` split, since the global Obsidian config directory
   differs:
   - macOS (`nix-mac`): `${config.home.homeDirectory}/Library/Application Support/obsidian/obsidian.json`
   - Linux (`nix-pixelbook`): `${config.home.homeDirectory}/.config/obsidian/obsidian.json`

## Config content

### Core plugins (enable only these — `core-plugins.json`, JSON array of ids)

```
backlink, bookmarks, command-palette, file-explorer, graph, note-composer,
outgoing-link, outline, switcher, global-search, slash-command, sync
```

Note: `sync` here only means the _Sync core plugin UI_ is enabled/visible —
it does not activate Obsidian Sync for this vault. Actually turning on
Sync for the `Agentic` vault would conflict with `remotely-save`'s S3 sync
(same residual risk already flagged in `plan-obsidian-agentic.md` §2/§7:
verify Sync stays off for this vault on every device after setup).

Exact plugin ids should be verified against the shipped Obsidian version at
implementation time (ids occasionally change between releases, e.g.
`slash-command` is a newer addition) — treat the list above as the source
of truth for _which plugins_, verify the _id strings_ against a real
`core-plugins.json` or Obsidian's plugin list before committing the
derivation.

### Community plugins (`community-plugins.json`, JSON array of ids)

```
omnisearch, remotely-save, obsidian-icon-folder, obsidian-style-settings
```

- **Omnisearch** — `scambier/obsidian-omnisearch`. No config needed beyond
  enabling it.
- **Icon folder** — `FlorianWoelki/obsidian-icon-folder`. No config needed
  beyond enabling it.
- **Style Settings** — `mgmeyers/obsidian-style-settings`. Added solely to
  drive Catppuccin's flavor switch (see Theme below); not otherwise
  configured.
- **Remotely-save** — see dedicated section below; this one needs real
  preconfiguration, not just enabling.

Each plugin is fetched from its GitHub release assets (`manifest.json`,
`main.js`, `styles.css` where present) via `pkgs.fetchurl` with pinned
sha256 hashes, assembled by a small shared helper function in the module,
e.g.:

```nix
fetchObsidianPlugin = { repo, version, mainJsHash, manifestHash, stylesHash ? null }:
  pkgs.runCommand "obsidian-plugin-${repo}" { } ''
    mkdir -p $out
    cp ${pkgs.fetchurl { url = "https://github.com/${repo}/releases/download/${version}/main.js"; sha256 = mainJsHash; }} $out/main.js
    cp ${pkgs.fetchurl { url = "https://github.com/${repo}/releases/download/${version}/manifest.json"; sha256 = manifestHash; }} $out/manifest.json
    ${lib.optionalString (stylesHash != null) "cp ${pkgs.fetchurl { ... }} $out/styles.css"}
  '';
```

placed via the activation-script copy mechanism (Decision 4) into
`<vault>/.obsidian/plugins/<id>/`.

### Theme — Catppuccin Frappe

- Fetch `catppuccin/obsidian` via `pkgs.fetchFromGitHub` (new flake input
  `catppuccin-obsidian`, pinned like `obsidian-skills` is), copy
  `manifest.json` + `theme.css` into `<vault>/.obsidian/themes/Catppuccin/`.
- Set `appearance.json`: `"cssTheme": "Catppuccin"`.
- Preconfigure Style Settings' own `data.json`
  (`.obsidian/plugins/obsidian-style-settings/data.json`) with the flavor
  set to Frappe — exact key names need verifying against the plugin's
  current settings schema at implementation time (Style Settings persists
  per-setting-id values keyed by the theme's declared `style-settings`
  YAML block, not a flat flavor string, so this needs a real
  install-and-inspect pass before finalizing the template).
- Fallback if that schema turns out to be awkward to template: ship a CSS
  snippet (`.obsidian/snippets/catppuccin-frappe.css`) that force-sets the
  Frappe CSS custom properties and enable it via `appearance.json`'s
  `enabledCssSnippets`, without relying on Style Settings' stored state.
  Keep Style Settings enabled either way (per the user's decision) but
  don't block on its data.json format being awkward.

### Remotely-save — preconfigured, with fallback

**Preconfigure** (primary path): mirror `agent-dropbox.nix`'s secret-wiring
pattern exactly — an out-of-band `.env` file at
`/etc/nix-darwin/secrets/agent-dropbox.env` (Darwin) or
`/etc/nixos/secrets/agent-dropbox.env` (Linux), already populated on hosts
that import `agent-dropbox`, holding `AGENT_DROPBOX_ACCESS_KEY_ID` /
`AGENT_DROPBOX_SECRET_ACCESS_KEY`. A `home.activation` script sources it (if
readable — same silent-skip-if-missing behavior as `agent-dropbox.nix`) and
uses `jq`/`envsubst` to render `.obsidian/plugins/remotely-save/data.json`
from a template with:

- `serviceType = "s3"`
- bucket `aj-agent-dropbox`, region `us-east-1` (matches `agent-dropbox.nix`'s `awsRegion`)
- prefix `obsidian-vault/` (same S3 path the server-side bisync uses)
- access key / secret from the sourced env vars
- auto-sync every 2 minutes + sync-on-save, matching the server timer cadence
- a fixed, non-random `vaultRandomID` (e.g. a stable string like
  `"nix-managed-agentic-vault"`) reused across all hosts, so the value stays
  reproducible under Nix rather than using the plugin's normal
  first-run-random generation

**Verification needed at implementation time**: remotely-save's exact
`data.json` field names (`s3BucketName` / `s3AccessKeyID` / etc., naming
not confirmed from source in this planning pass) must be confirmed by
either reading the plugin's TypeScript settings interface on GitHub or
doing one manual setup pass and inspecting the generated file, before the
Nix template is finalized.

**Fallback** (only if the schema proves impractical to template, e.g. it
turns out to encrypt fields with a vault-specific password Nix can't
reproduce): per-host manual setup instructions —

1. Install Remotely-save from Community Plugins (already declared enabled,
   so just needs its settings filled in).
2. Settings → Remotely-save → Remote Service → S3 (S3-compatible).
3. Endpoint `s3.amazonaws.com`, region `us-east-1`, bucket
   `aj-agent-dropbox`, path/prefix `obsidian-vault/`.
4. Access key / secret: same values as `AGENT_DROPBOX_ACCESS_KEY_ID` /
   `AGENT_DROPBOX_SECRET_ACCESS_KEY` (ask the user for these out of band —
   never print them; they're already on-host in the `.env` file above if
   readable).
5. Auto sync every 2 minutes, sync on save.
6. Confirm Obsidian Sync is OFF for this vault specifically.

### Auto-connecting the vault (global `obsidian.json`)

To satisfy "hosts can connect automatically" rather than requiring a
manual "Open folder as vault" click per device: a `home.activation` script
merges an entry for the vault path into the platform's global
`obsidian.json` vault registry (paths in Decision 5), using `jq` to:

- read the existing file if present (it lists _all_ vaults on the machine,
  including unrelated personal ones — must merge, never overwrite)
- check whether an entry with this vault's path already exists (idempotent
  re-runs)
- if not, add one keyed by a stable id (e.g. a hash of the path) with
  `{"path": "<vault path>", "ts": <fixed>, "open": false}`

`open: false` avoids force-launching into this vault on every Obsidian
start; it just appears in the vault switcher immediately after the first
`home-manager switch`, no manual folder picker needed.

## File changes

**nix-components:**

- New `modules/obsidian-gui.nix` (module described above).
- `flake.nix`: add `catppuccin-obsidian` input (`github:catppuccin/obsidian`, pinned).
- `home-modules.nix`: add the `_module.args.catppuccinObsidianSource` injection clause for `obsidian-gui.nix`, following the existing `namesNeedingCliPackageArgs`-style pattern.

**nix-mac** (`flake.nix`):

- Remove `pkgs.obsidian` from `environment.systemPackages` (~line 69).
- Add `inputs.nix-components.homeModules.obsidian-gui` to `home-manager.sharedModules` (~line 379-403 block).

**nix-pixelbook** (`flake.nix`):

- Add `pkgs.obsidian` is _not_ needed separately — module's `home.packages` covers it.
- Add `inputs.nix-components.homeModules.obsidian-gui` to `home-manager.sharedModules` (~line 234-259 block).

## Verification

After implementation, on each of `nix-mac` / `nix-pixelbook`:

```bash
home-manager switch   # (run by the user — not by the agent, per this system's rebuild policy)
ls -la ~/Vaults/Agentic/.obsidian/plugins/
cat ~/Library/Application\ Support/obsidian/obsidian.json   # or ~/.config/obsidian/obsidian.json on Linux
```

- Confirm the vault shows up in Obsidian's vault switcher without manually browsing for it.
- Open it, confirm Catppuccin Frappe is active, confirm the four community plugins are enabled.
- Confirm Remotely-save shows a configured S3 remote (not blank) and a manual "sync now" pulls the same notes visible via `obsidian-mcp` on `nix-server`.
- Confirm Obsidian Sync is off for this vault (Settings → Sync).
- Edit a note on the client, wait for both the client's remotely-save interval and the server's 2-minute bisync timer, confirm the edit appears through the `obsidian-mcp` tools (`obsidian_read_note`).

## Risks (carried over + new)

- Same bisync conflict/dual-sync risks already documented in
  `plan-obsidian-agentic.md` §7 — unchanged, now with two more sync
  participants (nix-mac, nix-pixelbook) instead of one.
- Style Settings' `data.json` schema is unconfirmed; may require the CSS
  snippet fallback described above.
- Remotely-save's `data.json` schema is unconfirmed; may require the
  manual-setup fallback described above.
- Declarative config is reasserted on every `home-manager switch` — manual
  GUI changes to theme/enabled-plugins between switches will be reverted
  next switch. This is intended (centralized config) but worth the user
  knowing.
