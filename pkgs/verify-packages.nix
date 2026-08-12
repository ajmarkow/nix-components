{ writeShellApplication
, jq
, coreutils
, findutils
, gnugrep
, ...
}:

# Verifies that a host lost no packages across the claude-code.nix -> packages.nix
# migration, and that the migrated tools are supplied by the home-manager profile
# rather than by a per-host workaround, Homebrew, or the system profile.
#
#   verify-packages snapshot   # run BEFORE the migration deploys
#   verify-packages check      # run AFTER each deploy
writeShellApplication {
  name = "verify-packages";
  runtimeInputs = [ jq coreutils findutils gnugrep ];
  text = ''
    snapshot_file="''${XDG_CACHE_HOME:-$HOME/.cache}/nix-components/pkg-snapshot.json"

    # Binaries that must be provided by the home-manager profile after the migration.
    # Left side is the executable name, right side the package it comes from.
    required=(
      "rtk:rtk"
      "defuddle:defuddle"
      "nix-locate:nix-index"
      "lsof:lsof"
      "gawk:gawk"
      "rg:ripgrep"
      "uv:uv"
      "semble:semble"
      "summarize:summarize"
      "jq:jq"
      "gh:gh"
      "git:git"
    )

    # Home-manager can install to either location depending on whether it runs
    # standalone or as a NixOS/darwin module. Both count; check every one present.
    profiles=()
    for dir in "$HOME/.nix-profile" "/etc/profiles/per-user/$USER"; do
      [ -d "$dir/bin" ] && profiles+=("$dir")
    done
    if [ ''${#profiles[@]} -eq 0 ]; then
      echo "verify-packages: no home-manager profile found" >&2
      exit 1
    fi

    # Resolves a binary name to its store path within the home-manager profiles.
    # Empty output means home-manager does not provide it.
    in_profile() {
      local name=$1 prof
      for prof in "''${profiles[@]}"; do
        if [ -e "$prof/bin/$name" ]; then
          readlink -f "$prof/bin/$name"
          return 0
        fi
      done
      return 0
    }

    # name<TAB>resolved store path, for every executable across the profiles.
    enumerate() {
      local prof bin name target
      for prof in "''${profiles[@]}"; do
        for bin in "$prof"/bin/*; do
          [ -e "$bin" ] || continue
          name=$(basename "$bin")
          target=$(readlink -f "$bin" 2>/dev/null || printf '%s' "$bin")
          printf '%s\t%s\n' "$name" "$target"
        done
      done | sort -u
    }

    cmd_snapshot() {
      mkdir -p "$(dirname "$snapshot_file")"
      enumerate | jq -Rn '[inputs | split("\t") | {key: .[0], value: .[1]}] | from_entries' \
        > "$snapshot_file"
      printf 'snapshot: %s binaries -> %s\n' \
        "$(jq 'length' < "$snapshot_file")" "$snapshot_file"
    }

    cmd_check() {
      local failed=0

      # 1. No loss: every binary present at snapshot time must still be present.
      if [ -f "$snapshot_file" ]; then
        local current missing added
        current=$(enumerate | jq -Rn '[inputs | split("\t") | .[0]]')
        missing=$(jq -r --argjson cur "$current" \
          '[keys[] | select(. as $k | ($cur | index($k)) | not)] | .[]' \
          < "$snapshot_file")
        added=$(jq -rn --argjson cur "$current" --slurpfile snap "$snapshot_file" \
          '$cur - ($snap[0] | keys) | .[]')

        if [ -n "$missing" ]; then
          printf 'FAIL  packages lost since snapshot:\n'
          printf '%s\n' "$missing" | sed 's/^/        /'
          failed=1
        else
          printf 'ok    no packages lost since snapshot\n'
        fi
        if [ -n "$added" ]; then
          printf 'note  new since snapshot:\n'
          printf '%s\n' "$added" | sed 's/^/        /'
        fi
      else
        printf 'WARN  no snapshot at %s - run "verify-packages snapshot" first\n' \
          "$snapshot_file"
        printf '      skipping the no-loss check\n'
      fi

      # 2. Provenance. Compare resolved store paths, not PATH locations, so a tool
      #    still counts as home-manager-provided when PATH points straight into the
      #    store. Distinguishes "not provided" from "provided but shadowed".
      local entry name pkg provided active
      printf '\n%-12s %-10s %s\n' "BINARY" "PACKAGE" "SOURCE"
      for entry in "''${required[@]}"; do
        name=''${entry%%:*}
        pkg=''${entry#*:}
        provided=$(in_profile "$name")
        active=""
        if active=$(command -v "$name" 2>/dev/null); then
          active=$(readlink -f "$active")
        fi

        if [ -z "$provided" ]; then
          if [ -n "$active" ]; then
            printf '%-12s %-10s FAIL not from home-manager (%s)\n' "$name" "$pkg" "$active"
          else
            printf '%-12s %-10s FAIL missing entirely\n' "$name" "$pkg"
          fi
          failed=1
        elif [ "$active" != "$provided" ]; then
          # Shadowing by another store path is benign (nix-shell, devShell, agent
          # harness). Shadowing by anything outside the store - Homebrew, /usr/bin -
          # is the failure this check exists for.
          case "$active" in
            /nix/store/*)
              printf '%-12s %-10s home-manager (warn: shadowed in this shell by %s)\n' \
                "$name" "$pkg" "$active" ;;
            *)
              printf '%-12s %-10s FAIL shadowed by non-Nix %s\n' "$name" "$pkg" "$active"
              failed=1 ;;
          esac
        else
          printf '%-12s %-10s home-manager\n' "$name" "$pkg"
        fi
      done

      # 3. No non-Nix rtk: catches the Homebrew/Nix double-install on darwin.
      local rtk_paths non_nix_rtk
      rtk_paths=$(type -aP rtk 2>/dev/null | xargs -r -n1 readlink -f | sort -u || true)
      non_nix_rtk=$(printf '%s\n' "$rtk_paths" | grep -v '^/nix/store/' || true)
      printf '\n'
      if [ -z "$non_nix_rtk" ]; then
        printf 'ok    rtk comes only from Nix\n'
      else
        printf 'FAIL  rtk also provided outside Nix (Homebrew?):\n'
        printf '%s\n' "$non_nix_rtk" | sed 's/^/        /'
        failed=1
      fi

      printf '\n'
      if [ "$failed" = "0" ]; then
        printf 'PASS  all checks passed\n'
      else
        printf 'FAIL  one or more checks failed\n'
      fi
      return "$failed"
    }

    case "''${1:-}" in
      snapshot) cmd_snapshot ;;
      check)    cmd_check ;;
      *)
        printf 'usage: verify-packages {snapshot|check}\n\n'
        printf '  snapshot  record the current home-manager profile (run BEFORE deploy)\n'
        printf '  check     verify nothing was lost and tools come from home-manager\n'
        exit 2
        ;;
    esac
  '';
}
