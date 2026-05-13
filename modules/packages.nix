{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
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
    curl
    ripgrep

    # Zsh plugins (needed by zsh.nix OMZ shims)
    zsh-completions
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-vi-mode

    # Security
    gnupg

    # Secrets
    infisical

    # Languages
    python3

    # Editors
    neovim

    # Nix tooling
    nil
    nixfmt
  ];
}
