{ pkgs, pkgs-unstable, backlogMd, ... }:
{
  home.packages = with pkgs; [
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
    fd
    btop
    p7zip
    # Linters
    trunk-io

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

    # Search / process / text tools
    nix-index
    lsof
    gawk
  ] ++ [
    backlogMd.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs-unstable.rtk
  ];
}
