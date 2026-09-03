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

  # claude-code.nix and codex.nix need the raw claude/codex CLI packages. Same
  # dedupe-by-key rationale as skillSourceArgs above: separate homeModules
  # independently setting `_module.args.claudeCodeNix`/`codexCliNix` collide
  # when co-imported.
  cliPackageArgs = {
    key = "nix-components-cli-package-args";
    config._module.args = {
      claudeCodeNix = inputs.claude-code-nix;
      codexCliNix = inputs.codex-cli-nix;
    };
  };
  namesNeedingCliPackageArgs = [
    "claude-code.nix"
    "codex.nix"
  ];

  toEntry =
    name:
    lib.nameValuePair (lib.removeSuffix ".nix" name) (
      { ... }:
      {
        imports = [
          (moduleDir + "/${name}")
        ]
        ++ lib.optional (builtins.elem name namesNeedingSkillArgs) skillSourceArgs
        ++ lib.optional (builtins.elem name namesNeedingCliPackageArgs) cliPackageArgs;
      }
      // lib.optionalAttrs (name == "claude-code.nix") {
        _module.args.uv2nix = inputs.uv2nix;
        _module.args.pyprojectNix = inputs.pyproject-nix;
        _module.args.pyprojectBuildSystems = inputs.pyproject-build-systems;
        _module.args.codexPluginCcSource = inputs.codex-plugin-cc;
      }
      // lib.optionalAttrs (name == "packages.nix") {
        _module.args.backlogMd = inputs.backlog-md;
      }
      // lib.optionalAttrs (name == "git.nix") {
        _module.args.treefmtNix = inputs.treefmt-nix;
      }
    );
in
{
  flake.homeModules = lib.listToAttrs (
    map toEntry (builtins.attrNames (lib.filterAttrs isNixFile entries))
  );
}
