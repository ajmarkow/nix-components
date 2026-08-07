# Agent Dropbox — Design Spec

## Goal

Give any agent, on any host (nix-server, nix-mac, and future hosts), a simple way to drop a file into one shared cloud folder — with a credential that can touch only that folder, not the rest of AWS. An agent just writes a file into a local folder; a background job picks it up and syncs it to the bucket every few minutes. No agent ever runs `rclone` directly or touches credentials.

## Why this approach

S3 + `rclone` is the standard, known-good combo for "push files to cloud storage under a scoped credential." No custom server, no bespoke upload script — `rclone` is the de facto tool for this, IAM does the access-scoping, and the OS's own scheduler (systemd timer / launchd agent) does the polling. No custom watcher daemon to write or maintain.

## Components

### 1. S3 bucket
- Name: `aj-agent-dropbox`
- Private (block all public access), versioning off, no lifecycle rule initially.

### 2. IAM user + policy (scoped credential)
- New IAM user, e.g. `agent-dropbox-writer`, with an inline/managed policy restricted to:
  - `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, `s3:DeleteObject`
  - Resource ARNs limited to `arn:aws:s3:::aj-agent-dropbox` and `arn:aws:s3:::aj-agent-dropbox/*`
- This IAM user's access key is the actual access boundary — it cannot reach any other bucket or AWS service.
- Provisioned via AWS CLI (scripted, not console) as part of implementation. Requires the implementing agent to have AWS credentials with IAM + S3 admin rights available in its environment (existing `aws.env` on nix-server has broader scope — fine for one-time provisioning, not for ongoing use).

### 3. Credential distribution
- Access key + secret stored in a secrets file per host, following the existing pattern (`/etc/nixos/secrets/aws.env`, `/etc/nixos/secrets/ngrok.env` on nix-server):
  - **nix-server (NixOS):** `/etc/nixos/secrets/agent-dropbox.env`
  - **nix-mac (nix-darwin):** equivalent path outside the Nix store — e.g. `/etc/nix-darwin/secrets/agent-dropbox.env` (mirrors the NixOS convention; exact path to be confirmed against nix-mac's existing secrets layout, since `/etc/nixos` doesn't exist on macOS).
  - File format: `AGENT_DROPBOX_ACCESS_KEY_ID=...` / `AGENT_DROPBOX_SECRET_ACCESS_KEY=...`
  - Provisioning of this file on each host is out-of-band (manual copy), same as the existing AWS/ngrok/GPG secrets — the Nix module only *consumes* it if present, never generates it.

### 4. Local outbox folder
- Path: `~/dropbox-outbox` (home-relative — same path works unmodified on NixOS and nix-darwin, no root needed).
- Agents write files here directly (plain `cp`/`Write` — no tool-specific knowledge required). This is the only thing an agent needs to know about.

### 5. Shared home-manager module (nix-components)
- New file: `nix-components/modules/agent-dropbox.nix` — auto-discovered by `home-modules.nix` (every `.nix` file under `modules/` becomes a home-manager module), so it's available to any host importing nix-components' home modules (nix-server and nix-mac both already do).
- Responsibilities:
  - Add `pkgs.rclone` to `home.packages`.
  - `home.file."dropbox-outbox/.keep".text = ""` to ensure the outbox folder exists.
  - Generate `~/.config/rclone/rclone.conf` (or merge a `dropbox` remote into it) via a home-manager activation script, sourcing the per-host secrets file if it exists (guarded, mirroring the `ngrok.env` / GPG-key-import pattern already used in nix-server — missing file is silently skipped, not an error).
  - Remote config:
    ```ini
    [dropbox]
    type = s3
    provider = AWS
    access_key_id = ${AGENT_DROPBOX_ACCESS_KEY_ID}
    secret_access_key = ${AGENT_DROPBOX_SECRET_ACCESS_KEY}
    region = <bucket region>
    ```
  - **Background sync job**, platform-conditional (`pkgs.stdenv.isDarwin`):
    - **Linux (systemd user service, via `systemd.user.services` / `systemd.user.timers`):**
      ```
      ExecStart = rclone move ~/dropbox-outbox dropbox:aj-agent-dropbox/ --min-age 30s
      OnUnitActiveSec = 5min
      ```
    - **macOS (launchd, via home-manager's `launchd.agents`):** equivalent `StartInterval = 300` running the same `rclone move` command.
    - `rclone move` deletes local files after a successful upload (per the "delete after upload" decision), so the outbox stays empty between syncs.
    - `--min-age 30s` avoids racing a file that's still being written by an agent.

### 6a. Downstream wiring (nix-server, nix-mac)
nix-server does **not** auto-import every nix-components home module — `hosts/nixos-host/default.nix` lists them explicitly per user (`users.root` and `users.paseo` each have their own `imports = [ inputs.nix-components.homeModules.* ... ]` list, currently: `zsh`, `git`, `starship`, `claude-code`, `claude-code-claude-md`, `neovim`, `packages`). nix-mac almost certainly follows the same explicit-import pattern. So after this module lands in nix-components:
- Bump the `nix-components` flake input in both nix-server and nix-mac (`nix flake update nix-components`, or user-approved equivalent per each repo's flake-update rules).
- Add `inputs.nix-components.homeModules.agent-dropbox` to the relevant `imports` list(s) — for nix-server, both `users.root` and `users.paseo` in `hosts/nixos-host/default.nix` (only `paseo` needs it for agent use, but match existing per-user symmetry unless told otherwise).
- Provision the `agent-dropbox.env` secret file on each host (out-of-band, per the existing pattern) before/after the rebuild.
- This is a **separate follow-up task per downstream repo**, done by an agent running in that repo's own workspace — not part of the nix-components implementation task itself. After the nix-components module is merged, message the nix-server agent (and nix-mac agent) with the wiring steps above.

### 6. Claude Code skill (nix-components/skills/agent-dropbox/)
- `SKILL.md` describing: "use when the user asks to drop/upload/send a file to the shared dropbox."
- Body: copy/write the file into `~/dropbox-outbox/`, tell the user it will sync to the bucket within 5 minutes. No `rclone` invocation, no credentials, nothing bucket-specific — the skill only ever touches the local folder.
- Following the existing `serve` skill's style (thin wrapper around a real tool) rather than the heavier skills.

## Non-goals
- No web UI, no listing/browsing skill (can be added later if needed — `rclone ls dropbox:aj-agent-dropbox/` works ad hoc).
- No file expiry/lifecycle policy for now.
- No multi-bucket / multi-tenant support — one bucket, one remote, one skill.
- No instant/on-write sync — files land in the bucket within one sync interval (~5 min), not immediately.

## Open items for implementing agent
- Confirm nix-mac's existing secrets directory convention (check `nix-mac` repo for any precedent, e.g. how it handles other out-of-store secrets) and use that instead of guessing `/etc/nix-darwin/secrets` if a different convention already exists.
- Confirm AWS region for the bucket (default to the region already used by existing AWS resources on nix-server, if any; otherwise `us-east-1`).
- Confirm home-manager's `launchd.agents` is available/enabled on nix-mac's existing setup (check how other periodic jobs, if any, are scheduled there).
- Run `nix flake check --no-build` in nix-components after adding the module.
