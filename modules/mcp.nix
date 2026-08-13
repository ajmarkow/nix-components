{ config, lib, pkgs, ... }:
let
  cfg = config.nix-components.mcp;
  requireEnv = name: builtins.getEnv name;
in
{
  options.nix-components.mcp = {
    enable = lib.mkEnableOption "MCP server configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.mcp = {
      enable = true;
      servers = {
        nixos = {
          command = "uvx";
          args = [ "mcp-nixos" ];
          # uvx defaults to downloading its own dynamically-linked CPython build,
          # which can't run on NixOS without nix-ld. Point it at a nixpkgs Python
          # instead so it works on every host without extra system config.
          env = {
            UV_PYTHON = "${pkgs.python3}/bin/python3";
          };
        };
        context7 = {
          type = "http";
          url = "https://mcp.context7.com/mcp";
          headers = {
            CONTEXT7_API_KEY = requireEnv "CONTEXT7_API_KEY";
          };
        };
        playwright = {
          command = "npx";
          args = [ "@playwright/mcp@latest" ];
        };
        wezterm-mcp = {
          command = "npx";
          args = [ "-y" "wezterm-mcp" ];
        };
        "long-term-memory" = {
          command = "node";
          args = [
            "${config.home.homeDirectory}/.config/long-term-memory/src/index.js"
          ];
          env = {
            MEM0_API_KEY = requireEnv "MEM0_API_KEY";
          };
        };
      };
    };
  };
}
