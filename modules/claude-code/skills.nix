{
  lib,
  paseoSkillsSource,
  superpowersSkillsSource,
  obsidianSkillsSource,
  awsSkillsSource,
  ...
}:
let
  # readSkills is shared with opencode.nix (../lib/skills.nix) so both agents
  # expose the same set of skills as slash commands. Merge precedence (later
  # wins on name collision): paseo-skills -> superpowers -> obsidian ->
  # aws-skills -> local ../../skills. Local always wins, so any skill this repo
  # already ships (e.g. test-driven-development) keeps its local version even
  # though upstream sources also define a skill with the same name.
  inherit (import ../lib/skills.nix { inherit lib; }) readSkills;
  skillCommands =
    (readSkills (paseoSkillsSource + "/skills"))
    // (readSkills (superpowersSkillsSource + "/skills"))
    // (readSkills (obsidianSkillsSource + "/skills"))
    // (readSkills awsSkillsSource)
    // (readSkills ../../skills);
in
{
  programs.claude-code.commands = skillCommands;
}
