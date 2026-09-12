{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Paseo's quota fetcher reads the OAuth token from ~/.claude/.credentials.json
  # (claudeAiOauth.accessToken) or macOS Keychain — never from
  # $CLAUDE_CODE_OAUTH_TOKEN. On Linux that file normally holds only mcpOAuth,
  # so Paseo reports the account as unavailable even though the token is set
  # in the environment. Mirror the env var into the file on activation,
  # without clobbering the mcpOAuth key or an already-populated accessToken.
  home.activation.claudeCredentialsToken = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -n "''${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
      creds="${config.home.homeDirectory}/.claude/.credentials.json"
      run mkdir -p "$(dirname "$creds")"
      existing="{}"
      if [ -f "$creds" ]; then
        existing=$(${pkgs.jq}/bin/jq -c '.' "$creds" 2>/dev/null || echo "{}")
      fi
      current_token=$(printf '%s' "$existing" | ${pkgs.jq}/bin/jq -r '.claudeAiOauth.accessToken // empty')
      if [ -z "$current_token" ]; then
        ( umask 077
          printf '%s' "$existing" | ${pkgs.jq}/bin/jq -c \
            --arg token "$CLAUDE_CODE_OAUTH_TOKEN" \
            '.claudeAiOauth.accessToken = $token' > "$creds"
        )
      fi
    fi
  '';
}
