{ pkgs }:
# Bumps the `nix-components` flake input in the current repo, verifies the flake
# still evaluates, and commits the flake.lock change.
#
#   bump-nix-components             # update, check, commit
#   bump-nix-components --push      # ...and push, triggering CI
#   bump-nix-components --dry-run   # report what would change, touch nothing
#
# Scoped to the current working directory on purpose: it refuses to run anywhere
# that doesn't already consume nix-components, so it can never rewrite the lock
# of a repo you aren't working in.
#
# git and jq come from runtimeInputs (store paths), so neither the rtk PreToolUse
# rewrite nor a shell `git` function can alter what this script sees. `nix` is
# deliberately NOT pinned — writeShellApplication prepends runtimeInputs to $PATH
# rather than replacing it, so the host's own nix (matching its daemon) is used.
pkgs.writeShellApplication {
  name = "bump-nix-components";
  runtimeInputs = [ pkgs.git pkgs.jq pkgs.coreutils ];
  text = ''
    input="nix-components"

    usage() {
      echo "Usage: bump-nix-components [--push] [--dry-run]" >&2
      exit 1
    }

    push=false
    dry_run=false

    while [ $# -gt 0 ]; do
      case "$1" in
        --push)
          push=true
          shift
          ;;
        --dry-run)
          dry_run=true
          shift
          ;;
        -h|--help)
          usage
          ;;
        *)
          echo "Unknown argument: $1" >&2
          usage
          ;;
      esac
    done

    if ! command -v nix >/dev/null 2>&1; then
      echo "Error: nix is not on PATH." >&2
      exit 1
    fi

    if ! repo="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      echo "Error: not inside a git repository." >&2
      exit 1
    fi

    for f in flake.nix flake.lock; do
      if [ ! -f "$repo/$f" ]; then
        echo "Error: $repo has no $f — this is not a flake repo." >&2
        exit 1
      fi
    done

    # The real scope guard: a repo that doesn't already lock nix-components is
    # rejected outright rather than silently no-op'ing.
    old_rev="$(jq -r --arg i "$input" '.nodes[$i].locked.rev // empty' "$repo/flake.lock")"
    if [ -z "$old_rev" ]; then
      echo "Error: $repo does not have a '$input' input in flake.lock." >&2
      echo "Run this from a repo that consumes $input (nix-server, nix-mac, nix-pixelbook)." >&2
      exit 1
    fi

    # Refuse to fold a pre-existing lock edit into the bump commit.
    if ! git -C "$repo" diff --quiet -- flake.lock ||
       ! git -C "$repo" diff --cached --quiet -- flake.lock; then
      echo "Error: $repo/flake.lock has uncommitted changes. Commit or discard them first." >&2
      exit 1
    fi

    echo "Bumping $input in $repo (currently ''${old_rev:0:7})..."

    # Targeted update — never a bare `nix flake update`. Every consumer sets
    # nix-components.inputs.nixpkgs.follows, so this cannot move the shared
    # nixpkgs pin.
    nix flake update "$input" --flake "$repo"

    new_rev="$(jq -r --arg i "$input" '.nodes[$i].locked.rev // empty' "$repo/flake.lock")"

    if [ "$old_rev" = "$new_rev" ]; then
      echo "$input is already up to date at ''${old_rev:0:7} — nothing to commit."
      exit 0
    fi

    if [ "$dry_run" = true ]; then
      echo "[dry-run] would bump $input: ''${old_rev:0:7} -> ''${new_rev:0:7}"
      echo "[dry-run] reverting flake.lock"
      git -C "$repo" checkout -- flake.lock
      exit 0
    fi

    # Repo rule: the flake must evaluate before the commit proceeds.
    if ! nix flake check --no-build "$repo"; then
      echo >&2
      echo "Error: 'nix flake check --no-build' failed after bumping $input." >&2
      echo "flake.lock was left modified so you can inspect it. To undo:" >&2
      echo "  git -C $repo checkout -- flake.lock" >&2
      exit 1
    fi

    git -C "$repo" add flake.lock
    git -C "$repo" commit -m "chore(flake): bump $input to ''${new_rev:0:7}" \
      -m "$old_rev -> $new_rev"

    echo "Committed: $input ''${old_rev:0:7} -> ''${new_rev:0:7}"

    if [ "$push" = true ]; then
      branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
      git -C "$repo" push origin "$branch"
      echo "Pushed to origin/$branch — CI will deploy."
    else
      branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
      echo "Not pushed. To trigger CI:"
      echo "  git -C $repo push origin $branch"
    fi
  '';
}
