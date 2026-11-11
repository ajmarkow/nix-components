# Fails when the literal `nixConfig` in a flake.nix differs from caches.nix.
# Usage in a flake's perSystem:
#   checks.cache-parity = inputs.nix-components.lib.mkCacheParityCheck {
#     inherit pkgs; flakeNix = ./flake.nix;
#   };
{ pkgs, flakeNix }:
let
  caches = import ../caches.nix;
  expected = pkgs.writeText "expected-caches" (
    builtins.concatStringsSep "\n" (caches.substituters ++ caches.trustedPublicKeys) + "\n"
  );
in
pkgs.runCommand "cache-parity" { } ''
  # Quoted strings inside the nixConfig block that look like a cache URL or key.
  sed -n '/^[[:space:]]*nixConfig[[:space:]]*=/,/^[[:space:]]*};/p' ${flakeNix} \
    | grep -oE '"(https://[^"]+|[A-Za-z0-9.-]+-[0-9]+:[^"]+)"' \
    | tr -d '"' | sort -u > actual
  sort -u ${expected} > want

  if [ ! -s actual ]; then
    echo "no nixConfig cache entries found in flake.nix" >&2
    exit 1
  fi
  if ! diff -u want actual; then
    echo "flake.nix nixConfig differs from nix-components caches.nix (- missing, + extra)" >&2
    exit 1
  fi
  touch $out
''
