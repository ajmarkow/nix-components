{
  description = "Reusable Nix modules shared across multiple host configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [ ./packages.nix ];

      flake = {
        homeModules = {
          claude-code = ./modules/claude-code.nix;
          firefox = ./modules/firefox.nix;
          git = ./modules/git.nix;
          git-macos = ./modules/git-macos.nix;
          mcp = ./modules/mcp.nix;
          neovim = ./modules/neovim.nix;
          neovim-wezterm = ./modules/neovim-wezterm.nix;
          packages = ./modules/packages.nix;
          starship = ./modules/starship.nix;
          wezterm = ./modules/wezterm.nix;
          zsh = ./modules/zsh.nix;
          zsh-macos = ./modules/zsh-macos.nix;
        };
      };
    };
}
