{
  description = "Reusable Nix modules shared across multiple host configurations";

  inputs = { };

  outputs =
    { self, ... }:
    {
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
}
