{ pkgs, lib, config, ... }:
let
  signingKey = "B9076853EC110207A2EE0D5D3D19E49D0F3BD0FA";
in
{
  programs.git = {
    enable = true;
    signing = {
      key = signingKey;
      signByDefault = true;
    };
    settings = {
      user.name = "AJ Markow";
      user.email = "alexanderjmarkow@gmail.com";
      gpg.program = "${pkgs.gnupg}/bin/gpg";
      rerere.enabled = true;
      init.defaultBranch = "main";
      pull.rebase = true;
      diff.algorithm = "histogram";
      fetch.prune = true;
      push.autoSetupRemote = true;
      core.pager = "delta";
      core.hooksPath = "${config.xdg.configHome}/git/hooks";
      interactive.diffFilter = "delta --color-only";
      delta.navigate = true;
      delta.line-numbers = true;
      merge.conflictstyle = "diff3";
    };
  };

  # --- Managed global pre-commit hook ---
  # Runs `nix flake check --no-build` ONLY in a flake repo with staged .nix
  # files. Every other commit is a fast no-op. Chains to a repo-local hook so
  # it never shadows one. Bypass with `git commit --no-verify`.
  xdg.configFile."git/hooks/pre-commit" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Managed by nix-components (modules/git.nix). Do not edit by hand.
      set -euo pipefail

      root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

      if [ -n "$root" ] && [ -f "$root/flake.nix" ]; then
        if [ -n "$(git diff --cached --name-only -- '*.nix')" ]; then
          echo "pre-commit: staged .nix in a flake — running 'nix flake check --no-build'…"
          if ! nix flake check --no-build "$root"; then
            echo "pre-commit: flake check FAILED — commit aborted." >&2
            echo "  Fix the errors above, or bypass with: git commit --no-verify" >&2
            exit 1
          fi
          echo "pre-commit: flake check passed."
        fi
      fi

      # Preserve any repo-local hook (global hooksPath would otherwise skip it).
      local_hook="$root/.git/hooks/pre-commit"
      if [ -n "$root" ] && [ -x "$local_hook" ]; then
        exec "$local_hook"
      fi
      exit 0
    '';
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    defaultCacheTtl = 14400;
    maxCacheTtl = 14400;
    pinentry.package = lib.mkIf pkgs.stdenv.isDarwin pkgs.pinentry_mac;
  };
}
