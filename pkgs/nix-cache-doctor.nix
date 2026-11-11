{
  lib,
  writeShellApplication,
  coreutils,
  gnugrep,
  gawk,
  ...
}:
let
  caches = import ../caches.nix;
  q = lib.escapeShellArgs;
in
writeShellApplication {
  name = "nix-cache-doctor";
  runtimeInputs = [
    coreutils
    gnugrep
    gawk
  ];
  text = ''
    subs=(${q caches.substituters})
    keys=(${q caches.trustedPublicKeys})

    if [ "''${1:-}" = "--flags" ]; then
      # For the first rebuild after a cache change, when the running daemon
      # does not know the new entries yet.
      echo "--accept-flake-config --option extra-substituters '${lib.concatStringsSep " " caches.substituters}' --option extra-trusted-public-keys '${lib.concatStringsSep " " caches.trustedPublicKeys}'"
      exit 0
    fi

    cfg="$(nix config show 2>/dev/null)"
    # Normalise trailing slashes: determinate lists "https://cache.nixos.org/".
    have_subs="$(printf '%s\n' "$cfg" | awk -F' = ' '$1=="substituters"{print $2}' | tr ' ' '\n' | sed 's|/$||')"
    have_keys="$(printf '%s\n' "$cfg" | awk -F' = ' '$1=="trusted-public-keys"{print $2}' | tr ' ' '\n')"
    fail=0

    for s in "''${subs[@]}"; do
      printf '%s\n' "$have_subs" | grep -qxF "$s" || { echo "MISSING substituter: $s"; fail=1; }
    done
    for k in "''${keys[@]}"; do
      printf '%s\n' "$have_keys" | grep -qxF "$k" || { echo "MISSING key: $k"; fail=1; }
    done

    # A URL active in the daemon with no key is what prints
    # "ignoring substitute ... not signed by any of the keys".
    for s in $have_subs; do
      case "$s" in
        https://cache.flakehub.com|https://edge.cache.flakehub.com) continue ;;
      esac
      host="''${s#https://}"
      printf '%s\n' "$have_keys" | grep -qF "$host-" \
        || { echo "NO KEY for active substituter: $s"; fail=1; }
    done

    for f in "$HOME/.config/nix/nix.conf" "''${XDG_CONFIG_HOME:-$HOME/.config}/nix/nix.conf"; do
      if [ -f "$f" ] && grep -qE '^(extra-)?(substituters|trusted-public-keys)' "$f"; then
        echo "HAND-MANAGED cache settings in $f: move them into nix-components caches.nix"
        fail=1
      fi
    done

    if [ "$fail" = 0 ]; then echo "ok: all caches and keys present"; fi
    exit "$fail"
  '';
}
