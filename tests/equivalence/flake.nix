{
  description = ''
    Tier 2 of the drv-equivalence harness (see plans/drv-equivalence-harness.md
    in the parent repo): instantiates every homeModule/nixosModule/darwinModule
    nix-components exports, end to end, so a refactor that silently drops or
    renames one is visible as a manifest change instead of passing unnoticed.

    Kept as its own flake with its own lock -- home-manager, nix-darwin, and
    nixvim are needed to instantiate these modules but must never enter the
    main flake's lock, since every downstream consumer would inherit them.
  '';

  inputs = {
    nix-components.url = "path:../..";
    nixpkgs.follows = "nix-components/nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixvim.url = "github:nix-community/nixvim/nixos-26.05";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nix-components,
      home-manager,
      nixvim,
      nix-darwin,
      ...
    }:
    let
      lib = nixpkgs.lib;

      homeModuleNames = builtins.attrNames nix-components.homeModules;
      nixosModuleNames = builtins.attrNames nix-components.nixosModules;
      darwinModuleNames = builtins.attrNames nix-components.darwinModules;

      # One representative system per config type rather than all four --
      # Tier 1 already proves every plain package/check/devShell/formatter
      # across all four systems; this tier exists to prove the *module
      # surface* (homeModules/nixosModules/darwinModules) instantiates and
      # stays stable, which only needs one Linux and one Darwin target.
      homeSystem = "x86_64-linux";
      nixosSystem = "x86_64-linux";
      darwinEvalSystem = "aarch64-darwin";

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ nix-components.overlays.default ];
          # claude-code-nix and codex-cli-nix are unfree; real consumers
          # (nix-mac, nix-pixelbook) already set this the same way.
          config.allowUnfree = true;
        };

      stubUser = {
        home.username = "equivalence-test";
        home.homeDirectory = "/home/equivalence-test";
        home.stateVersion = "25.05";
      };

      mkHomeConfig =
        modules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor homeSystem;
          modules = [
            nixvim.homeModules.nixvim
            { programs.nixvim.nixpkgs.source = nixpkgs; }
            stubUser
          ]
          ++ modules;
        };

      stubNixos = {
        system.stateVersion = "24.11";
        boot.loader.grub.device = "nodev";
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        # beszel-agent has no `enable` gate -- importing the module runs the
        # agent, so hubUrl/hubKey (which have no default, deliberately, since
        # they identify a real hub) must always be set to something.
        nix-components.beszel.agent.hubUrl = "http://localhost:8090";
        nix-components.beszel.agent.hubKey = "ssh-ed25519 AAAAequivalencetest";
      };

      # os-modules.nix's home-manager-backup module sets
      # `home-manager.backupFileExtension`, which only exists once
      # home-manager's own system module is imported -- real consumers
      # always pair the two.
      mkNixosConfig =
        modules:
        nixpkgs.lib.nixosSystem {
          system = nixosSystem;
          modules = [
            stubNixos
            home-manager.nixosModules.home-manager
          ]
          ++ modules;
        };

      stubDarwin = {
        system.stateVersion = 5;
        # Same beszel-agent requirement as stubNixos above.
        nix-components.beszel.agent.hubUrl = "http://localhost:8090";
        nix-components.beszel.agent.hubKey = "ssh-ed25519 AAAAequivalencetest";
      };

      mkDarwinConfig =
        modules:
        nix-darwin.lib.darwinSystem {
          system = darwinEvalSystem;
          modules = [
            stubDarwin
            home-manager.darwinModules.home-manager
          ]
          ++ modules;
        };
    in
    {
      homeConfigurations =
        (lib.listToAttrs (
          map (
            name: lib.nameValuePair "each-${name}" (mkHomeConfig [ nix-components.homeModules.${name} ])
          ) homeModuleNames
        ))
        // {
          all = mkHomeConfig (map (name: nix-components.homeModules.${name}) homeModuleNames);
        };

      nixosConfigurations.all = mkNixosConfig (
        map (name: nix-components.nixosModules.${name}) nixosModuleNames
      );

      darwinConfigurations.all = mkDarwinConfig (
        map (name: nix-components.darwinModules.${name}) darwinModuleNames
      );
    };
}
