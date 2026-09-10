#!/usr/bin/env bash
set -euo pipefail

# Emits sorted "<attrpath> <drvPath>" lines for a flakeref -- the manifest
# that assert-same-drvs.sh diffs across two revisions or two
# --override-input states. Pure evaluation only, no builds: a derivation
# path is input-addressed and recursive, so drvPath equality alone proves
# the whole closure beneath it is byte-identical.
#
# Works unmodified against both the main nix-components flake (Tier 1:
# packages/checks/devShells/formatter) and the tests/equivalence sub-flake
# (Tier 2: homeConfigurations/nixosConfigurations/darwinConfigurations) --
# each flake only has some of these groups populated, and empty/missing
# groups are skipped silently.

usage() {
  cat >&2 <<'EOF'
Usage: drv-manifest.sh <flakeref> [-- <extra nix eval args...>]

Extra args (e.g. `-- --override-input nix-components <ref>`) are passed
through to every `nix eval` call.
EOF
  exit 1
}

[ $# -ge 1 ] || usage
flakeref=$1
shift
if [ "${1:-}" = "--" ]; then
  shift
fi
extra_args=("$@")

systems=(x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin)
per_system_groups=(packages checks devShells)

eval_names() {
  nix eval --json "${extra_args[@]}" "$1" --apply builtins.attrNames 2>/dev/null | jq -r '.[]?' || true
}

# Flat (not per-system) groups, each with its own path down to a real
# derivation -- a nixosSystem/darwinSystem/homeManagerConfiguration result
# is an attrset, not a derivation, so `.drvPath` alone doesn't resolve.
declare -A flat_suffix=(
  [homeConfigurations]="activationPackage.drvPath"
  [nixosConfigurations]="config.system.build.toplevel.drvPath"
  [darwinConfigurations]="config.system.build.toplevel.drvPath"
)

{
  for system in "${systems[@]}"; do
    for group in "${per_system_groups[@]}"; do
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        drv=$(nix eval --raw "${extra_args[@]}" "${flakeref}#${group}.${system}.${name}.drvPath" 2>/dev/null) || continue
        printf '%s.%s.%s %s\n' "$system" "$group" "$name" "$drv"
      done < <(eval_names "${flakeref}#${group}.${system}")
    done

    drv=$(nix eval --raw "${extra_args[@]}" "${flakeref}#formatter.${system}.drvPath" 2>/dev/null) || drv=""
    [ -n "$drv" ] && printf '%s.formatter %s\n' "$system" "$drv"
  done

  for group in "${!flat_suffix[@]}"; do
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      drv=$(nix eval --raw "${extra_args[@]}" "${flakeref}#${group}.${name}.${flat_suffix[$group]}" 2>/dev/null) || continue
      printf '%s.%s %s\n' "$group" "$name" "$drv"
    done < <(eval_names "${flakeref}#${group}")
  done
} | sort
