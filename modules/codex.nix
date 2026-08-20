{
  lib,
  paseoSkillsSource,
  superpowersSkillsSource,
  obsidianSkillsSource,
  awsSkillsSource,
  ...
}:
let
  inherit (import ./lib/skills.nix { inherit lib; }) readSkillDirs;
  skillDirs =
    (readSkillDirs (paseoSkillsSource + "/skills"))
    // (readSkillDirs (superpowersSkillsSource + "/skills"))
    // (readSkillDirs (obsidianSkillsSource + "/skills"))
    // (readSkillDirs awsSkillsSource)
    // (readSkillDirs ../skills);

in
{
  programs.codex = {
    enable = true;
    package = null;
    context = import ./lib/claude-md-content.nix;
    skills = skillDirs;
  };
}
