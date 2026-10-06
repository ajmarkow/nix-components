{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.programs.atuin;
  flagsStr = lib.escapeShellArgs cfg.flags;
  managedKeyCfg = config.nix-components.atuin;
  keyPath =
    if pkgs.stdenv.isDarwin then
      "/etc/nix-darwin/secrets/atuin-key"
    else
      "/etc/nixos/secrets/atuin-key";
in
{
  # `atuin register` is what generates the encryption key in the first
  # place, and it refuses to overwrite a key_path file that already exists.
  # Registration therefore has to run once against atuin's own default
  # (~/.local/share/atuin/key) before the key can be fed into Infisical and
  # deployed by a secrets-manifest. Flipping this on too early points
  # key_path at a file that doesn't exist yet (or is root-owned 0600 with
  # nothing in it), which breaks `atuin register`/`login` rather than
  # helping them. Consumers opt in per-machine once their secrets-manifest
  # actually renders the key file — see nix-server's
  # plans/atuin-client-rollout.md for the full bootstrap sequence.
  options.nix-components.atuin.managedKey = lib.mkEnableOption "reading the atuin encryption key from the deployed secrets-manifest file";

  config.programs.atuin = {
    enable = true;

    # Disabled deliberately — see the comment on initContent below for why.
    # This option defaults to true; leaving it at the default double-runs
    # `atuin init zsh` on every shell start (harmless, just wasteful).
    enableZshIntegration = false;

    # Keep the up-arrow on normal shell/zsh-vi-mode history motion instead of
    # handing it to atuin. zsh-vi-mode already owns up/down for single-step
    # history recall (insert-mode up-arrow, normal-mode k/j); the full atuin
    # search UI stays one keystroke away on Ctrl-R, so nothing is lost.
    flags = [ "--disable-up-arrow" ];

    # Runs sync as a long-lived background process instead of on every new
    # shell, so each terminal isn't paying a tailnet round-trip on startup.
    # Home-manager wires this to systemd --user on Linux and launchd on
    # Darwin, so it works on every host this module gets imported into.
    daemon.enable = true;

    settings = lib.mkMerge [
      { sync_address = "https://atuin.tail772f0.ts.net"; }
      (lib.mkIf managedKeyCfg.managedKey { key_path = keyPath; })
    ];
  };

  # enableZshIntegration is disabled above because home-manager's default
  # integration just appends `eval "$(atuin init zsh ...)"` to zsh initContent
  # at normal priority (order 1000). That's too early to survive zsh-vi-mode.
  # zsh-vi-mode (modules/zsh.nix) defers ALL of its own keybinding setup,
  # including the widgets Ctrl-R would otherwise use, to a `precmd` hook that
  # only fires at the first prompt — i.e. after the *entire* .zshrc has
  # already run. No initContent ordering can out-run that. zsh-vi-mode ships
  # `zvm_after_init_commands` for exactly this case: anything queued there
  # runs at the end of its deferred init, after its own bindkey calls, so
  # it's the only point where atuin's Ctrl-R binding reliably wins.
  config.programs.zsh.initContent = lib.mkOrder 1000 ''
    zvm_after_init_commands+=('eval "$(${lib.getExe cfg.package} init zsh ${flagsStr})"')
  '';
}
