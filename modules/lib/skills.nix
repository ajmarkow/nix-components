# Shared by claude-code.nix and opencode.nix so both agents expose the same
# set of skills as slash commands. Recursively discovers skills under `dir`:
# any directory containing a SKILL.md is a skill (keyed by its own folder
# name); directories without one are treated as containers and searched for
# skills inside them. Returns an attrset of { <skill-name> = <SKILL.md text>; }.
{ lib }:
dir:
let
  readSkills = dir:
    let
      entries = lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir);
      collect = name: _:
        let subdir = dir + "/${name}"; in
        if builtins.pathExists (subdir + "/SKILL.md")
        then { ${name} = builtins.readFile (subdir + "/SKILL.md"); }
        else readSkills subdir;
    in
    lib.foldl' (acc: entry: acc // entry) { } (lib.mapAttrsToList collect entries);
in
readSkills dir
