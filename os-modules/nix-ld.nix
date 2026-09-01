# NixOS-only. Lets prebuilt, dynamically-linked Linux binaries that a tool
# downloads for itself outside the Nix store (e.g. trunk-io's `trunk fmt`,
# which fetches its own linter-engine binary on first run) find a standard
# ELF interpreter and common libraries at run time. Without it such a binary
# fails outright with "Could not start dynamically linked executable" —
# NixOS has no /lib64/ld-linux-x86-64.so.2, unlike every other distro.
#
# No nix-darwin equivalent, and none is needed: macOS binaries are native
# Mach-O, not ELF, so this failure mode doesn't exist there. Not exposed as a
# darwinModule.
#
# No options of its own: importing the module enables it, matching
# os-modules/determinate.nix. programs.nix-ld.libraries' default set (drawn
# from systemd's and Nix's own dependencies — glibc, libstdc++, zlib, etc.)
# covers most such binaries; extend it here only if a specific downloaded
# binary still fails with a missing .so.
{
  _file = ./nix-ld.nix;
  key = "nix-components-nix-ld-nixos";

  programs.nix-ld.enable = true;
}
