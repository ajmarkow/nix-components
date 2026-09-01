{
  pkgs,
  lib,
  config,
  treefmtNix,
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

  # One shared, Nix-native formatter for every repo this hook touches — no
  # per-repo config file, no network fetch, no foreign binary running under
  # nix-ld. Every formatter listed is a plain nixpkgs derivation; the config
  # is baked into the wrapper at build time (treefmt-nix's `mkWrapper`), so
  # there is nothing to init and nothing that can drift out of date the way
  # a committed .trunk/trunk.yaml version pin did (see git history: it
  # pinned a trunk CLI release that trunk.io later stopped serving, breaking
  # every commit until someone noticed).
  #
  # projectRootFile defaults to ".git/config" (treefmt-nix's own default),
  # which every plain git repo has — no flake.nix required in the target
  # repo, since this hook also runs in non-Nix repos (aj-website,
  # judith-website, ...).
  treefmtWrapper =
    (treefmtNix.lib.evalModule pkgs {
      programs = {
        nixfmt.enable = true;
        shfmt.enable = true;
        prettier.enable = true; # JS/TS/JSON/YAML/Markdown/CSS/HTML
        ruff-format.enable = true;
        rustfmt.enable = true;
        gofmt.enable = true;
        stylua.enable = true;
        taplo.enable = true; # TOML
        rufo.enable = true; # Ruby
      };
      # enableDefaultExcludes (on by default) already covers *.lock,
      # package-lock.json, go.{mod,sum}, .git{ignore,attributes,modules},
      # LICENSE. These are directories no formatter should ever walk into.
      settings.excludes = [
        "node_modules/**"
        "dist/**"
        "build/**"
        ".direnv/**"
        "result/**"
        ".worktrees/**"
        ".playwright-mcp/**"
      ];
    }).config.build.wrapper;

  repoFmt = pkgs.writeShellApplication {
    name = "repo-fmt";
    runtimeInputs = [
      treefmtWrapper
      pkgs.git
    ];
    text = ''
      staged="$(git diff --cached --name-only --diff-filter=ACMRT 2>/dev/null || true)"
      if [ -z "$staged" ]; then
        exit 0
      fi
      printf '%s\n' "$staged" | xargs -r treefmt --
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
      ${repoFmt}/bin/repo-fmt
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
