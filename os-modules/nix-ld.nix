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
#
# nix-ld gets a binary running; it says nothing about where that binary finds
# CA certificates. Many such binaries (trunk-io's downloaded engine among
# them) link OpenSSL but carry no compiled-in trust store and don't probe
# NixOS's /etc/ssl/certs on their own, so without SSL_CERT_FILE they fail
# outbound TLS with "CERTIFICATE_VERIFY_FAILED" even though nix-ld itself
# fixed the "cannot execute" error. `curl`/`git` don't need this — they're
# nix-built and already wrapped with NIX_SSL_CERT_FILE. Both SSL_CERT_FILE
# (OpenSSL's own var) and NIX_SSL_CERT_FILE (nixpkgs' patched OpenSSL, per
# pkgs/development/libraries/openssl/*/nix-ssl-cert-file.patch) are set,
# since it's unclear upfront which one a given prebuilt binary reads.
{
  _file = ./nix-ld.nix;
  key = "nix-components-nix-ld-nixos";

  programs.nix-ld.enable = true;

  environment.variables = {
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };
}
