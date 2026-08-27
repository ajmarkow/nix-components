# nix-components

Reusable Nix modules shared across multiple host configurations (macOS via nix-darwin, NixOS servers, etc.).

## Usage

Add this repo as a flake input and import the modules you need:

```nix
inputs.nix-components.url = "github:ajmarkow/nix-components";
```

Then import individual modules in your host or home-manager config:

```nix
imports = [
  inputs.nix-components.homeModules.zsh
  inputs.nix-components.homeModules.neovim
  inputs.nix-components.homeModules.claude-code
];
```

## Modules

All files under `modules/` are auto-exported as `homeModules.<name>` (filename without `.nix`).

| Module | Description |
|--------|-------------|
| `claude-code.nix` | Claude Code with statusline, rtk-rewrite hook, plugins, and skill marketplaces |
| `claude-code-claude-md.nix` | Writes `~/.claude/CLAUDE.md` from `modules/lib/claude-md-content.nix` |
| `opencode.nix` | opencode with the Muse contributor provider; writes `~/.config/opencode/AGENTS.md` from the same `modules/lib/claude-md-content.nix` |
| `firefox.nix` | Firefox with dark theme, extensions, and policies |
| `git.nix` | Git with GPG commit signing and gpg-agent |
| `mcp.nix` | MCP server configuration (nixos, context7, long-term-memory) |
| `neovim.nix` | Nixvim config: LSP, blink-cmp, pulse.nvim, catppuccin, oil, neo-tree, trouble, and more |
| `neovim-wezterm.nix` | Smart-splits plugin and keybindings for Wezterm pane navigation |
| `packages.nix` | Common home packages shared across all hosts |
| `starship.nix` | Starship prompt |
| `wezterm.nix` | Wezterm with Catppuccin, smart-splits, and Fira Code |
| `zsh.nix` | Zsh with oh-my-zsh, vi-mode, direnv, zoxide, and shared aliases |

`modules/lib/` is not scanned into `homeModules` (only top-level files under `modules/` are) — it holds `claude-md-content.nix`, the shared CLAUDE.md/AGENTS.md prose imported by both `claude-code-claude-md.nix` and `opencode.nix`. Edit prose there, not in either consuming module.

## OS modules

System-level modules are exported as `darwinModules.<name>` and `nixosModules.<name>`. They live in `os-modules.nix` and `os-modules/`, not `modules/`, because they set NixOS / nix-darwin system options rather than home-manager ones. Import them in the host module list, next to your other system modules:

```nix
modules = [
  inputs.nix-components.darwinModules.home-manager-backup
  inputs.nix-components.darwinModules.determinate
];
```

| Module | Platforms | Description |
|--------|-----------|-------------|
| `home-manager-backup` | darwin, nixos | Shared `backupFileExtension` + `overwriteBackup` so activation replaces a stale `<file>.backup` instead of aborting on it |
| `determinate` | darwin, nixos | Determinate Nix, plus the shared binary caches and trusted users for every host |
| `tailscale` | darwin, nixos | Tailscale client daemon, the tailscaled operator grant the `diff-viewer` module needs, and an opt-in health watchdog |

### `determinate`

Wraps the upstream [`determinate`](https://github.com/DeterminateSystems/determinate) module and adds the cache baseline. Options:

| Option | Description |
|--------|-------------|
| `nix-components.determinate.substituters` | Binary caches, added as `extra-substituters`. Hosts append to the baseline |
| `nix-components.determinate.trustedPublicKeys` | Matching public keys, added as `extra-trusted-public-keys`. A cache without its key here is silently skipped |
| `nix-components.determinate.trustedUsers` | Users granted `trusted-users`. Needed for nix to honor a flake input's own `nixConfig` substituters |

All three are `listOf str` and merge across definitions, so a host adds only what is specific to it:

```nix
nix-components.determinate.trustedUsers = [ "ajmarkow" ];
```

Two things differ by platform, both because of upstream:

- **macOS needs the installer first.** Determinate manages the Nix installation outside nix-darwin, so run the [macOS package](https://install.determinate.systems/determinate-pkg/stable/Universal) on the machine **before** the first activation. The module sets `nix.enable = false`, which makes nix-darwin restore whatever unmanaged daemon is in `/nix/var/nix/profiles/default` and stop managing `/etc/nix/nix.conf`. Activating first therefore leaves the host with no `experimental-features`, so no flakes, so no way to rebuild back out. NixOS needs no installer — that module is fully declarative.
- **Garbage collection is not the same setting.** On darwin, `nix.enable = false` makes `nix.gc` and `nix.optimise` silently inert, so GC is delegated to determinate-nixd (`garbageCollector.strategy = "automatic"`, free-space driven). On NixOS `nix.*` still works and upstream exposes no GC option, so the module sets `nix.gc` to weekly / `--delete-older-than 14d`. Override per host with `nix.gc`; every value is a `mkDefault`.

A host that adopts this module should delete its own `nix.settings.experimental-features`, `nix.gc`, `nix.optimise`, and `nix.settings.trusted-users`. Determinate enables `nix-command` and `flakes` by default, and on darwin the rest is dead code that still reads as live config.

### `tailscale`

Enables `services.tailscale` and grants a user "operator" rights over the local tailscaled. The grant is what lets the [`diff-viewer`](#modules) module run `tailscale serve` as a normal user — without it, diff URLs 404 and tailscaled logs `Access denied: serve config denied`. Importing the module enables tailscale; there is no `enable` option.

| Option | Description |
|--------|-------------|
| `nix-components.tailscale.operator` | User granted tailscaled operator rights. `null` (the default) grants nobody |
| `nix-components.tailscale.healthcheck.enable` | Poll `tailscale status` every 2 minutes, restart tailscaled when down or hung, alert after 3 consecutive failures. NixOS only, off by default |
| `nix-components.tailscale.healthcheck.secretsFile` | File defining `SHOUTRRR_URL` for those alerts. Defaults to `/etc/nixos/secrets/tailscale-alert.env`, root-owned 0600, optional at run time |

```nix
nix-components.tailscale.operator = "ajmarkow";
```

Three things differ by platform:

- **The operator grant uses a different mechanism.** NixOS has `services.tailscale.extraSetFlags`; nix-darwin declares only `enable`, `package` and `overrideLocalDns`, so darwin runs `tailscale set --operator=` from `system.activationScripts` instead. Idempotent, and non-fatal if tailscaled is not up yet on first activation.
- **darwin pins `package = pkgs.tailscale`.** The sandboxed Mac App Store Tailscale app cannot run `tailscale serve`, and `homebrew.onActivation.cleanup` will not remove a MAS-installed app — so remove it by hand if one is present.
- **The healthcheck is NixOS-only.** It is a systemd service plus timer, and the darwin variant asserts the option is off rather than ignoring it. `Restart=on-failure` / `RestartSec=5s` on tailscaled is set on NixOS unconditionally; it covers crashes, while the watchdog covers a hung-but-alive daemon and a stalled tailnet link.

Firewall rules, sshd gating, and per-service tailnet port exposure stay host-specific — they name each host's own services and there is nothing shared to factor out.

## Packages

Custom packages under `pkgs/` are exported as `packages.<system>.<name>`:

| Package | Description |
|---------|-------------|
| `summarize` | CLI tool for summarizing and transcribing URLs, videos, podcasts, and files |
| `organize-tool` | File management automation tool. Not yet in nixpkgs, so this repo packages it |
| `semble` | Semantic code search tool, built from the `semble-workspace` uv2nix project |

## Skills

Claude Code skills under `skills/` are bundled into `claude-code.nix` at build time via the `paseo-skills` flake input:

| Skill | Description |
|-------|-------------|
| `add-mcp` | Add a new MCP server to the `claude-code.nix` module |
| `adding-to-claude-md` | Add new rules or guidance to `modules/lib/claude-md-content.nix` |
| `backlog-md` | Guide use of the Backlog.md CLI for task creation, status, and board views |
| `c-and-p` | Commit all staged and unstaged changes with a conventional commit message and push |
| `debug-with-llms` | Debug AI-assisted code without looping, patching symptoms, or writing slop |
| `deploy-nix-components` | Deploy a nix-components change and bump the flake input on nix-server |
| `git-rewrite-history` | Rewrite git history with `git-filter-repo` instead of `filter-branch` |
| `paseo-send` | Find a running paseo agent by repo name and send it a message |
| `ponytail` | Push for the simplest, shortest working solution on any coding task |
| `ruleset-design` | Design and audit rule files such as AGENTS.md and CLAUDE.md |
| `serve` | Serve a local file or directory publicly through an ngrok tunnel |
| `ste-writing` | Write or edit documentation in Simplified Technical English |
| `summarize` | Summarize or transcribe URLs, YouTube videos, podcasts, PDFs, and local files |
| `taste-skill` | Design landing pages and portfolios that avoid a templated look |
| `test-driven-development` | Follow test-driven development before writing implementation code |
| `tighten` | Refactor AGENTS.md following progressive disclosure principles |
| `writing-skills` | Create, edit, and verify Claude Code skills before deployment |
