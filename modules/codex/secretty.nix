_: {
  # Codex CLI's native PreToolUse hook matches both shell_command and unified
  # exec_command as "Bash". For these tools, returning permissionDecision
  # "allow" with updatedInput.command replaces the command before execution.
  # The hook format and rewrite contract are documented at:
  # https://developers.openai.com/codex/hooks#pretooluse
  #
  # Keep this as one command hook. Codex starts same-event command hooks in
  # parallel and resolves competing rewrites by completion order, so a second
  # independent Bash-rewrite hook could overwrite this wrapper.
  home.file.".codex/hooks/secretty-pre-tool-use.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash

      if ! command -v secretty &>/dev/null || ! command -v jq &>/dev/null; then
        exit 0
      fi

      input=$(cat)
      command=$(jq -r '.tool_input.command // empty' <<<"$input")
      if [[ -z "$command" ]]; then
        exit 0
      fi

      # Idempotency guard: pass through commands already wrapped with secretty
      # instead of wrapping again (compounds quoting until bash fails to parse).
      if [[ "$command" =~ ^[[:space:]]*['"]?[^[:space:]'"]*secretty['"]?[[:space:]] ]]; then
        exit 0
      fi

      printf -v quoted_command '%q' "$command"
      wrapped_command="secretty --config \"\$HOME/.config/secretty/config.yaml\" --no-init-hints --strict run -- bash -c $quoted_command"

      jq -n --arg command "$wrapped_command" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "allow",
          updatedInput: { command: $command }
        }
      }'
    '';
  };

  # A user-level hooks.json is the native global hook location. Codex reviews
  # non-managed hooks by content hash before first use and after each change;
  # /hooks shows that state. This home-manager module cannot make the hook a
  # managed policy source, so it must not bypass Codex's trust review globally.
  home.file.".codex/hooks.json".text = builtins.toJSON {
    description = "Redact secrets from Codex Bash tool output before it reaches the model.";
    hooks.PreToolUse = [
      {
        matcher = "^Bash$";
        hooks = [
          {
            type = "command";
            command = ''"$HOME/.codex/hooks/secretty-pre-tool-use.sh"'';
            statusMessage = "Enabling Bash output redaction";
          }
        ];
      }
    ];
  };
}
