{ ... }:
{
  home.file.".claude/statusline-command.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code status line script
      #
      # Two rows:
      #   1. where you are   — directory, branch, session name, account
      #   2. how it is going — model, context meter, CI, rate limits

      input=$(cat)

      # One jq pass for every field, to keep the render cheap.
      # Unit separator, not tab: tab is IFS whitespace, so bash would collapse
      # consecutive empty fields and shift every value left.
      IFS=$'\x1f' read -r model cwd used_pct session_name limit_5h limit_7d <<<"$(
        printf '%s' "$input" | jq -r '[
          (.model | if type == "object" then .display_name else . end) // "Unknown Model",
          (.workspace.current_dir // .cwd // ""),
          (.context_window.used_percentage // ""),
          (.session_name // ""),
          (.rate_limits.five_hour.used_percentage // ""),
          (.rate_limits.seven_day.used_percentage // "")
        ] | map(tostring) | join("\u001f")'
      )"

      # Git branch (skip lock to avoid blocking)
      git_branch=""
      if git_out=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
        git_branch="$git_out"
      fi

      # GitHub CI status for the current branch.
      # Cached with a 60s TTL; refresh runs detached so the status line never blocks on gh.
      ci_state=""
      if [ -n "$git_branch" ]; then
        cache_key=$(printf '%s@%s' "$cwd" "$git_branch" | cksum | cut -d' ' -f1)
        cache_file="''${TMPDIR:-/tmp}/claude-ci-''${cache_key}"
        if [ ! -f "$cache_file" ] || [ -n "$(find "$cache_file" -mmin +1 2>/dev/null)" ]; then
          : >> "$cache_file"
          (
            # gh resolves the repo from its working directory, which is not $cwd here.
            cd "$cwd" || exit
            gh run list --limit 1 --branch "$git_branch" \
              --json status,conclusion \
              --jq '.[0] | if .status != "completed" then .status else .conclusion end' \
              2>/dev/null > "''${cache_file}.new" \
              && mv "''${cache_file}.new" "$cache_file" \
              || { rm -f "''${cache_file}.new"; touch "$cache_file"; }
          ) </dev/null >/dev/null 2>&1 &
          disown 2>/dev/null || true
        fi
        ci_state=$(head -n1 "$cache_file" 2>/dev/null)
      fi

      # ANSI colors
      RESET=$'\033[0m'
      BOLD=$'\033[1m'
      CYAN=$'\033[36m'
      GREEN=$'\033[32m'
      YELLOW=$'\033[33m'
      RED=$'\033[31m'
      DIM=$'\033[2m'

      # Dimmed pipe between groups, so the separators recede and the values stay bright.
      SEP="''${DIM}│''${RESET}"

      # Joins non-empty segments with SEP; absent fields leave no dangling separator.
      joined=""
      join_segs() {
        local seg
        joined=""
        for seg in "$@"; do
          [ -n "$seg" ] || continue
          if [ -n "$joined" ]; then joined+=" ''${SEP} ''${seg}"; else joined="$seg"; fi
        done
      }

      # Green under 50%, yellow from 50%, red from 80%.
      pct_color=""
      set_pct_color() {
        if [ "$1" -ge 80 ]; then pct_color="$RED"
        elif [ "$1" -ge 50 ]; then pct_color="$YELLOW"
        else pct_color="$GREEN"
        fi
      }

      bar_out=""
      make_bar() {
        local pct=$1 width=$2 filled i
        filled=$(( (pct * width + 50) / 100 ))
        [ "$filled" -gt "$width" ] && filled=$width
        [ "$filled" -lt 0 ] && filled=0
        bar_out=""
        for ((i = 0; i < filled; i++)); do bar_out+="█"; done
        for ((i = filled; i < width; i++)); do bar_out+="░"; done
      }

      # Context meter
      ctx_display=""
      if [ -n "$used_pct" ]; then
        ctx_int=''${used_pct%.*}
        set_pct_color "$ctx_int"
        make_bar "$ctx_int" 10
        ctx_display="''${DIM}ctx''${RESET} ''${pct_color}''${bar_out} ''${ctx_int}%''${RESET}"
      fi

      # CI status
      case "$ci_state" in
        success)                 ci_display="''${GREEN}ci ok''${RESET}" ;;
        failure|timed_out)       ci_display="''${RED}ci fail''${RESET}" ;;
        cancelled|action_required|startup_failure)
                                 ci_display="''${YELLOW}ci ''${ci_state}''${RESET}" ;;
        in_progress|queued|requested|waiting|pending)
                                 ci_display="''${YELLOW}ci running''${RESET}" ;;
        "")                      ci_display="" ;;
        *)                       ci_display="''${DIM}ci ''${ci_state}''${RESET}" ;;
      esac

      # Rate limits (Pro/Max only; each window can be absent independently)
      limits_display=""
      for window in "5h:$limit_5h" "7d:$limit_7d"; do
        label=''${window%%:*}
        value=''${window#*:}
        [ -n "$value" ] || continue
        value_int=''${value%.*}
        set_pct_color "$value_int"
        [ -n "$limits_display" ] && limits_display+=" "
        limits_display+="''${DIM}''${label}''${RESET} ''${pct_color}''${value_int}%''${RESET}"
      done

      # Session name
      session_display=""
      if [ -n "$session_name" ]; then
        session_display="''${DIM}[''${session_name}]''${RESET}"
      fi

      # Account email — read live from ~/.claude.json
      account_display=""
      account_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
      if [ -n "$account_email" ]; then
        account_display="''${DIM}''${account_email}''${RESET}"
      fi

      # Branch segment
      branch_display=""
      [ -n "$git_branch" ] && branch_display="''${DIM}''${git_branch}''${RESET}"

      # Row 1: where you are. Row 2: how it is going.
      join_segs "''${BOLD}''${CYAN}''${cwd##*/}''${RESET}" "$branch_display" "$session_display" "$account_display"
      printf '%s\n' "$joined"

      join_segs "''${GREEN}''${model}''${RESET}" "$ctx_display" "$ci_display" "$limits_display"
      printf '%s\n' "$joined"
    '';
  };
}
