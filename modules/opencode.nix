{ pkgs, ... }:
# opencode is the second agent backend Paseo surfaces natively (alongside
# claude-code and codex — see @getpaseo/server's AGENT_HOOK_PROVIDERS). Paseo
# discovers opencode's models dynamically from opencode's own provider
# registry, so adding a custom provider here makes it selectable in Paseo's
# model picker as `opencode/<providerId>/<modelId>` with no Paseo-side
# changes. Meta Muse ships as a built-in opencode provider already, so it
# does not need to be defined by hand here.
#
# AGENTS.md content is imported from ./lib/claude-md-content.nix, the same
# plain string ./claude-code-claude-md.nix uses for CLAUDE.md — so the two
# agents share one set of rules. Import the shared string directly rather
# than reading it back out of `config.home.file.".claude/CLAUDE.md".text`:
# home-manager's programs.opencode.context folds into xdg.configFile, which
# folds back into home.file, so reading home.file here creates a real
# infinite-recursion cycle (home.file can't finish evaluating while it's
# still evaluating itself).
{
  programs.opencode = {
    enable = true;
    package = pkgs.opencode;
    enableMcpIntegration = true;
    context = import ./lib/claude-md-content.nix;
    settings = {
      provider = {
        # Only the free OpenCode Zen models should show in the /models
        # picker for the built-in opencode (Zen) provider.
        opencode = {
          whitelist = [
            "big-pickle"
            "deepseek-v4-flash-free"
            "mimo-v2.5-free"
            "hy3-free"
            "laguna-s-2.1-free"
            "nemotron-3-ultra-free"
            "nemotron-3.5-lightning-free"
          ];
        };
        # Amazon Bedrock auto-enables whenever AWS credentials are present
        # in the environment (see opencode docs), which surfaces it in the
        # /models picker unintentionally. Empty whitelist hides every model
        # for this provider without needing to enumerate Bedrock model IDs.
        amazon-bedrock = {
          whitelist = [ ];
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
