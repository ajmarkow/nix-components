{ lib
, pkgs
, config
, ...
}:
{
  programs.zsh = {
    # Strip /usr/local zsh site-functions so compinit doesn't error on missing _mullvad
    # Add ~/.docker/completions to fpath for docker tab completions
    envExtra = ''
      fpath=(''${fpath:#/usr/local/share/zsh/site-functions})
      fpath=(~/.docker/completions $fpath)
    '';

    shellAliases = {
      hsw = "home-manager switch";
      dsw = "source ~/.zshrc && sudo -E darwin-rebuild switch --impure --flake /etc/nix-darwin#AJ-MARKOW-WORK-MACBOOK-PRO";
      showfiles = "defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder";
      hidefiles = "defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder";
      claude-monitor = "claude-monitor --plan pro";
      sync-mcp-servers = "ruby /Users/ajmarkow/Documents/Scripts/sync-mcp-servers.rb";
      claude-work = "cswap --switch-to 2 && claude";
      claude-personal = "cswap --switch-to 1 && claude";
    };

    sessionVariables = {
      WEZTERM_CONFIG_FILE = "$HOME/.config/wezterm/wezterm.lua";
      TWEAKCC_CC_INSTALLATION_PATH = "/usr/bin/cc";
    };

    initContent = lib.mkOrder 1000 ''
      # Ensure Homebrew paths are always available
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
      # Ensure npm global paths always available
      export PATH="$HOME/.npm-packages/bin:$PATH"
    '';
  };

  # Generate docker zsh completions on each switch if docker is available
  home.activation.dockerCompletions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p $HOME/.docker/completions
    if command -v docker &>/dev/null; then
      docker completion zsh > $HOME/.docker/completions/_docker
    fi
  '';
}
