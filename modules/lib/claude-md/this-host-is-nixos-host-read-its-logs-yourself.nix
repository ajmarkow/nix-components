''
  ## This Host Is nixos-host — Read Its Logs Yourself

  **When working in nix-server or nix-components, you are already running on the machine those repos configure.** Inspecting its services, containers, and logs is local work, not SSH — do it yourself instead of asking the user to paste output.

  Read-only channels available to the `paseo` user:

  | What | How |
  |---|---|
  | Any service's logs | `journalctl -u <unit> --since "10 min ago" --no-pager` — no sudo (`paseo` is in `systemd-journal`) |
  | Any container's stdout | `journalctl CONTAINER_NAME=<name>` |
  | `containers`-user rootless containers | `/run/wrappers/bin/sudo -u containers podman-logs-ro {logs,ps,inspect}` |
  | paseo's own rootless containers | bare `podman logs/ps/inspect` |

  `podman-logs-ro` is NOPASSWD-allowlisted to `logs`, `ps`, and `inspect` only, so it needs no approval. Two silent gotchas: use the absolute `/run/wrappers/bin/sudo` (plain `sudo` can resolve to the non-setuid copy), and run it from a world-readable cwd like `/tmp` — the `containers` user cannot chdir into the repo and fails with a misleading `Permission denied`. Source: `podmanLogsRo` in nix-server's `modules/paseo.nix`.

  **When debugging a service behind Traefik, check the backend's own health — never conclude from the proxy layer alone that the service is up.** An Authelia redirect (302 to `auth.aj-cloud.cc`) is issued before Traefik contacts the backend at all, so a completely dead service returns exactly the same 302, and the login page's own 200 is not evidence either. Confirm against the container's health (`podman-logs-ro ps`) and the status codes Traefik actually returned (`journalctl CONTAINER_NAME=traefik | grep RequestHost`), which expose the 5xx a redirect hides.
''
