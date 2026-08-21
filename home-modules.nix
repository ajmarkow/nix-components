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

  # claude-code.nix, codex.nix, and mcp.nix all need the raw claude/codex CLI
  # packages (mcp.nix's reason is below). Same dedupe-by-key rationale as
  # skillSourceArgs above: three separate homeModules independently setting
  # `_module.args.claudeCodeNix`/`codexCliNix` collide when co-imported.
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
    "mcp.nix"
  ];

  toEntry =
    name:
    lib.nameValuePair (lib.removeSuffix ".nix" name) (
      { ... }:
      {
        imports =
          [ (moduleDir + "/${name}") ]
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
      // lib.optionalAttrs (name == "mcp.nix") {
        # mcp.nix's claude/codex wrapper packages need the raw claude/codex
        # binaries directly, NOT via config.programs.claude-code.finalPackage /
        # config.programs.codex.finalPackage. mcp.nix forces those package
        # options to null while enabled so home-manager's own `home.packages =
        # lib.mkIf (cfg.package != null) [ cfg.finalPackage ];` (upstream
        # home-manager, modules/programs/claude-code.nix) does NOT also try to
        # install the raw binary -- that would collide with mcp.nix's wrapper,
        # since both provide bin/claude. finalPackage is therefore null/unset
        # for our purposes and unusable here.
      }
    );
in
{
  flake.homeModules = lib.listToAttrs (
    map toEntry (builtins.attrNames (lib.filterAttrs isNixFile entries))
  );
}
