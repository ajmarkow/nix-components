{ ... }:
{
  # secretty's redaction ruleset, declared here instead of left to the
  # interactive `secretty init` wizard so it's versioned and identical
  # across every host. Schema/defaults verified against secretty's own
  # internal/config/config.go and internal/config/testdata/canonical.yaml.
  #
  # Guardrail (evidence: paseo session 66521186 leaked ghp_, sk-or-v1-,
  # ctx7sk- via `ps aux | grep mcpm`): never run `ps aux` / `ps -ef`
  # unwrapped -- argv may carry live tokens. For process checks use
  # `ps -o pid,comm=` (no args column) under the secretty wrap, and rely on
  # the argv rules below to redact anything that still leaks.
  #
  # action is "placeholder" everywhere (not the default "mask" + glow
  # blocks) because this output is read by an LLM through the Claude Code
  # Bash hook, not displayed on a human's terminal — a plain
  # <REDACTED:{type}> token is what the agent should see.
  home.file.".config/secretty/config.yaml".text = ''
    version: 1

    mode: strict
    strict:
      no_reveal: true
      lock_until_exit: false
      disable_copy_original: true

    redaction:
      default_action: placeholder
      placeholder_template: "<REDACTED:{type}>"
      include_event_id: false
      rolling_window_bytes: 32768
      status_line:
        enabled: false
        rate_limit_ms: 2000

    masking:
      style: block
      block_char: "*"
      hex_random_same_length:
        uppercase: false
      stable_hash_token:
        enabled: false
        tag_len: 8
      morse_message: SECRETTY

    overrides:
      copy_without_render:
        enabled: false
        ttl_seconds: 30
        require_confirm: true
        backend: none

    allowlist:
      enabled: false
      commands: []

    ui:
      shell_banner: false

    rulesets:
      web3:
        enabled: true
        allow_bare_64hex: false
      api_keys:
        enabled: true
      auth_tokens:
        enabled: true
      cloud:
        enabled: true
      passwords:
        enabled: true

    rules:
      - name: env_private_key
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: EVM_PK
        ruleset: web3
        regex:
          pattern: "(?i)\\bPRIVATE_KEY\\s*=\\s*([^\\s]+)"
          group: 1
        context_keywords: ["private_key", "secret", "sk", "--private-key"]
      - name: api_key_label
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: API_KEY
        ruleset: api_keys
        regex:
          pattern: "(?i)\\b([A-Z0-9_]*API[_-]?KEY|x-api-key|client[_-]?secret|secret[_-]?key)\\b\\s*[:=]\\s*([A-Za-z0-9_\\-]{16,})"
          group: 2
        context_keywords: ["api_key", "x-api-key", "client_secret", "secret_key"]
      - name: stripe_key
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: API_KEY
        ruleset: api_keys
        regex:
          pattern: "\\b(sk_(live|test)_[0-9a-zA-Z]{16,})\\b"
          group: 1
      - name: github_pat
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: API_KEY
        ruleset: api_keys
        regex:
          pattern: "\\b(ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36})\\b"
          group: 0
      - name: openrouter_key
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: API_KEY
        ruleset: api_keys
        regex:
          pattern: "\\bsk-or-v1-[A-Za-z0-9]{16,}\\b"
          group: 0
      - name: context7_key
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: API_KEY
        ruleset: api_keys
        regex:
          pattern: "\\bctx7sk-[A-Za-z0-9._-]{8,}\\b"
          group: 0
      - name: mcp_remote_argv_header
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: AUTH_TOKEN
        ruleset: auth_tokens
        regex:
          pattern: "(?i)(mcp-remote[^\\n]*?--header[\\s=]+[\"']?[^\"']*(?:Bearer|Basic)\\s+)([^\\s\"']+)"
          group: 2
        context_keywords: ["mcp-remote", "--header", "Bearer"]
      - name: bearer_token
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: AUTH_TOKEN
        ruleset: auth_tokens
        regex:
          pattern: "(?i)\\bBearer\\s+([A-Za-z0-9\\-._~+/]{20,}={0,2})"
          group: 1
      - name: auth_token_label
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: AUTH_TOKEN
        ruleset: auth_tokens
        regex:
          pattern: "(?i)\\b(access|refresh|auth)[_-]?token\\b\\s*[:=]\\s*([^\\s]+)"
          group: 2
        context_keywords: ["token", "auth", "access", "refresh"]
      - name: jwt_token
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: JWT
        ruleset: auth_tokens
        regex:
          pattern: "\\b(eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+)\\b"
          group: 1
      - name: aws_access_key_id
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: CLOUD_CRED
        ruleset: cloud
        regex:
          pattern: "\\bAKIA[0-9A-Z]{16}\\b"
          group: 0
      - name: aws_secret_access_key
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: CLOUD_CRED
        ruleset: cloud
        regex:
          pattern: "(?i)\\baws_secret_access_key\\b\\s*[:=]\\s*([A-Za-z0-9/+=]{40})"
          group: 1
        context_keywords: ["aws", "secret_access_key"]
      - name: password_label
        enabled: true
        type: regex
        action: placeholder
        severity: high
        secret_type: PASSWORD
        ruleset: passwords
        regex:
          pattern: "(?i)\\b(password|passwd|pwd|passphrase)\\b\\s*[:=]\\s*([^\\s]+)"
          group: 2
        context_keywords: ["password", "pwd", "passphrase"]

    typed_detectors:
      - name: evm_private_key
        enabled: true
        kind: EVM_PRIVATE_KEY
        action: placeholder
        severity: high
        secret_type: EVM_PK
        ruleset: web3
        context_keywords: ["private_key", "--private-key", "secret", "sk="]

    debug:
      enabled: false
      log_events: false
  '';
}
