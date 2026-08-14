{ config, pkgs, ... }:
# opencode is the second agent backend Paseo surfaces natively (alongside
# claude-code and codex — see @getpaseo/server's AGENT_HOOK_PROVIDERS). Paseo
# discovers opencode's models dynamically from opencode's own provider
# registry, so adding a custom provider here (e.g. Muse) makes it selectable
# in Paseo's model picker as `opencode/<providerId>/<modelId>` with no
# Paseo-side changes.
#
# AGENTS.md content is sourced from the same CLAUDE.md text defined in
# ./claude-code-claude-md.nix, so the two agents share one set of rules.
{
  programs.opencode = {
    enable = true;
    package = pkgs.opencode;
    enableMcpIntegration = true;
    context = config.home.file.".claude/CLAUDE.md".text;
    settings = {
      provider = {
        muse = {
          npm = "@ai-sdk/anthropic";
          name = "Meta Muse";
          options = {
            baseURL = "https://api.meta.ai";
            # Synced from Infisical (META_MUSE_KEY) into INFISICAL_META_MUSE_KEY
            # by nix-server — never hardcode the key here.
            apiKey = "{env:INFISICAL_META_MUSE_KEY}";
          };
          models = {
            "muse-spark-1.2-contributor" = {
              name = "Muse Spark 1.2 Contributor";
            };
          };
        };
      };
      mcp = {
        nixos = {
          type = "local";
          command = [ "uvx" "mcp-nixos" ];
          environment = {
            UV_PYTHON = "${pkgs.python3}/bin/python3";
          };
        };
        context7 = {
          type = "remote";
          url = "https://mcp.context7.com/mcp/oauth";
        };
        github = {
          type = "remote";
          url = "https://api.githubcopilot.com/mcp/";
        };
        playwright = {
          type = "local";
          command = [ "${pkgs.playwright-mcp}/bin/playwright-mcp" "--headless" "--isolated" ];
        };
      };
    };
  };
}
