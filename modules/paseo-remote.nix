{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.nix-components.paseo.remoteHost = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = "tcp://paseo.aj-cloud.cc:443?ssl=true";
    description = ''
      Paseo daemon host URI exported as PASEO_HOST in zsh. The password is
      NOT part of this URI; the CLI reads it separately from PASEO_PASSWORD,
      which the zsh module loads from Infisical. Set to null on a host that
      runs the daemon locally so the CLI uses the local socket.
    '';
  };

  config = lib.mkIf (config.nix-components.paseo.remoteHost != null) {
    # mkOrder 1500 places this after zsh.nix's Infisical eval (mkOrder 1000),
    # in case a PASEO_HOST ever lands in Infisical — the nix value wins.
    programs.zsh.initContent = lib.mkOrder 1500 ''
      export PASEO_HOST="${config.nix-components.paseo.remoteHost}"
    '';

    # For cron/launchd units that never source zsh init. Hardcodes the one
    # secret it may fetch so agents never compose infisical commands.
    home.packages = [
      (pkgs.writeShellApplication {
        name = "paseo-headless";
        text = ''
          export PASEO_HOST="${config.nix-components.paseo.remoteHost}"
          if [ -f "$HOME/.config/infisical-token" ]; then
            INFISICAL_TOKEN="$(cat "$HOME/.config/infisical-token")"
            export INFISICAL_TOKEN
          fi
          PASEO_PASSWORD="$(infisical secrets get PASEO_PASSWORD --plain --silent --projectId=0bd4a4d8-f58e-4bad-9d65-c16ee9aeae7e --env=prod)"
          export PASEO_PASSWORD
          exec paseo "$@"
        '';
      })
    ];
  };
}
