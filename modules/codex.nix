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

  explicitOnlySkillDirs = lib.mapAttrs (
    name: path:
    if builtins.pathExists (path + "/agents/openai.yaml") then
      throw "Codex skill '${name}' already provides agents/openai.yaml; merge its metadata before disabling implicit invocation"
    else
      pkgs.runCommand "codex-skill-${name}" { } ''
        mkdir -p "$out"
        cp -R -L ${path}/. "$out/"
        chmod -R u+w "$out"
        mkdir -p "$out/agents"
        cp ${pkgs.writeText "openai.yaml" ''
          policy:
            allow_implicit_invocation: false
        ''} "$out/agents/openai.yaml"

        # Codex follows skill-directory symlinks but ignores a symlinked SKILL.md.
        test -f "$out/SKILL.md"
        test ! -L "$out/SKILL.md"
      ''
  ) skillDirs;

  explicitOnlySkillFiles = lib.mapAttrs' (
    name: path: lib.nameValuePair ".codex/skills/${name}" { source = path; }
  ) explicitOnlySkillDirs;

in
{
  programs.codex = {
    enable = true;
    package = codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    context = import ./lib/claude-md-content.nix;
  };

  # programs.codex.skills treats each value as SKILL.md content. Install each
  # complete skill directory instead so its metadata remains a sibling file.
  home.file = explicitOnlySkillFiles;
}
