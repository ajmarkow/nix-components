{ lib, inputs, ... }:
let
  moduleDir = ./modules;
  entries = builtins.readDir moduleDir;
  isNixFile = name: type: type == "regular" && lib.hasSuffix ".nix" name;

  # Shared skill-source args needed by claude-code.nix, codex.nix, and
  # opencode.nix. This is a module with an explicit `key`, so when two or
  # more of those homeModules are imported together into the same user
  # config, the module system dedupes the repeated import by key instead of
  # erroring with "option _module.args.X is defined multiple times" — plain
  # reference/structural equality of an anonymous `imports` entry is not
  # enough to dedupe on its own.
  skillSourceArgs = {
    key = "nix-components-skill-source-args";
    config._module.args = {
      paseoSkillsSource = inputs.paseo-skills;
      superpowersSkillsSource = inputs.superpowers-skills;
      obsidianSkillsSource = inputs.obsidian-skills;
      awsSkillsSource = inputs.aws-skills;
    };
  };
  namesNeedingSkillArgs = [
    "claude-code.nix"
    "codex.nix"
    "opencode.nix"
  ];

  toEntry =
    name:
    lib.nameValuePair (lib.removeSuffix ".nix" name) (
      { ... }:
      {
        imports = [ (moduleDir + "/${name}") ] ++ lib.optional (builtins.elem name namesNeedingSkillArgs) skillSourceArgs;
      }
      // lib.optionalAttrs (name == "claude-code.nix") {
        _module.args.uv2nix = inputs.uv2nix;
        _module.args.pyprojectNix = inputs.pyproject-nix;
        _module.args.pyprojectBuildSystems = inputs.pyproject-build-systems;
        _module.args.claudeCodeNix = inputs.claude-code-nix;
      }
      // lib.optionalAttrs (name == "codex.nix") {
        _module.args.codexCliNix = inputs.codex-cli-nix;
      }
      // lib.optionalAttrs (name == "packages.nix") {
        _module.args.backlogMd = inputs.backlog-md;
      }
    );
in
{
  flake.homeModules = lib.listToAttrs (
    map toEntry (builtins.attrNames (lib.filterAttrs isNixFile entries))
  );
}
