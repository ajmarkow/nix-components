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
| `claude-code-claude-md.nix` | Manages `~/.claude/CLAUDE.md` with shared global Claude Code instructions |
| `firefox.nix` | Firefox with dark theme, extensions, and policies |
| `git.nix` | Git with GPG commit signing and gpg-agent |
| `mcp.nix` | MCP server configuration (nixos, context7, long-term-memory) |
| `neovim.nix` | Nixvim config: LSP, blink-cmp, pulse.nvim, catppuccin, oil, neo-tree, trouble, and more |
| `neovim-wezterm.nix` | Smart-splits plugin and keybindings for Wezterm pane navigation |
| `packages.nix` | Common home packages shared across all hosts |
| `starship.nix` | Starship prompt |
| `wezterm.nix` | Wezterm with Catppuccin, smart-splits, and Fira Code |
| `zsh.nix` | Zsh with oh-my-zsh, vi-mode, direnv, zoxide, and shared aliases |

## Packages

Custom packages under `pkgs/` are exported as `packages.<system>.<name>`:

| Package | Description |
|---------|-------------|
| `summarize` | CLI tool for summarizing and transcribing URLs, videos, podcasts, and files |

## Skills

Claude Code skills under `skills/` are bundled into `claude-code.nix` at build time via the `paseo-skills` flake input:

| Skill | Description |
|-------|-------------|
| `add-mcp` | Add a new MCP server to the `claude-code.nix` module |
| `c-and-p` | Commit all staged/unstaged changes with a conventional commit message and push |
| `paseo-send` | Find a running paseo agent by repo name and send it a message |
| `serve` | Serve a local file or directory publicly via ngrok tunnel |
| `summarize` | Summarize or transcribe URLs, YouTube videos, podcasts, PDFs, and local files |
| `tighten` | Refactor AGENTS.md following progressive disclosure principles |
