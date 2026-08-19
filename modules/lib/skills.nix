# Shared by claude-code.nix, opencode.nix, and codex.nix so all three agents
# expose the same set of skills. Recursively discovers skills under `dir`:
# any directory containing a SKILL.md is a skill (keyed by its own folder
# name); directories without one are treated as containers and searched for
# skills inside them.
{ lib }:
let
  # Returns an attrset of { <skill-name> = <path to the skill's directory>; }.
  # codex.nix uses this to symlink whole skill directories (SKILL.md plus any
  # scripts/references/assets) into ~/.codex/skills/<name>/.
  readSkillDirs = dir:
    let
      entries = lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir);
      collect = name: _:
        let subdir = dir + "/${name}"; in
        if builtins.pathExists (subdir + "/SKILL.md")
        then { ${name} = subdir; }
        else readSkillDirs subdir;
    in
    lib.foldl' (acc: entry: acc // entry) { } (lib.mapAttrsToList collect entries);
in
{
  # Returns an attrset of { <skill-name> = <SKILL.md text>; }, used by
  # claude-code.nix's `commands` and opencode.nix's `command` to expose
  # skills as slash commands.
  readSkills = dir: lib.mapAttrs (_: path: builtins.readFile (path + "/SKILL.md")) (readSkillDirs dir);

  inherit readSkillDirs;
}
