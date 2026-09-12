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
{ ... }:
{
  imports = [
    ./claude-code/skills.nix
    ./claude-code/statusline.nix
    ./claude-code/hooks.nix
    ./claude-code/credentials.nix
    ./claude-code/settings.nix
  ];
}
