{
  pkgs,
  lib,
  backlogMd,
  ...
}:
let
  # Auto-discover scripts/*.nix so new files there need no edits here.
  scripts = map (f: import f { inherit pkgs; }) (
    lib.filter (f: lib.hasSuffix ".nix" (toString f)) (lib.filesystem.listFilesRecursive ../scripts)
  );
in
{
  home.packages =
    with pkgs;
    [
      # Version control & GitHub
      git
      gh
      commitizen

      # Shell tooling
      eza
      fzf
      fastfetch
      doggo
      direnv
      zoxide
      jq
      navi
      curl
      ripgrep
      delta
      bat
      diff2html-cli
      fd
      btop
      p7zip
      # Linters
      gibo

      # Zsh plugins (needed by zsh.nix OMZ shims)
      zsh-completions
      zsh-autosuggestions
      zsh-syntax-highlighting
      zsh-vi-mode

      # Security
      gnupg
      ngrok

      # Secrets
      infisical

      # Languages
      python3
      nodejs
      uv

      # Fonts — Nerd Font provides icon glyphs for eza --icons and nvim-web-devicons.
      # fontconfig is needed so the font is discoverable in headless/server environments.
      nerd-fonts.fira-code
      fontconfig

      # Node.js tooling
      npkill

      # Nix tooling
      nil
      nixfmt
      devenv

      # Custom packages
      semble
      summarize
      mcpm

      # Search / process / text tools
      nix-index
      lsof
      gawk
    ]
    ++ [
      backlogMd.packages.${pkgs.stdenv.hostPlatform.system}.default
      rtk
    ]
    ++ scripts;
}
