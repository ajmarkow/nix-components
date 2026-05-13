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
  inputs.nix-components.modules.zsh
  inputs.nix-components.modules.neovim
  inputs.nix-components.modules.claude-code
];
```

## Modules

### Home-Manager

| Module | Description |
|--------|-------------|
| `neovim.nix` | Nixvim config: LSP, blink-cmp, pulse.nvim, catppuccin, oil, neo-tree, trouble, and more |
| `neovim-wezterm.nix` | Smart-splits plugin and keybindings for Wezterm pane navigation |
| `zsh.nix` | Zsh with oh-my-zsh, vi-mode, direnv, zoxide, and shared aliases |
| `zsh-macos.nix` | macOS-specific zsh additions: Homebrew PATH, docker completions, macOS aliases |
| `claude-code.nix` | Claude Code with statusline, rtk-rewrite hook, plugins, and marketplaces |
| `mcp.nix` | MCP server configuration (nixos, context7, long-term-memory) |
| `starship.nix` | Starship prompt |
| `git.nix` | Git with GPG commit signing and gpg-agent |
| `git-macos.nix` | macOS pinentry for gpg-agent |
| `firefox.nix` | Firefox with dark theme, extensions, and policies |
| `wezterm.nix` | Wezterm with Catppuccin, smart-splits, and Fira Code |

### System

| Module | Description |
|--------|-------------|
| `packages.nix` | Common system packages shared across all hosts |
