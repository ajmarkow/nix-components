{ lib, inputs, ... }:
let
  moduleDir = ./modules;
  entries = builtins.readDir moduleDir;
  isNixFile = name: type: type == "regular" && lib.hasSuffix ".nix" name;
  toEntry = name: lib.nameValuePair (lib.removeSuffix ".nix" name) (
    { ... }: {
      imports = [ (moduleDir + "/${name}") ];
    } // lib.optionalAttrs (name == "claude-code.nix") {
      _module.args.paseoSkillsSource = inputs.paseo-skills;
      _module.args.uv2nix = inputs.uv2nix;
      _module.args.pyprojectNix = inputs.pyproject-nix;
      _module.args.pyprojectBuildSystems = inputs.pyproject-build-systems;
      _module.args.claudeCodeNix = inputs.claude-code-nix;
    } // lib.optionalAttrs (name == "packages.nix") {
      _module.args.backlogMd = inputs.backlog-md;
    }
  );
in
{
  flake.homeModules = lib.listToAttrs (
    map toEntry (builtins.attrNames (lib.filterAttrs isNixFile entries))
  );
}
