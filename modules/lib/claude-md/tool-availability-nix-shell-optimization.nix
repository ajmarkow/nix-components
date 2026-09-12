''
  ## Tool Availability & nix-shell Optimization

  Run `which <tool>` before wrapping a command in nix-shell — if it exits 0, use the tool directly.

  ```bash
  rtk which curl && rtk curl https://example.com
  # only if not found:
  rtk nix-shell -p curl --run "curl https://example.com"
  ```
''
