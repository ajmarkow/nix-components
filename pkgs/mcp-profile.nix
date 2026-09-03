{
  profileNames ? [ ],
  lib,
  writeShellApplication,
  jq,
  coreutils,
  ...
}:
# Runtime profile swap: retags which servers carry the `active` tag in mcpm's
# servers.json, so the next `mcpm profile run active` (a new agent session)
# aggregates a different set. Touches one file, shared by every agent. The
# deploy-declared default returns on the next home-manager switch (servers.json
# is a forced store symlink; this replaces it with a real file).
writeShellApplication {
  name = "mcp-profile";
  runtimeInputs = [
    jq
    coreutils
  ];
  text = ''
    known_profiles=(${lib.concatMapStringsSep " " lib.escapeShellArg profileNames})
    servers="$HOME/.config/mcpm/servers.json"

    if [[ "$#" -eq 0 ]]; then
      echo "Usage: mcp-profile <profile1> [<profile2> ...]" >&2
      echo "Valid profiles: ${lib.concatStringsSep ", " profileNames}" >&2
      exit 1
    fi

    if [[ ! -f "$servers" ]]; then
      echo "mcpm servers.json is missing: $servers" >&2
      exit 1
    fi

    is_known() {
      local p
      for p in "''${known_profiles[@]}"; do
        [[ "$1" == "$p" ]] && return 0
      done
      return 1
    }

    selected=()
    for profile in "$@"; do
      if ! is_known "$profile"; then
        echo "Unknown MCP profile: $profile" >&2
        echo "Valid profiles: ${lib.concatStringsSep ", " profileNames}" >&2
        exit 1
      fi
      # De-dupe while preserving order.
      already=false
      for s in "''${selected[@]}"; do
        [[ "$profile" == "$s" ]] && already=true && break
      done
      [[ "$already" == true ]] || selected+=("$profile")
    done

    sel_json=$(printf '%s\n' "''${selected[@]}" | jq -R . | jq -s .)

    # For each server, drop any stale `active` tag, then re-add it when the
    # server's group tags intersect the selected profiles.
    tmp=$(mktemp "$(dirname "$servers")/.servers.json.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    jq --argjson sel "$sel_json" '
      to_entries
      | map(
          .value.profile_tags = (
            ((.value.profile_tags // []) - ["active"]) as $groups
            | $groups + (if (($groups - ($groups - $sel)) | length) > 0 then ["active"] else [] end)
          )
        )
      | from_entries
    ' "$servers" > "$tmp"
    mv "$tmp" "$servers"
    trap - EXIT

    echo "Active MCP profiles: ''${selected[*]}"
    echo "Start a new agent session for this to take effect -- MCP servers connect at session start."
    echo "This is a session-scoped override. The Nix-declared default returns on the next deploy."
  '';
}
