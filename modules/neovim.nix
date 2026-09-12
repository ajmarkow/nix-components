# This file must stay a top-level modules/*.nix file: home-modules.nix
# auto-exports it as homeModules.neovim by readDir'ing this directory
# (top-level regular files only). Most content lives in ./neovim/, split by
# concern, each file setting a distinct sub-path of `programs.nixvim` so the
# module system's ordinary recursive config merge combines them (not a
# manual `//`).
#
# `keymaps`/`autoCmd` stay inline here rather than in their own ./neovim/
# file. Both are `listOf`-typed options, and modules/neovim-wezterm.nix also
# defines `programs.nixvim.keymaps` — when every homeModule is imported
# together (as tests/equivalence's "all" config and any consumer that
# imports both do), the module system's breadth-first merge concatenates
# same-option definitions in the order they're discovered, which depends on
# import *nesting depth*, not just declaration order. Pushing keymaps one
# level deeper than neovim-wezterm.nix's (undivided) definition changed that
# concatenation order — same keymaps, different generated init.lua bytes.
# Keeping them at this file's top level matches neovim-wezterm.nix's depth
# and keeps the merge order — and so the generated output — unchanged.
{ ... }:
{
  imports = [
    ./neovim/settings.nix
    ./neovim/extra-plugins.nix
    ./neovim/plugins.nix
  ];

  programs.nixvim = {
    # Open oil when starting with a directory (e.g. `nvim .`)
    autoCmd = [
      {
        event = "VimEnter";
        pattern = "*";
        callback = {
          __raw = ''
            function()
              local path = vim.fn.argv(0)
              if path ~= "" and vim.fn.isdirectory(path) == 1 then
                require("oil").open(path)
              end
            end
          '';
        };
        once = true;
      }
    ];

    # Key mappings
    keymaps = [
      # Which-key - show keybindings
      {
        key = "?";
        action = "<cmd>lua require('which-key').show()<cr>";
        options.desc = "Show keybindings (which-key)";
      }
      # Pulse command palette
      {
        key = "<leader>pc";
        action = "<cmd>Pulse<cr>";
        options.desc = "Pulse command palette";
      }
      # Pulse search
      {
        key = "<leader>ps";
        action = "<cmd>Pulse fuzzy_search<cr>";
        options.desc = "Pulse fuzzy search";
      }
      # File explorer
      {
        key = "<leader>e";
        action = ":Neotree toggle reveal=false<CR>";
        options.desc = "Toggle file explorer";
      }
      # Save file
      {
        key = "<leader>w";
        action = ":w<CR>";
        options.desc = "Save file";
      }
      # Quit
      {
        key = "<leader>q";
        action = ":q<CR>";
        options.desc = "Quit";
      }
      # Format
      {
        key = "<leader>f";
        action = "<cmd>Format<cr>";
        options.desc = "Format file";
      }
      # Claude Code
      {
        key = "<leader>ac";
        action = "<cmd>ClaudeCode<cr>";
        options.desc = "Toggle Claude Code";
      }
      {
        key = "<leader>af";
        action = "<cmd>ClaudeCodeFocus<cr>";
        options.desc = "Focus Claude Code";
      }
      {
        key = "<leader>ar";
        action = "<cmd>ClaudeCode --resume<cr>";
        options.desc = "Resume Claude session";
      }
      {
        key = "<leader>as";
        action = "<cmd>ClaudeCodeSend<cr>";
        mode = "v";
        options.desc = "Send selection to Claude";
      }
      {
        key = "<leader>ab";
        action = "<cmd>ClaudeCodeAdd %<cr>";
        options.desc = "Add current buffer to Claude";
      }
      {
        key = "<leader>aa";
        action = "<cmd>ClaudeCodeDiffAccept<cr>";
        options.desc = "Accept Claude diff";
      }
      {
        key = "<leader>ad";
        action = "<cmd>ClaudeCodeDiffDeny<cr>";
        options.desc = "Deny Claude diff";
      }
    ];
  };
}
