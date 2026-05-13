{ config, ... }:
let
  requireEnv =
    name:
    let
      v = builtins.getEnv name;
    in
    if v == "" then builtins.throw "${name} must be set in environment" else v;
in
{
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
}
