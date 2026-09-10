#!/usr/bin/env bash
set -euo pipefail

# The actual derivation-equivalence test: diffs drv-manifest.sh's output for
# this repo at <baseline-ref> against the working tree (Tier 1), optionally
# extended to the tests/equivalence sub-flake (Tier 2) and real downstream
# consumers (Tier 3), each with nix-components overridden to the two
# revisions being compared. No git worktree is created -- the baseline
# revision is evaluated directly via a `git+file://<repo>?rev=<sha>`
# flakeref, so there's nothing to check out or clean up.

usage() {
  cat >&2 <<'EOF'
Usage: assert-same-drvs.sh <baseline-ref> [--tier2] [--tier3 <consumer-repo>...]

  (no flags)        Tier 1 only: this repo's own packages/checks/devShells/
                     formatter, baseline vs. working tree.
  --tier2            Also compare tests/equivalence (the synthetic
                     module-instantiation sub-flake), nix-components
                     overridden to each revision in turn.
  --tier3 <repo>...  Also compare each given downstream repo's real system
                     closure, nix-components overridden to each revision.
                     A repo that fails to evaluate (e.g. not checked out) is
                     reported as a warning and skipped, not a silent pass.

Exit status is non-zero if any tier reports drift.
EOF
  exit 1
}

[ $# -ge 1 ] || usage
baseline_ref=$1
shift

run_tier2=false
tier3_repos=()
while [ $# -gt 0 ]; do
  case "$1" in
  --tier2)
    run_tier2=true
    shift
    ;;
  --tier3)
    shift
    while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do
      tier3_repos+=("$1")
      shift
    done
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    ;;
  esac
done

repo_root=$(git rev-parse --show-toplevel)
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
drv_manifest="$script_dir/drv-manifest.sh"

baseline_rev=$(git -C "$repo_root" rev-parse "$baseline_ref")
baseline_flakeref="git+file://$repo_root?rev=$baseline_rev"
current_flakeref="path:$repo_root"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

status=0

# Diffs two manifests and, for any attrpath present on both sides with a
# changed drvPath, prints a `nix derivation show -r` hint that narrows the
# mismatch down to the exact input derivation that moved -- usually one
# writeShellApplication whose text gained or lost a byte.
report() {
  local label=$1 old=$2 new=$3
  local diff_out
  if diff_out=$(diff -u "$old" "$new"); then
    echo "OK: $label -- no derivation drift"
    return
  fi
  status=1
  echo "FAIL: $label -- derivation drift detected" >&2
  echo "$diff_out" >&2
  comm -12 <(cut -d' ' -f1 "$old" | sort) <(cut -d' ' -f1 "$new" | sort) | while read -r attr; do
    old_drv=$(awk -v a="$attr" '$1==a{print $2}' "$old")
    new_drv=$(awk -v a="$attr" '$1==a{print $2}' "$new")
    if [ "$old_drv" != "$new_drv" ]; then
      echo "  hint: diff <(nix derivation show -r $old_drv | jq -S .) <(nix derivation show -r $new_drv | jq -S .)  # $attr" >&2
    fi
  done
}

echo "== Tier 1: self =="
old1="$tmpdir/tier1-old"
new1="$tmpdir/tier1-new"
"$drv_manifest" "$baseline_flakeref" >"$old1"
"$drv_manifest" "$current_flakeref" >"$new1"
report "tier1" "$old1" "$new1"

if "$run_tier2"; then
  echo "== Tier 2: tests/equivalence =="
  # `git+file://...?dir=` rather than `path:$repo_root/tests/equivalence` --
  # the latter breaks the sub-flake's own `nix-components.url = "path:../.."`
  # nested relative-path resolution when the sub-flake is addressed by an
  # absolute path: flakeref from outside its directory.
  subflake="git+file://$repo_root?dir=tests/equivalence"
  old2="$tmpdir/tier2-old"
  new2="$tmpdir/tier2-new"
  if "$drv_manifest" "$subflake" -- --override-input nix-components "$baseline_flakeref" >"$old2" 2>/dev/null &&
    "$drv_manifest" "$subflake" -- --override-input nix-components "$current_flakeref" >"$new2" 2>/dev/null; then
    report "tier2" "$old2" "$new2"
  else
    echo "WARN: tier2 (tests/equivalence) failed to evaluate, skipping" >&2
  fi
fi

for consumer in "${tier3_repos[@]}"; do
  echo "== Tier 3: $consumer =="
  if [ ! -d "$consumer" ]; then
    echo "WARN: tier3 consumer '$consumer' not found on disk, skipping" >&2
    continue
  fi
  old3="$tmpdir/tier3-old-$(basename "$consumer")"
  new3="$tmpdir/tier3-new-$(basename "$consumer")"
  if "$drv_manifest" "path:$consumer" -- --override-input nix-components "$baseline_flakeref" >"$old3" 2>/dev/null &&
    "$drv_manifest" "path:$consumer" -- --override-input nix-components "$current_flakeref" >"$new3" 2>/dev/null; then
    report "tier3:$consumer" "$old3" "$new3"
  else
    echo "WARN: tier3 consumer '$consumer' failed to evaluate, skipping" >&2
  fi
done

exit $status
