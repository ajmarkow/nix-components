{ lib, inputs, ... }:
let
  moduleDir = ./modules;
  entries = builtins.readDir moduleDir;
  isNixFile = name: type: type == "regular" && lib.hasSuffix ".nix" name;
  baseModule = { nixpkgs.config.allowUnfree = true; };
  toEntry = name: lib.nameValuePair (lib.removeSuffix ".nix" name) (
    { ... }: {
      imports = [ baseModule (moduleDir + "/${name}") ];
    } // lib.optionalAttrs (name == "claude-code.nix") {
      _module.args.paseoSkillsSource = inputs.paseo-skills;
    }
  );
in
{
  flake.homeModules = lib.listToAttrs (
    map toEntry (builtins.attrNames (lib.filterAttrs isNixFile entries))
  );
}
