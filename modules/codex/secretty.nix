{ ... }: {
  # Codex CLI's native PreToolUse hook matches both shell_command and unified
  # exec_command as "Bash". Returning permissionDecision "allow" with
  # updatedInput.command replaces the command before execution, and exit 2
  # denies the call. The hook format, matcher patterns, and exit-code
  # contract are documented at:
  # https://developers.openai.com/codex/hooks#pretooluse
  #
  # This file holds both Bash-layer hooks. The deny class runs inside the
  # secretty wrapper script (checked before wrapping so denied commands
  # never execute) because Codex starts same-event command hooks in
  # parallel and resolves competing rewrites by completion order — a
  # second independent Bash-rewrite hook could overwrite this wrapper.
  home.file.".codex/hooks/secretty-pre-tool-use.sh" = {
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
      # Checked for deny first below via scan_command, which unwraps one
      # secretty layer so deny checks see the inner command.
      scan_command="$command"
      if [[ "$command" =~ ^[[:space:]]*['"]?[^[:space:]'"]*secretty['"]?[[:space:]] ]]; then
        scan_command=$(printf '%s' "$command" | sed -E 's/^.*bash +-c +//' | sed -E "s/^'//; s/'[[:space:]]*$//")
        [ -z "$scan_command" ] && exit 0
      fi

      # Deny class shared with Claude Code's block-ssh-rg-cd.sh (exit 2
      # blocks the call in Codex too). Checked before the secretty wrap so
      # denied commands never execute. Keep the git carve-out for ssh: git
      # cannot open an interactive host connection and routinely carries
      # "ssh" as free text.
      deny() {
        echo "Blocked: $1" >&2
        exit 2
      }

      if echo "$scan_command" | grep -Eq '(^|[;&|(|`$]|\s)rg\b'; then
        deny "use rtk semble search instead of rg."
      fi
      NONGIT_SCAN=$(printf '%s' "$scan_command" | sed -E 's/git[[:space:]]+(grep|egrep|fgrep)/git-GREP-EXEMPT/g')
      if echo "$NONGIT_SCAN" | grep -Eq '(^|[;&|(|`$]|\s)(grep|egrep|fgrep)[[:space:]]+[^;&|]*-[a-zA-Z]*[rR]'; then
        deny "use rtk semble search instead of grep -r."
      fi
      if echo "$scan_command" | grep -Eq '(^|[;&|(|`$]|\s)find[[:space:]]+[^;&|]*-name\b'; then
        deny "use rtk semble search instead of find -name."
      fi
      if echo "$scan_command" | grep -Eq '(^|[;&|(|`$]|\s)ps[[:space:]]+(aux[[:alnum:]]*|u[[:alnum:]]*|-([[:alnum:]]*[fF][[:alnum:]]*|[[:alnum:]]*u[[:alnum:]]*))([^[:alnum:]_]|$)' \
        && ! echo "$scan_command" | grep -Eq '(^|[;&|(|`$]|\s)ps[[:space:]]+[^;&|]*-o[[:space:]]'; then
        deny "no argv-revealing ps (ps aux / ps -ef). Use ps -o pid,comm= instead."
      fi
      if echo "$scan_command" | grep -Eq '(>>?|>)\s*[^;&|]*\.codex/[^;&| ]*memory|>>?\s*[^;&|]*/memory/'; then
        deny "no shell writes to auto-memory (prompt must contain explicit remember approval)."
      fi
      if echo "$scan_command" | grep -Eq '(^|[;&|(|`$]|\s)(nixos-rebuild|home-manager)[[:space:]]+switch\b'; then
        deny "never rebuild locally — commit+push, CI deploys."
      fi
      scan=$(printf '%s' "$scan_command" | sed -E 's/^[[:space:]]*GIT_SSH_COMMAND=("[^"]*"|[^[:space:]]*)[[:space:]]*//')
      case "$scan" in
        git\ *|rtk\ git\ *|/*/git\ *) ;;
        *)
          if echo "$scan" | grep -Eq '(^|[^[:alnum:]._-])(ssh|scp|sftp)([[:space:]]|$)'; then
            deny "no direct ssh/scp/sftp to a host. ssh-add, ssh-keygen, .ssh/ paths and git commands are allowed."
          fi
          ;;
      esac

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

  # Memory guard (deny-only: exit 2, never rewrites, so no race with the
  # wrapper above despite Codex starting same-event hooks concurrently)
  # lives in ./memory-guard.nix; both matchers are wired into hooks.json
  # below. Same file so deny script and wiring cannot drift apart.
  home.file = {
    ".codex/hooks/memory-guard.sh" = {
      executable = true;
      text = builtins.readFile ./memory-guard.sh;
    };

    ".codex/hooks.json".text = builtins.toJSON {
      description = "Redact secrets from Codex Bash tool output before it reaches the model; guard memory and instruction-file writes.";
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
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = ''"$HOME/.codex/hooks/memory-guard.sh"'';
              statusMessage = "Guarding memory and instruction files";
            }
          ];
        }
      ];
    };
  };
}
