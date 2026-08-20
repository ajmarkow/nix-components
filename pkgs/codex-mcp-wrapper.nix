{
  lib,
  writeShellApplication,
  # No usable default is guaranteed: this file is auto-exported through a
  # blind `pkgs.callPackage`, so `null` keeps that evaluation safe. The real
  # caller, modules/mcp.nix, always supplies the raw codex-cli-nix package.
  codexPackage ? null,
  ...
}:
writeShellApplication {
  name = "codex";
  text =
    if codexPackage == null then
      ''
        echo "codex-mcp-wrapper: no codexPackage was supplied." >&2
        echo "This package must be built via modules/mcp.nix's callPackage, not the auto-exported standalone package." >&2
        exit 1
      ''
    else
      ''
        for arg in "$@"; do
          case "$arg" in
            --profile | --profile=*) exec "${codexPackage}/bin/codex" "$@" ;;
          esac
        done
        exec "${codexPackage}/bin/codex" --profile active "$@"
      '';
  meta = with lib; {
    description = "Codex wrapped to use the active MCP profile";
    mainProgram = "codex";
  };
}
