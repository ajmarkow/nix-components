{ config, lib, ... }:
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
        };
        context7 = {
          type = "http";
          url = "https://mcp.context7.com/mcp";
          headers = {
            CONTEXT7_API_KEY = requireEnv "CONTEXT7_API_KEY";
          };
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
