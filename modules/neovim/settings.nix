{
  pkgs,
  config,
  lib,
  options,
  ...
}:
let
  stylixActive = (options ? stylix) && config.stylix.enable;
in
{
  programs.nixvim = {
    enable = true;
    vimAlias = true;

    # Global settings
    globals = {
      mapleader = " "; # Set space as leader key
      maplocalleader = " ";
      # Disable netrw so oil can take over directory buffers (e.g. when using `nvim .`)
      loaded_netrw = 1;
      loaded_netrwPlugin = 1;
    };

    # General options
    opts = {
      background = lib.mkIf (!stylixActive) "dark";
      autoindent = true; # Auto indent
      smartindent = true;
      number = true; # Show line numbers
      relativenumber = false; # Show relative line numbers
      tabstop = 2; # Tab width
      shiftwidth = 2; # Indent width
      expandtab = true; # Use spaces instead of tabs
      wrap = false; # Don't wrap lines
      termguicolors = lib.mkIf (!stylixActive) true; # Enable 24-bit RGB colors
      clipboard = "unnamedplus"; # Use system clipboard
      autochdir = true; # Auto change directory to the current file's directory
      undofile = true;
      backup = true;
      backupdir.__raw = "vim.fn.stdpath('state') .. '/backup//'";
      signcolumn = "yes";
      cursorline = true;
      guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175";
      guifont = lib.mkIf (!stylixActive) "FiraCode Nerd Font";
      syntax = "on";
    };

    # Colorscheme
    colorschemes.catppuccin = lib.mkIf (!stylixActive) {
      enable = true;
      settings = {
        flavour = "frappe";
        transparent_background = false;
        term_colors = true;
        integrations = {
          lualine = true;
          blink_cmp = true;
          indent_blankline = true;
          which_key = true;
          neotree = true;
          lsp_trouble = true;
        };
      };
    };

    # LSP/linter dependencies
    extraPackages = with pkgs; [
      nixfmt
      shellcheck
      markdownlint-cli
      sqlfluff
    ];
  };
}
