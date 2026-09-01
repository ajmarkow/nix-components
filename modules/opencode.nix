{
  pkgs,
  lib,
  paseoSkillsSource,
  superpowersSkillsSource,
  obsidianSkillsSource,
  awsSkillsSource,
  ...
}:
# opencode is the second agent backend Paseo surfaces natively (alongside
# claude-code and codex — see @getpaseo/server's AGENT_HOOK_PROVIDERS). Paseo
# discovers opencode's models dynamically from opencode's own provider
# registry, so adding a custom provider here makes it selectable in Paseo's
# model picker as `opencode/<providerId>/<modelId>` with no Paseo-side
# changes.
#
# AGENTS.md content is imported from ./lib/claude-md-content.nix, the same
# plain string ./claude-code-claude-md.nix uses for CLAUDE.md — so the two
# agents share one set of rules. Import the shared string directly rather
# than reading it back out of `config.home.file.".claude/CLAUDE.md".text`:
# home-manager's programs.opencode.context folds into xdg.configFile, which
# folds back into home.file, so reading home.file here creates a real
# infinite-recursion cycle (home.file can't finish evaluating while it's
# still evaluating itself).
let
  # Same skills that feed programs.claude-code.commands in claude-code.nix
  # (via the shared ./lib/skills.nix), reshaped into opencode's `command`
  # settings schema (each skill's SKILL.md becomes a command template) so
  # both agents expose the identical set of skills as slash commands.
  # Merge precedence (later wins on name collision): paseo-skills ->
  # superpowers -> obsidian -> aws-skills -> local ../skills. Local always
  # wins. Kept identical to claude-code.nix's skillCommands chain.
  inherit (import ./lib/skills.nix { inherit lib; }) readSkills;
  skillCommands =
    (readSkills (paseoSkillsSource + "/skills"))
    // (readSkills (superpowersSkillsSource + "/skills"))
    // (readSkills (obsidianSkillsSource + "/skills"))
    // (readSkills awsSkillsSource)
    // (readSkills ../skills);
  opencodeCommands = lib.mapAttrs (_: template: { inherit template; }) skillCommands;
in
{
  programs.opencode = {
    enable = true;
    package = pkgs.opencode;
    context = import ./lib/claude-md-content.nix;
    settings = {
      command = opencodeCommands;
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
        # Only Muse Spark 1.2 Contributor should show in the /models picker
        # for the built-in Meta Muse provider.
        meta = {
          whitelist = [
            "muse-spark-1.2-contributor"
          ];
        };
        # Amazon Bedrock auto-enables whenever AWS credentials are present
        # in the environment (see opencode docs), which surfaces it in the
        # /models picker unintentionally. Empty whitelist hides every model
        # for this provider without needing to enumerate Bedrock model IDs.
        amazon-bedrock = {
          whitelist = [ ];
        };
        openrouter = {
          options.apiKey = "{env:OPENROUTER_API_KEY}";
          whitelist = [
            "google/gemma-4-31b-it:free"
            "minimax/minimax-m3:free"
            "thinkingmachines/inkling-small:free"
            "thinkingmachines/inkling:free"
            "z-ai/glm-5.2:free"
          ];
        };
      };
    };
  };
}
