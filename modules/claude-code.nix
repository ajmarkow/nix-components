# This file must stay a top-level modules/*.nix file: home-modules.nix
# auto-exports it as homeModules.claude-code by readDir'ing this directory
# (top-level regular files only), and keys its _module.args dispatch table
# (skill sources, claudeCodeNix, codexCliNix, codexPluginCcSource, ...) on
# the literal filename "claude-code.nix". The actual content lives in
# ./claude-code/, split by concern.
#
# Deliberately `imports`, not `//`: this module used to be three attrsets
# joined with `//` in one file, which is a shallow merge — each block's
# `home` replaced the previous one, silently discarding all but the last
# block's home.file and home.packages. `imports` goes through the module
# system's own recursive config merge instead, which is what every other
# multi-file homeModule combination in this repo relies on (home-modules.nix
# importing several homeModules.* into one user config), so it cannot repeat
# that bug.
#
# CLAUDE.md is NOT defined here. It lives in ./claude-code-claude-md.nix, which
# is exported as its own home module and imported separately by consumers.
# Merging it in would define home.file.".claude/CLAUDE.md" twice and fail the
# switch. The prose itself lives in ./lib/claude-md-content.nix (shared with
# opencode.nix's AGENTS.md) — edit that file, not this one or
# claude-code-claude-md.nix.
#
# home.packages stays inline here rather than in ./claude-code/settings.nix.
# `home.packages` is a listOf option, and modules/packages.nix (imported
# alongside this module by every host that uses both, e.g. nix-server's root
# user) also defines it undivided at this file's own nesting depth. Nesting
# this definition one level deeper shifted its position in the module
# system's breadth-first same-option merge order relative to packages.nix's
# — same list membership, different concatenation order, different
# home-manager-generation bytes. Caught by scripts/assert-same-drvs.sh
# --tier3 against nix-server's real nixos-host closure (its root user imports
# both modules, tests/equivalence's synthetic "all" config happened not to
# reproduce it). See the near-identical note in modules/neovim.nix.
{
  config,
  lib,
  pkgs,
  codexCliNix,
  ...
}:
{
  # codex-plugin-cc's hooks/commands shell out to the `codex` CLI, so it must
  # be on PATH regardless of whether ./codex.nix is also imported.
  #
  # Only add the raw package when nothing else already provides bin/codex,
  # otherwise buildEnv fails with "two given paths contain a conflicting
  # subpath: .../codex-<ver>/bin/codex and .../codex/bin/codex". When
  # ./codex.nix is imported it sets programs.codex.enable = true, and upstream
  # home-manager (via programs.codex.package) installs codex already. The two
  # conditions are exact complements, so codex is always on PATH exactly once.
  home.packages = lib.optional (
    !(config.programs.codex.enable or false)
  ) codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  imports = [
    ./claude-code/skills.nix
    ./claude-code/statusline.nix
    ./claude-code/hooks.nix
    ./claude-code/credentials.nix
    ./claude-code/settings.nix
  ];
}
