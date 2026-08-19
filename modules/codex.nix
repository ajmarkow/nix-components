{ pkgs, lib, paseoSkillsSource, superpowersSkillsSource, obsidianSkillsSource, awsSkillsSource, ... }:
# Codex CLI is the third agent backend sharing the same instructions, skills,
# and MCP servers as claude-code.nix and opencode.nix.
#
# AGENTS.md content is imported from ./lib/claude-md-content.nix, the same
# plain string ./claude-code-claude-md.nix uses for CLAUDE.md and
# opencode.nix uses for programs.opencode.context — so all three agents
# share one set of rules.
#
# Skills are installed as native Codex skills: each skill directory (SKILL.md
# plus any scripts/references/assets) is symlinked whole into
# ~/.codex/skills/<name>/, which is Codex CLI's own skill directory — Codex
# reads each SKILL.md's frontmatter (name/description) at session start and
# auto-triggers the skill's body when a request matches, with no explicit
# invocation needed. Verified empirically (2026-08-19): `codex exec` (the
# runtime paseo drives) correctly matched 5 built-in .system skills *and* a
# manually-installed copy of the superpowers `subagent-driven-development`
# skill by description alone — but only once that skill sat directly at
# ~/.codex/skills/subagent-driven-development/SKILL.md. A one-level-deeper
# path (~/.codex/skills/<scope>/<name>/SKILL.md) was silently ignored, so
# skills here are installed flat, not scoped.
#
# This replaces the older approach of flattening skills into
# ~/.codex/prompts/<name>.md `/name` slash commands: that mechanism is
# TUI-only (confirmed via `codex exec --help`, which has no slash-command
# support at all), so it was invisible to paseo and to any non-interactive
# Codex session — dead weight now that skills cover the same ground and work
# in both interactive and non-interactive sessions.
#
# lib.generators.toTOML is not available in this nixpkgs pin (checked via
# `nix eval ... lib.generators` — no toTOML attribute), so config.toml is
# hand-written here instead.
let
  # Same skills that feed programs.claude-code.commands in claude-code.nix
  # and settings.command in opencode.nix (via the shared ./lib/skills.nix).
  # Merge precedence (later wins on name collision): paseo-skills ->
  # superpowers -> obsidian -> aws-skills -> local ../skills. Local always
  # wins. Kept identical to claude-code.nix/opencode.nix's skillCommands chain.
  inherit (import ./lib/skills.nix { inherit lib; }) readSkillDirs;
  skillDirs =
    (readSkillDirs (paseoSkillsSource + "/skills")) //
    (readSkillDirs (superpowersSkillsSource + "/skills")) //
    (readSkillDirs (obsidianSkillsSource + "/skills")) //
    (readSkillDirs awsSkillsSource) //
    (readSkillDirs ../skills);

  skillFiles = lib.mapAttrs'
    (name: path: lib.nameValuePair ".codex/skills/${name}" { source = path; })
    skillDirs;

  # Codex CLI's MCP config lives in ~/.codex/config.toml under
  # [mcp_servers.<name>] tables. stdio servers use command/args(/env) here,
  # which is Codex's documented stdio schema. For remote HTTP servers
  # (context7, github) the `url = "..."` key is NOT independently verified
  # against Codex's actual schema for remote/HTTP MCP servers -- it's a
  # best-effort translation of claude-code.nix's mcpServers / opencode.nix's
  # settings.mcp values (both confirmed to hold the same URLs). Verify this
  # against current Codex CLI docs before relying on context7/github MCP
  # working through Codex.
  configToml = ''
    [mcp_servers.nixos]
    command = "uvx"
    args = ["mcp-nixos"]

    [mcp_servers.nixos.env]
    UV_PYTHON = "${pkgs.python3}/bin/python3"

    [mcp_servers.context7]
    url = "https://mcp.context7.com/mcp/oauth"

    [mcp_servers.github]
    url = "https://api.githubcopilot.com/mcp/"

    [mcp_servers.playwright]
    command = "${pkgs.playwright-mcp}/bin/playwright-mcp"
    args = ["--headless", "--isolated"]
  '';
in
{
  home.packages = [ pkgs.codex ];

  # One attrset, deliberately — see claude-code.nix's comment on why joining
  # separate home.file attrsets with `//` at the top level silently drops
  # entries. skillFiles is merged in here via `//` on the single top-level
  # home.file value, not merged with a second home.file option definition.
  home.file = {
    ".codex/AGENTS.md".text = import ./lib/claude-md-content.nix;
    ".codex/config.toml".text = configToml;
  } // skillFiles;
}
