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

  skillFiles = lib.mapAttrs' (
    name: path: lib.nameValuePair ".agents/skills/${name}" { source = path; }
  ) skillDirs;

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
  home.file = skillFiles // {
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
