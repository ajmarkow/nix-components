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

  implicitInvocationDisabled = pkgs.writeTextDir "agents/openai.yaml" ''
    policy:
      allow_implicit_invocation: false
  '';

  explicitOnlySkillDirs = lib.mapAttrs (
    name: path:
    if builtins.pathExists (path + "/agents/openai.yaml") then
      throw "Codex skill '${name}' already provides agents/openai.yaml; merge its metadata before disabling implicit invocation"
    else
      pkgs.symlinkJoin {
        name = "codex-skill-${name}";
        paths = [
          path
          implicitInvocationDisabled
        ];
      }
  ) skillDirs;

in
{
  programs.codex = {
    enable = true;
    package = codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    context = import ./lib/claude-md-content.nix;
    skills = explicitOnlySkillDirs;
  };
}
