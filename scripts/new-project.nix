{ pkgs }:
pkgs.writeShellApplication {
  name = "new-project";
  runtimeInputs = [
    pkgs.git
    pkgs.gh
    pkgs.coreutils
    pkgs.jq
  ];
  text = ''
    usage() {
      echo "Usage: new-project <name> [--public] [--parent <dir>] [--desc <text>] [--json]" >&2
      exit 1
    }

    name=""
    public=false
    parent="''${NEW_PROJECT_DIR:-$HOME/paseo-projects}"
    desc=""
    json=false

    while [ $# -gt 0 ]; do
      case "$1" in
        --public)
          public=true
          shift
          ;;
        --parent)
          parent="$2"
          shift 2
          ;;
        --desc)
          desc="$2"
          shift 2
          ;;
        --json)
          json=true
          shift
          ;;
        -h|--help)
          usage
          ;;
        -*)
          echo "Unknown option: $1" >&2
          usage
          ;;
        *)
          if [ -n "$name" ]; then
            echo "Unexpected argument: $1" >&2
            usage
          fi
          name="$1"
          shift
          ;;
      esac
    done

    if [ -z "$name" ]; then
      usage
    fi

    dir="$parent/$name"

    # Step 1-2: create the project directory.
    if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
      echo "Error: $dir already exists and is not empty." >&2
      exit 1
    fi
    mkdir -p "$dir"

    # Step 3: init git repo (skip if already a repo).
    if [ ! -d "$dir/.git" ]; then
      git -C "$dir" init -b main >&2
    fi

    # Step 4: seed a README so the initial commit is never empty.
    if [ ! -f "$dir/README.md" ]; then
      printf '# %s\n' "$name" > "$dir/README.md"
    fi

    # Step 5: commit — this MUST happen before `gh repo create --push`, which
    # fails with "no commits found" against an empty repo. Plain `git commit`
    # here on purpose: `cz commit` is a zsh alias for interactive shells only
    # and does not apply inside this script.
    if ! git -C "$dir" rev-parse HEAD >/dev/null 2>&1; then
      git -C "$dir" add -A
      git -C "$dir" commit -m "Initial commit" >&2
    fi

    # Step 6: resolve the GitHub owner dynamically — never hardcode it.
    owner="$(gh api user -q .login)" || {
      echo "Error: gh is not authenticated. Run 'gh auth login' first." >&2
      exit 1
    }

    # Step 7: abort if the remote repo already exists.
    if gh repo view "$owner/$name" >/dev/null 2>&1; then
      echo "Error: $owner/$name already exists on GitHub." >&2
      exit 1
    fi

    # Step 8: create the remote and push. Private by default; --public flips it.
    visibility_flag="--private"
    if [ "$public" = true ]; then
      visibility_flag="--public"
    fi

    create_args=(gh repo create "$owner/$name" "$visibility_flag" --source "$dir" --remote origin --push)
    if [ -n "$desc" ]; then
      create_args+=(--description "$desc")
    fi
    "''${create_args[@]}" >&2

    repo_url="https://github.com/$owner/$name"

    # Step 9: create a paseo workspace, warning (not failing) if paseo is missing.
    workspace_id=""
    if command -v paseo >/dev/null 2>&1; then
      ws_json="$(paseo workspace create --isolation local --path "$dir" --title "$name" --json)" || {
        echo "Warning: paseo workspace create failed; continuing without a workspace." >&2
        ws_json=""
      }
      if [ -n "$ws_json" ]; then
        workspace_id="$(echo "$ws_json" | jq -r '.workspaceId // .id // .workspace_id // empty' 2>/dev/null || true)"
      fi
    else
      echo "Warning: paseo not found on PATH; skipping workspace creation." >&2
    fi

    # Step 10: report.
    if [ "$json" = true ]; then
      jq -n --arg path "$dir" --arg repo_url "$repo_url" --arg workspace_id "$workspace_id" \
        '{$path, $repo_url, $workspace_id}'
    else
      echo "path: $dir"
      echo "repo_url: $repo_url"
      echo "workspace_id: ''${workspace_id:-<none>}"
    fi
  '';
}
