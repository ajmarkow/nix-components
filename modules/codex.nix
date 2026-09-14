{
  config,
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
    name: path: lib.nameValuePair ".agents/skills/${name}" { source = path; }
  ) explicitOnlySkillDirs;

  codexConfig = (pkgs.formats.toml { }).generate "codex-config" config.programs.codex.settings;

in
{
  imports = [
    ./codex/secretty.nix
    # The hook above deliberately resolves secretty from PATH, but it needs the
    # shared declarative ruleset too. Import both parts transitively so a host
    # cannot deploy the wrapper while forgetting its full configuration.
    ./secretty.nix
  ];

  programs.codex = {
    enable = true;
    package = codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    context = import ./lib/claude-md-content.nix;
    settings.features.hooks = true;
  };

  # Codex keeps project trust in config.toml. The upstream module manages this
  # file as a Nix-store symlink, which makes the TUI fail when it saves trust.
  # Seed it once as a writable file and leave Codex-owned state intact.
  home.file = explicitOnlySkillFiles // {
    ".codex/config.toml".enable = lib.mkForce false;
  };

  home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config_file="${config.home.homeDirectory}/.codex/config.toml"
    if [ -L "$config_file" ]; then
      run rm "$config_file"
    fi
    if [ ! -e "$config_file" ]; then
      run mkdir -p "$(dirname "$config_file")"
      run install -m600 "${codexConfig}" "$config_file"
    fi
  '';
}
