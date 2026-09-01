{
  pkgs,
  lib,
  config,
  ...
}:
let
  signingKey = "B9076853EC110207A2EE0D5D3D19E49D0F3BD0FA";

  ensureGitignore = pkgs.writeShellApplication {
    name = "ensure-gitignore";
    runtimeInputs = [
      pkgs.gibo
      pkgs.git
      pkgs.coreutils
    ];
    text = ''
      root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -z "$root" ]; then
        exit 0
      fi
      if [ -s "$root/.gitignore" ]; then
        exit 0
      fi
      templates=""
      if [ -f "$root/package.json" ] || [ -f "$root/pnpm-lock.yaml" ] || [ -f "$root/yarn.lock" ] || [ -f "$root/package-lock.json" ]; then
        templates="$templates Node"
      fi
      if [ -f "$root/pyproject.toml" ] || [ -f "$root/requirements.txt" ] || [ -f "$root/uv.lock" ] || [ -f "$root/poetry.lock" ] || [ -f "$root/Pipfile" ]; then
        templates="$templates Python"
      fi
      if [ -f "$root/go.mod" ]; then
        templates="$templates Go"
      fi
      if [ -f "$root/Cargo.toml" ]; then
        templates="$templates Rust"
      fi
      if [ -f "$root/Gemfile" ]; then
        templates="$templates Ruby"
      fi
      if [ -z "$(echo "$templates" | tr -d '[:space:]')" ]; then
        templates="macOS Linux Windows"
      else
        templates="$(echo "$templates" | xargs)"
      fi
      # shellcheck disable=SC2086
      if ! gibo dump $templates > "$root/.gitignore" 2>/dev/null; then
        echo "pre-commit: ensure-gitignore: gibo dump $templates failed — continuing without .gitignore" >&2
        exit 0
      fi
      if ! git -C "$root" add .gitignore 2>/dev/null; then
        echo "pre-commit: ensure-gitignore: git add .gitignore failed — continuing" >&2
      fi
      echo "pre-commit: ensure-gitignore: generated .gitignore ($templates) — review & amend if needed" >&2
    '';
  };

  trunkFmt = pkgs.writeShellApplication {
    name = "trunk-fmt";
    runtimeInputs = [
      pkgs.trunk-io
      pkgs.git
    ];
    text = ''
      staged="$(git diff --cached --name-only --diff-filter=ACMRT 2>/dev/null || true)"
      if [ -z "$staged" ]; then
        exit 0
      fi
      printf '%s\n' "$staged" | xargs -r trunk fmt
      git diff --name-only 2>/dev/null | xargs -r git add -- 2>/dev/null || true
    '';
  };
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
      # Set declaratively because `gh auth setup-git` cannot: it writes to the
      # global git config, which is a read-only /nix/store symlink.
      credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      credential."https://gist.github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
    };
  };

  xdg.configFile."git/hooks/pre-commit" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Managed by nix-components (modules/git.nix). Do not edit by hand.
      set -euo pipefail
      ${ensureGitignore}/bin/ensure-gitignore || echo "pre-commit: ensure-gitignore failed — continuing" >&2
      ${trunkFmt}/bin/trunk-fmt
      root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      local_hook="$root/.git/hooks/pre-commit"
      if [ -n "$root" ] && [ -x "$local_hook" ]; then
        exec "$local_hook"
      fi
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
