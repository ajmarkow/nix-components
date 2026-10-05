{
  lib,
  config,
  ...
}:
let
  cfg = config.programs.atuin;
  flagsStr = lib.escapeShellArgs cfg.flags;
in
{
  programs.atuin = {
    enable = true;

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

    settings = {
      sync_address = "https://atuin.tail772f0.ts.net";
    };
  };

  # Don't use enableZshIntegration: home-manager's atuin module would just
  # append `eval "$(atuin init zsh ...)"` to zsh initContent at normal
  # priority (order 1000). That's too early to survive zsh-vi-mode.
  # zsh-vi-mode (modules/zsh.nix) defers ALL of its own keybinding setup,
  # including the widgets Ctrl-R would otherwise use, to a `precmd` hook that
  # only fires at the first prompt — i.e. after the *entire* .zshrc has
  # already run. No initContent ordering can out-run that. zsh-vi-mode ships
  # `zvm_after_init_commands` for exactly this case: anything queued there
  # runs at the end of its deferred init, after its own bindkey calls, so
  # it's the only point where atuin's Ctrl-R binding reliably wins.
  programs.zsh.initContent = lib.mkOrder 1000 ''
    zvm_after_init_commands+=('eval "$(${lib.getExe cfg.package} init zsh ${flagsStr})"')
  '';
}
