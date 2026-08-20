{
  lib,
  writeShellApplication,
  # No usable default exists: pkgs.claude-code (nixpkgs) is unfree, and this
  # repo doesn't set config.allowUnfree, so referencing it here would break
  # this repo's own `nix flake check`/auto-exported `packages.<system>.
  # claude-mcp-wrapper` (via per-system.nix's blind `pkgs.callPackage` over
  # every pkgs/*.nix file). `null` keeps this file eval-safe for that
  # auto-export while still failing loudly -- at RUNTIME, not eval time -- if
  # anyone actually tries to run the standalone package. The real caller,
  # modules/mcp.nix, always supplies the real claude-code-nix package.
  claudeCodePackage ? null,
  ...
}:
writeShellApplication {
  name = "claude";
  text =
    if claudeCodePackage == null then
      ''
        echo "claude-mcp-wrapper: no claudeCodePackage was supplied." >&2
        echo "This package must be built via modules/mcp.nix's callPackage, not the auto-exported standalone package." >&2
        exit 1
      ''
    else
      ''
        exec "${claudeCodePackage}/bin/claude" --strict-mcp-config --mcp-config "$HOME/.config/mcp-profiles/claude-active.json" "$@"
      '';
  meta = with lib; {
    description = "Claude Code wrapped to use the active MCP profile";
    mainProgram = "claude";
  };
}
