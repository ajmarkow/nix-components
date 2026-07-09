{ lib
, pkgs
, config
, ...
}:
let
  infisicalProjectId = "0bd4a4d8-f58e-4bad-9d65-c16ee9aeae7e";
in
{
  # Thin OMZ plugin dirs: upstream OMZ does not ship these; Nix wraps the store paths.
  home.file = {
    ".oh-my-zsh-custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh".text = ''
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    '';
    ".oh-my-zsh-custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh".text = ''
      source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    '';
    ".oh-my-zsh-custom/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh".text = ''
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autocd = true;
    history = {
      size = 10000;
      extended = true;
      ignoreAllDups = true;
      share = true;
    };
    oh-my-zsh = {
      enable = true;
      custom = "${config.home.homeDirectory}/.oh-my-zsh-custom";
      # zsh-syntax-highlighting must load after zsh-autosuggestions (upstream requirement).
      # zsh-vi-mode must remain last — it hooks into ZLE and gets overwritten by plugins loaded after it.
      plugins = [
        "git"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "zsh-vi-mode"
      ];
    };

    envExtra = lib.mkMerge [
      ''
        fpath=(${pkgs.zsh-completions}/share/zsh/site-functions $fpath)
        export PNPM_HOME="$HOME/.local/share/pnpm"
        export PATH="$PNPM_HOME:$PATH"
      ''
      (lib.mkIf pkgs.stdenv.isDarwin ''
        fpath=(''${fpath:#/usr/local/share/zsh/site-functions})
        fpath=(~/.docker/completions $fpath)
      '')
    ];

    shellAliases = {
      ga = "git add";
      gst = "git status";
      gp = "git push";
      fzfp = "fzf --preview='less {}' --bind shift-up:preview-page-up,shift-down:preview-page-down";
      ls = "eza --long --git --icons --group --header --color=auto";
      neofetch = "fastfetch";
      dig = "doggo";
      dog = "doggo";
      pip = "pip3";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
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
      EDITOR = "nvim";
      XDG_CONFIG_HOME = "$HOME/.config";
      ZO_DOCTOR = "0";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      WEZTERM_CONFIG_FILE = "$HOME/.config/wezterm/wezterm.lua";
      TWEAKCC_CC_INSTALLATION_PATH = "/usr/bin/cc";
    };

    initContent = lib.mkMerge [
      # Must run before OMZ/plugins (default order 500) so zsh-vi-mode picks up these vars at init time.
      (lib.mkOrder 400 ''
        setopt HIST_REDUCE_BLANKS
        export ZVM_KEYTIMEOUT=0.05
        export ZVM_ESCAPE_KEYTIMEOUT=0.05
      '')

      (lib.mkIf pkgs.stdenv.isDarwin (lib.mkOrder 1000 ''
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
        export PATH="$HOME/.npm-packages/bin:$PATH"
      ''))

      (lib.mkOrder 1000 ''
        # Load secrets from Infisical (only when token is present; 3s timeout avoids blocking).
        [[ -f ~/.config/infisical-token ]] && export INFISICAL_TOKEN=$(cat ~/.config/infisical-token)
        output=$(timeout 3 infisical export --format=dotenv-export --projectId=${infisicalProjectId} --env=prod 2>/dev/null) && eval "$output"
        # Infisical's prod secrets include NODE_ENV=production, which clobbers the
        # empty value the paseo daemon deliberately sets (see nix-server's paseo.nix)
        # and causes npm to silently skip devDependencies in every interactive shell.
        unset NODE_ENV

        unalias gcmsg 2>/dev/null; 'gcmsg'() { cz commit; }

        git() {
          if [[ "$1" == "commit" && ( "$2" == "-m" || "$2" == "--message" ) ]] && [[ -t 0 ]]; then
            cz commit
          else
            command git "$@"
          fi
        }

        mkcd() {
          mkdir -p -- "$1" && cd -- "$1"
        }

        claude-usage() {
          local tmp
          tmp="$(mktemp -t cswap-export.XXXXXX.json)"
          cswap --export "$tmp" >/dev/null 2>&1 && \
          TZ=America/Chicago jq -r '
            .accounts[]
            | select(.email == "alexanderjmarkow@gmail.com")
            | "For account \(.organizationName) (\(.email)), your usage limit resets at \"\((.credentials.claudeAiOauth.expiresAt / 1000) | strflocaltime("%Y-%m-%d %I:%M:%S %p %Z"))\"."
          ' "$tmp"
          rm -f "$tmp"
        }

        ip-loc() {
          local ip="''${1:?Usage: ip-loc <ip>}"
          curl -s "https://ipinfo.io/''${ip}/json" \
            | jq -r --arg ip "$ip" '"The IP \($ip) is from \(.city), \(.region), in \(.country)."'
        }
      '')
    ];

    loginExtra = ''
      if [[ -t 1 ]]; then
        RED='\033[0;31m'
        ORANGE='\033[0;33m'
        YELLOW='\033[1;33m'
        GREEN='\033[0;32m'
        BLUE='\033[0;34m'
        INDIGO='\033[0;36m'
        VIOLET='\033[0;35m'
        RESET='\033[0m'

        echo -e "''${RED}                                        ''${RESET}"
        echo -e "''${ORANGE}                                        ''${RESET}"
        echo -e "''${YELLOW}      ___         ___          ___      ''${RESET}"
        echo -e "''${GREEN}     /  /\\       /  /\\        /__:\\     ''${RESET}"
        echo -e "''${BLUE}    /  /::\\     /  /:/       |  |::\\    ''${RESET}"
        echo -e "''${INDIGO}   /  /:/\\:\\   /__/::\\       |  |:|:\\   ''${RESET}"
        echo -e "''${VIOLET}  /  /:/~/::\\  \\__\\/\\:\\    __|__|:|\\:\\  ''${RESET}"
        echo -e "''${RED} /__/:/ /:/\\:\\    \\  \\:\\  /__/::::| \\:\\ ''${RESET}"
        echo -e "''${ORANGE} \\  \\:\\/:/__\\/     \\__\\:\\ \\  \\:\\~~\\__\\/ ''${RESET}"
        echo -e "''${YELLOW}  \\  \\::/          /  /:/  \\  \\:\\       ''${RESET}"
        echo -e "''${GREEN}   \\  \\:\\         /__/:/    \\  \\:\\      ''${RESET}"
        echo -e "''${BLUE}    \\  \\:\\        \\__\\/      \\  \\:\\     ''${RESET}"
        echo -e "''${INDIGO}     \\__\\/                    \\__\\/     ''${RESET}"
        echo -e "''${VIOLET}                                        ''${RESET}"
        echo -e "''${RED}                                        ''${RESET}"
      fi
    '';
  };

  home.activation = lib.mkIf pkgs.stdenv.isDarwin {
    dockerCompletions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.docker/completions
      if command -v docker &>/dev/null; then
        docker completion zsh > $HOME/.docker/completions/_docker
      fi
    '';
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd cd" ];
  };
}
