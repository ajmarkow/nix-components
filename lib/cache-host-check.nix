# Fails when a host's *rendered* nix settings lack a cache or key from
# caches.nix, e.g. the determinate module was dropped or overridden with
# mkForce. Pass the host's final lists:
#   NixOS:  config.nix.settings.extra-substituters / extra-trusted-public-keys
#   darwin: config.determinateNix.customSettings.<same keys>
{
  pkgs,
  substituters,
  trustedPublicKeys,
}:
let
  inherit (pkgs) lib;
  caches = import ../caches.nix;
  missing =
    (lib.subtractLists substituters caches.substituters)
    ++ (lib.subtractLists trustedPublicKeys caches.trustedPublicKeys);
in
pkgs.runCommand "cache-host-check" { } (
  if missing == [ ] then
    "touch $out"
  else
    ''
      echo "host nix settings are missing entries from nix-components caches.nix:" >&2
      printf '  %s\n' ${lib.escapeShellArgs missing} >&2
      exit 1
    ''
)
