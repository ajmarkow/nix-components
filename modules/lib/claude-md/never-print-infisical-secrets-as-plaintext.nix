''
  ## ⚠️ NEVER Print Infisical Secrets as Plaintext

  Never run an `infisical` command that outputs secret values in plaintext, including `infisical export` (default, and with `--format=dotenv-export`, `json`, or `yaml`) and `infisical secrets get ... --plain`. These print secret values to stdout unless piped straight to a consumer that doesn't echo them.

  As a backstop, every Bash command also runs through `secretty`, which redacts common secret patterns (API keys, tokens, passwords, cloud credentials) from its output — treat this as a safety net, not permission to print secrets deliberately.
''
