# Unified Infisical secrets model for nix-mac + nix-pixelbook

## Context

Three host repos, three different secrets stories today:

- **nix-server**: fully automated. `secrets.sh` (`nix run .#secrets`) fetches an
  entire Infisical environment via `infisical export --format=json`, renders
  per-service `.env`/token files with an owner/mode table, and CI's
  `deploy.yml` does the same thing over SSH from GitHub Actions secrets that
  Infisical syncs in. Out of scope for this task — it already works and isn't
  being touched.
- **nix-mac**: ad hoc. A zsh-init hook (`nix-components/modules/zsh.nix`) does
  `eval "$(infisical export ...)"` into every interactive shell (project
  `0bd4a4d8-f58e-4bad-9d65-c16ee9aeae7e`, informally called `work_macbook_env`,
  env `prod`, root path). Some MCP server tokens are read straight out of that
  shell's env at Nix eval time via `builtins.getEnv` (`aj-modules/home/mcp.nix`).
  One secret (agent-dropbox S3 creds) has its own one-off provisioning script
  (`nix-mac/scripts/provision-agent-dropbox-env.sh`) that renders a file by
  hand. Nothing is scripted end-to-end; a new secret means editing 2-3 places.
- **nix-pixelbook**: almost nothing. `install.sh` stubs two empty files
  (`beszel-token`, `cachix.env`) under `/etc/nixos/secrets` and the README
  says "provisioned by hand" — no fetch mechanism at all.

Goal: one mechanism, used identically by nix-mac and nix-pixelbook, so adding
a secret to either host is: put it in Infisical, run one command. nix-server
stays as-is (CI-integrated, already mature) — this is scoped to the two hosts
that currently have nothing comparable.

**Constraint carried through this whole plan: no `infisical` command that can
read/print a secret value gets run by the implementing agent. Every step below
that touches the live Infisical project (rename, folder creation, machine
identity, populating values) is called out as a manual step for the user.**

## Design

### 1. Infisical project/folder structure

- Rename the existing `work_macbook_env` project to **`PERSONAL-HOSTS`**
  (user will do this in the Infisical dashboard — a project rename, not
  something the CLI does).
- Keep the single `prod` environment (matches every other convention in this
  fleet — no dev/staging split exists anywhere else).
- Root path `/` = secrets already there today, now implicitly "shared across
  every personal host" (this is already true in practice — `BESZEL_UNIVERSAL_TOKEN`
  is documented in `nix-server/secrets.sh` as one value shared across nix-mac
  and nix-pixelbook). No migration of existing root secrets — additive only.
- New folders `/nix-mac` and `/nix-pixelbook` = secrets specific to one host
  only (e.g. nix-pixelbook's `cachix.env`, if that token ends up host-specific
  rather than shared). User creates secrets under the right folder going
  forward; nothing existing needs to move.
- The fetch script merges root + host folder, host folder wins on key
  collision — mirrors how `nix-server/secrets.sh` already treats
  `INFISICAL_`-prefixed vs bare key fallback (last-writer-wins merge of two
  sources), just applied to two paths instead of two name spellings.

### 2. Shared fetch/render engine lives in nix-components

Both host repos already import shared modules from `nix-components`
(`zsh.nix`, `agent-dropbox.nix`, `beszel-agent.nix`, all of which already
branch on `pkgs.stdenv.isDarwin` for path differences). The new engine follows
that precedent instead of duplicating ~250 lines of bash per repo:

- New file `nix-components/lib/infisical-secrets.nix` exporting a function,
  something like:
  ```nix
  mkSecretsApp {
    projectId,            # PERSONAL-HOSTS project id
    hostFolder,           # "/nix-mac" or "/nix-pixelbook"
    secretsDir,           # "/etc/nix-darwin/secrets" or "/etc/nixos/secrets"
    manifest,             # list of { file, owner ? null, keys, template }
                           #   describing each rendered file, mirroring
                           #   nix-server/secrets.sh's per-file `render` calls
    rebuildCommand ? null # e.g. "darwin-rebuild switch --flake ." /
                           #      "sudo nixos-rebuild switch --flake ."
  }
  ```
  Returns `{ secrets = <writeShellApplication>; rebuild = <writeShellApplication>; }`.
- The generated `secrets` app:
  1. Resolves auth, in order: existing `INFISICAL_TOKEN` in env → if
     `INFISICAL_UNIVERSAL_AUTH_CLIENT_ID`/`_CLIENT_SECRET` are set, run
     `infisical login --method=universal-auth --client-id ... --client-secret ... --plain --silent`
     and capture the printed token into `INFISICAL_TOKEN` (this is the
     preferred, machine-identity path — confirmed via context7 that `infisical
export`/`run` only auto-read a pre-obtained `INFISICAL_TOKEN`/
     `INFISICAL_UNIVERSAL_AUTH_ACCESS_TOKEN`, never client-id/secret directly,
     so the login exchange has to happen explicitly) → else `~/.config/infisical-token`
     if present (existing `zsh.nix`/`paseo-remote.nix` convention) → else fall
     through to interactive `infisical login` (manual auth, confirmed fine).
  2. `infisical export --silent --format=dotenv-export --projectId=<id> --env=prod --path=/`
     and the same for `--path=<hostFolder>`, merged (host folder overrides
     root on key collision) and `eval`'d into the running script's own
     environment — this is what makes `builtins.getEnv`-based consumers
     (nix-mac's `aj-modules/home/mcp.nix` `requireEnv` pattern) keep working
     with zero changes, as long as `rebuild` (below) invokes the actual
     rebuild command from this same process rather than a fresh shell.
  3. Renders each `manifest` entry to `secretsDir`, install-style ownership/mode
     handling copied from `nix-server/secrets.sh` (0600, directory 0751 if a
     non-root owner is needed, skip-with-warning on empty guard values so a
     partial Infisical outage never blanks a working secret on disk).
  4. Never prints a secret value on any path, including errors — same
     guarantee `nix-server/secrets.sh` already documents and enforces.
  5. Supports `--dry-run` (names only) and `--only a,b` exactly like
     `nix-server/secrets.sh`, for parity/familiarity.
- The generated `rebuild` app = run the same auth+export+render steps inline,
  then exec `rebuildCommand` in the now-populated environment. This is the
  "one command" entry point: `nix run .#rebuild` refreshes secrets _and_
  rebuilds in one shot.
- A third generated app, **`login`**, is the consistent-across-machines way to
  provision the machine identity credentials themselves (this is what the user
  asked to have scripted, rather than "store it however on each box"):
  ```nix
  apps.<system>.infisical-login = pkgs.writeShellApplication {
    name = "infisical-login-setup";
    text = ''
      dir="$HOME/.config/infisical"
      install -d -m 700 "$dir"
      read -r -p "Universal Auth Client ID: " client_id
      read -r -s -p "Universal Auth Client Secret: " client_secret
      echo
      printf '%s' "$client_id"     | install -m 600 /dev/stdin "$dir/universal-auth-client-id"
      printf '%s' "$client_secret" | install -m 600 /dev/stdin "$dir/universal-auth-client-secret"
      echo "Stored in $dir (mode 700/600). Re-run to rotate; nothing is echoed back."
    '';
  };
  ```
  `read -s` suppresses terminal echo for the secret, and the script never
  prints either value back — same "never echo" guarantee as the fetch engine.
  Same command (`nix run .#infisical-login`), same two file paths, on every
  host — that's the "consistency across machines" the user wants, versus
  ad hoc copy-pasting into 1Password or a hand-written file per box.
  Auth resolution in `secrets`/`rebuild` (step 1 above) checks these two files
  _first_, before the `INFISICAL_UNIVERSAL_AUTH_CLIENT_ID`/`_SECRET` env vars,
  before `~/.config/infisical-token`, before falling through to interactive
  `infisical login`.

### 2a. GPG signing key: rendering the file is not enough

`nix-components/modules/git.nix` already hardcodes the signing key fingerprint
every host uses (`signingKey = "B9076853EC110207A2EE0D5D3D19E49D0F3BD0FA"`,
`programs.git.signing.signByDefault = true`) — but that module only _tells
git_ which key to sign with. It does not put the private key material into
anyone's keyring. On nix-server that gap is closed by a separate, bespoke
piece: `nix-server/modules/gpg.nix`'s `system.activationScripts.importGpgKey`,
which runs after every `nixos-rebuild switch`, does
`gpg --homedir <user>/.gnupg --import /etc/nixos/secrets/gpg-key.asc` for
root and (via `runuser -u paseo`) for the paseo service user, then sets
ultimate trust with `gpg --import-ownertrust` for that literal fingerprint.
It's guarded on the file existing and is idempotent — `gpg --import` no-ops on
a key it already has, so re-running rebuild is always safe.

nix-mac and nix-pixelbook need the equivalent, generalized to a single
interactive user instead of nix-server's root+paseo split:

- Treat `GPG_SIGNING_KEY` as one more **root-path (shared)** Infisical secret
  in `PERSONAL-HOSTS` — same tier as `BESZEL_UNIVERSAL_TOKEN`, because it's
  the same private key on every personal host, not a per-host value. One-time
  manual step: `gpg --export-secret-keys --armor B9076853EC110207A2EE0D5D3D19E49D0F3BD0FA`
  from wherever the key currently lives (nix-mac's own keyring, since commit
  signing already works there today) and paste the armored output as
  `GPG_SIGNING_KEY`'s value at the project root. Infisical projects don't
  share secrets with each other, so this is a second copy of the same value
  nix-server's own project already stores under the same key name — expected
  duplication, not a mistake.
- `mkSecretsApp`'s manifest on both hosts includes a `gpg-key.asc` entry
  (`keys = [ "GPG_SIGNING_KEY" ]`, raw template, no `owner` — single
  interactive-user machines, no service-user split to worry about), rendered
  to `<secretsDir>/gpg-key.asc` exactly like nix-server's file layout.
- Extend the _same_ `nix-components/modules/git.nix` (it already owns the
  `signingKey` constant — one place that knows the fingerprint) with a
  `home.activation.importGpgKey` step, following the exact guarded-file
  precedent `modules/agent-dropbox.nix` already uses for its own out-of-store
  secrets file (`pkgs.stdenv.isDarwin` branch for the secrets path,
  `lib.hm.dag.entryAfter [ "writeBoundary" ]`, silent skip if the file isn't
  there yet):
  ```nix
  home.activation.importGpgKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    keyFile="${if pkgs.stdenv.isDarwin then "/etc/nix-darwin" else "/etc/nixos"}/secrets/gpg-key.asc"
    if [ -r "$keyFile" ]; then
      run ${pkgs.gnupg}/bin/gpg --import "$keyFile"
      run bash -c 'echo "${signingKey}:6:" | ${pkgs.gnupg}/bin/gpg --import-ownertrust'
    fi
  '';
  ```
  This runs on every `home-manager switch` — which `nix run .#rebuild` (design
  section 2) triggers right after rendering `gpg-key.asc` — so the sequence
  is always: secrets rendered → rebuild runs → activation imports the key →
  git signing works, with no separate manual `gpg --import` ever, on either
  host, after the one-time Infisical population above.
- nix-server is untouched (out of scope) and keeps its own bespoke
  root+paseo import script — this addition lives entirely in the
  home-manager-level `git.nix`, which nix-server's system-level import
  doesn't go through.
- For nix-pixelbook specifically, this is how it gets working commit signing
  for the _first_ time (it has none today); for nix-mac it makes the already-
  working signing setup reproducible from a clean install instead of being an
  unrecorded manual step someone did once.

### 3. Per-host wiring

- **nix-mac** `flake.nix`: add
  ```nix
  apps.<system> = nix-components.lib.mkSecretsApp {
    projectId = "<PERSONAL-HOSTS id>";
    hostFolder = "/nix-mac";
    secretsDir = "/etc/nix-darwin/secrets";
    manifest = [ /* agent-dropbox.env, beszel-agent token, gpg-key.asc,
                    anything else already hand-provisioned via
                    provision-agent-dropbox-env.sh */ ];
    rebuildCommand = "darwin-rebuild switch --flake .";
  };
  ```
  Delete `nix-mac/scripts/provision-agent-dropbox-env.sh` once its one secret
  is covered by the manifest — it becomes redundant.
- **nix-pixelbook** `flake.nix`: same shape, `hostFolder = "/nix-pixelbook"`,
  `secretsDir = "/etc/nixos/secrets"`, manifest starts with the two secrets
  `install.sh` already stubs (`beszel-token`, `cachix.env`) plus `gpg-key.asc`,
  `rebuildCommand = "sudo nixos-rebuild switch --flake ."`.
- Update each repo's README "Secrets" section to describe the new one-command
  flow, replacing the current "provisioned by hand" language (nix-pixelbook)
  and the ad hoc script instructions (nix-mac).

### 4. What the user has to do manually (not run by the implementing agent)

1. Rename `work_macbook_env` → `PERSONAL-HOSTS` in the Infisical dashboard.
2. Create folders `/nix-mac` and `/nix-pixelbook` in that project (only
   needed once a host-specific secret actually exists — can be deferred).
3. Create a Universal Auth machine identity scoped to `PERSONAL-HOSTS` with
   read access, generate its client secret, then on each host run
   `nix run .#infisical-login` (the new shared helper — see design section 2)
   and paste the client ID/secret when prompted. Exact dashboard steps for
   creating the identity go inline in the updated READMEs; the identity
   itself is not created by the implementing agent — that needs an
   authenticated Infisical session it should not open.
4. Export the existing GPG private key once (`gpg --export-secret-keys --armor
B9076853EC110207A2EE0D5D3D19E49D0F3BD0FA`) and store it as `GPG_SIGNING_KEY`
   at the `PERSONAL-HOSTS` project root (see design section 2a) — a second
   copy of the same value nix-server's own project already stores.
5. Populate any other new per-host secret values.

## Secrets inventory (for verification)

Every secret referenced _by name_ in code today, across both host repos and
the shared `nix-components` modules they import. Use this to check Infisical
before running `nix run .#secrets`/`.#rebuild` on either host — cross-check
key names yourself with `infisical secrets --path=<path> --env=prod` (names
only; no need to look at the value column).

**Shared — project root `/`, needed on every host that imports the
corresponding module (both nix-mac and nix-pixelbook import `git.nix` and
`beszel-agent`, so both need these two):**

| Key                      | Consumed by                                        | Pattern                                   |
| ------------------------ | -------------------------------------------------- | ----------------------------------------- |
| `GPG_SIGNING_KEY`        | `nix-components/modules/git.nix` (new — design 2a) | C — render `gpg-key.asc` + `gpg --import` |
| `BESZEL_UNIVERSAL_TOKEN` | `nix-components/os-modules/beszel-agent.nix`       | D — bare token file                       |

**Already at root today (nix-mac's interactive shell already pulls these via
`zsh.nix`) — additive only, not migrated into a folder:**

| Key                               | Consumed by                                | Pattern                                         |
| --------------------------------- | ------------------------------------------ | ----------------------------------------------- |
| `RAINDROP_TOKEN`                  | `nix-mac/aj-modules/home/mcp.nix`          | B — `builtins.getEnv` at rebuild time           |
| `N8N_API_URL`                     | `nix-mac/aj-modules/home/mcp.nix`          | B                                               |
| `N8N_API_KEY`                     | `nix-mac/aj-modules/home/mcp.nix`          | B                                               |
| `AGENT_DROPBOX_ACCESS_KEY_ID`     | `nix-components/modules/agent-dropbox.nix` | C — rendered file, sourced by activation script |
| `AGENT_DROPBOX_SECRET_ACCESS_KEY` | `nix-components/modules/agent-dropbox.nix` | C                                               |

**`/ignored` folder (pre-existing, untouched by this plan) — fetched but
deliberately never exported into an interactive shell:**

| Key              | Consumed by                                                                                                                                         | Pattern                                                                                            |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `PASEO_PASSWORD` | `nix-components/modules/paseo-remote.nix`'s `paseo-headless` wrapper — nix-mac imports `homeModules.paseo-remote`, nix-pixelbook currently does not | E — fetched fresh per invocation by the wrapper itself; never rendered to a file by `mkSecretsApp` |

**nix-pixelbook-only:**

| Key                 | Consumed by                                                                                                 | Pattern |
| ------------------- | ----------------------------------------------------------------------------------------------------------- | ------- |
| `CACHIX_AUTH_TOKEN` | `nix-pixelbook/flake.nix` (`nix-components.determinate.pushCache.enable = true`) → rendered to `cachix.env` | C       |

nix-mac does not enable cache-pushing, so it does not need `CACHIX_AUTH_TOKEN`.

**Wired into a Nix module already, but not yet into either host's render
manifest (this plan adds the manifest entries — design section 3):**
`GPG_SIGNING_KEY` → `gpg-key.asc`, `BESZEL_UNIVERSAL_TOKEN` → `beszel-token`
(pixelbook) / `token` (nix-mac, darwin default path
`/etc/beszel-agent/token`) — both keys already exist in Infisical today
(nix-server's project has them; the root-path copies in `PERSONAL-HOSTS` are
what's newly required), just not yet rendered to disk on either host.

Caveat: this table is everything referenced by name _in code_. `zsh.nix`
does a blanket `infisical export` of the whole root path, so root may already
hold additional ad hoc keys with no corresponding Nix module (e.g. config
for a CLI tool invoked directly, never plumbed through `requireEnv`). Treat
this table as the floor, not a guaranteed ceiling — the CLI cross-check above
is what actually confirms completeness.

## Verification

- `nix flake check --no-build` in both `nix-mac` and `nix-pixelbook` after
  wiring — confirms the new `apps.*` and the `mkSecretsApp` library function
  evaluate cleanly. No build, no execution of the generated scripts, no
  Infisical calls.
- `nix run .#secrets -- --dry-run` (documented, not run by the implementing
  agent) is the user's own smoke test once they've set up the machine
  identity — matches `nix-server/secrets.sh`'s existing `--dry-run` contract,
  prints file/key names only.
- No secret value is read, printed, or transmitted by the implementing agent
  at any point in this task.
