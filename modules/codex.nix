{
  pkgs,
  lib,
  paseoSkillsSource,
  superpowersSkillsSource,
  obsidianSkillsSource,
  awsSkillsSource,
  codexCliNix,
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
    name: path: lib.nameValuePair ".codex/skills/${name}" { source = path; }
  ) skillDirs;

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
  home.packages = [ codexCliNix.packages.${pkgs.stdenv.hostPlatform.system}.default ];

  home.file = {
    ".codex/AGENTS.md".text = import ./lib/claude-md-content.nix;
    ".codex/config.toml".text = configToml;
  }
  // skillFiles;
}
