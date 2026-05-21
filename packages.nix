{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        # Version control & GitHub
        git = pkgs.git;
        gh = pkgs.gh;
        commitizen = pkgs.commitizen;

        # Shell tooling
        eza = pkgs.eza;
        fzf = pkgs.fzf;
        fastfetch = pkgs.fastfetch;
        doggo = pkgs.doggo;
        direnv = pkgs.direnv;
        zoxide = pkgs.zoxide;
        jq = pkgs.jq;
        curl = pkgs.curl;
        ripgrep = pkgs.ripgrep;
        delta = pkgs.delta;
        bat = pkgs.bat;
        fd = pkgs.fd;
        btop = pkgs.btop;

        # Zsh plugins
        zsh-completions = pkgs.zsh-completions;
        zsh-autosuggestions = pkgs.zsh-autosuggestions;
        zsh-syntax-highlighting = pkgs.zsh-syntax-highlighting;
        zsh-vi-mode = pkgs.zsh-vi-mode;

        # Security
        gnupg = pkgs.gnupg;

        # Secrets
        infisical = pkgs.infisical;

        # Languages
        python3 = pkgs.python3;
        nodejs = pkgs.nodejs;
        uv = pkgs.uv;

        # Fonts
        fira-code = pkgs.nerd-fonts.fira-code;
        fontconfig = pkgs.fontconfig;

        # Nix tooling
        nil = pkgs.nil;
        nixfmt = pkgs.nixfmt;

        # Custom packages
        summarize = pkgs.callPackage ./pkgs/summarize.nix { };
      };
    };
}
