{
  lib,
  pkgs,
  codexCliNix,
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

  explicitOnlySkillMetadata = lib.mapAttrs' (
    name: path:
    if builtins.pathExists (path + "/agents/openai.yaml") then
      throw "Codex skill '${name}' already provides agents/openai.yaml; merge its metadata before disabling implicit invocation"
    else
      lib.nameValuePair ".codex/skills/${name}/agents/openai.yaml" {
        text = ''
          policy:
            allow_implicit_invocation: false
        '';
      }
  ) skillDirs;

in
{
  programs.codex = {
    enable = true;
    package = codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    context = import ./lib/claude-md-content.nix;
    skills = skillDirs;
  };

  # programs.codex.skills installs each value as SKILL.md. Install sibling
  # metadata separately so directory wrappers are not serialized as Markdown.
  home.file = explicitOnlySkillMetadata;
}
