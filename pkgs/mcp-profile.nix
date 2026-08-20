{
  profileNames ? [ ],
  fragmentDir ? "/var/empty",
  lib,
  writeShellApplication,
  jq,
  coreutils,
  ...
}:
writeShellApplication {
  name = "mcp-profile";
  runtimeInputs = [ jq coreutils ];
  text = ''
    known_profiles=(${lib.concatMapStringsSep " " lib.escapeShellArg profileNames})
    fragment_dir=${lib.escapeShellArg fragmentDir}

    if [[ "$#" -eq 0 ]]; then
      echo "Usage: mcp-profile <profile1> [<profile2> ...]" >&2
      echo "Valid profiles: ${lib.concatStringsSep ", " profileNames}" >&2
      exit 1
    fi

    is_known_profile() {
      local profile="$1"
      local known_profile

      for known_profile in "''${known_profiles[@]}"; do
        [[ "$profile" == "$known_profile" ]] && return 0
      done

      return 1
    }

    for profile in "$@"; do
      if ! is_known_profile "$profile"; then
        echo "Unknown MCP profile: $profile" >&2
        echo "Valid profiles: ${lib.concatStringsSep ", " profileNames}" >&2
        exit 1
      fi
    done

    if [[ ! -d "$fragment_dir" ]]; then
      echo "MCP profile fragments are missing: $fragment_dir" >&2
      exit 1
    fi

    claude_fragments=()
    opencode_fragments=()
    codex_fragments=()
    for profile in "$@"; do
      claude_fragment="$fragment_dir/claude-code/$profile.json"
      opencode_fragment="$fragment_dir/opencode/$profile.json"
      codex_fragment="$fragment_dir/codex/$profile.toml"

      for fragment in "$claude_fragment" "$opencode_fragment" "$codex_fragment"; do
        if [[ ! -f "$fragment" ]]; then
          echo "MCP profile fragment is missing: $fragment" >&2
          exit 1
        fi
      done

      claude_fragments+=("$claude_fragment")
      opencode_fragments+=("$opencode_fragment")
      codex_fragments+=("$codex_fragment")
    done

    claude_dir="$HOME/.config/mcp-profiles"
    codex_dir="$HOME/.codex"
    mkdir -p "$claude_dir" "$codex_dir"

    claude_temp=$(mktemp "$claude_dir/.claude-active.json.XXXXXX")
    opencode_temp=$(mktemp "$claude_dir/.opencode-active.json.XXXXXX")
    codex_temp=$(mktemp "$codex_dir/.active.config.toml.XXXXXX")
    cleanup() {
      rm -f "$claude_temp" "$opencode_temp" "$codex_temp"
    }
    trap cleanup EXIT

    jq -s '{mcpServers: (map(.mcpServers) | add)}' "''${claude_fragments[@]}" > "$claude_temp"
    jq -s '{mcp: (map(.mcp) | add)}' "''${opencode_fragments[@]}" > "$opencode_temp"
    for index in "''${!codex_fragments[@]}"; do
      [[ "$index" -eq 0 ]] || printf '\n'
      cat "''${codex_fragments[$index]}"
    done > "$codex_temp"

    mv "$claude_temp" "$claude_dir/claude-active.json"
    mv "$opencode_temp" "$claude_dir/opencode-active.json"
    mv "$codex_temp" "$codex_dir/active.config.toml"

    echo "Active MCP profiles: $*"
    echo "Start a new agent session for this change to take effect. MCP servers connect at session start."
    echo "This is a session-scoped override. The Nix-declared default returns on the next deploy."
  '';
}
