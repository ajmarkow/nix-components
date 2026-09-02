{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.diffViewer;
  outputDir = "${config.home.homeDirectory}/diff-viewer";
  # Loopback-only backend port for static-web-server; tailscale serve proxies
  # the tailnet-facing HTTPS port (cfg.tailnetPort) to this one locally.
  # Deliberately NOT in the 18090-18093/18404 range: nix-server reserves
  # that block for its rootless-podman containers
  # (modules/containers-rootless.nix, hosts/nixos-host/default.nix firewall
  # rules). This module runs on every host (nix-mac, nix-server,
  # nix-pixelbook) via home-manager, independent of any per-host port
  # reservations, so a collision here isn't caught by that host's own
  # flake check. 18092 previously collided with nix-server's keeper
  # container: whichever process won the bind race first squatted the
  # port, and the loser crash-looped retrying forever (observed on
  # nixos-host 2026-09-02 — keeper's rootlessport couldn't bind because
  # this service's static-web-server had already claimed 127.0.0.1:18092).
  port = 28092;
  servePath = "/diffs";

  # Wrapper so the same payload runs under both launchd and systemd.user:
  # (re)register the tailscale serve path on every start (idempotent — safe
  # to repeat), then exec the local file server. `tailscale serve` requires
  # operator permission on the local tailscaled (system config:
  # nix-components.tailscale.operator, from os-modules/tailscale.nix) — until
  # that's provisioned this silently no-ops so the local server still comes up,
  # it's just unreachable over the tailnet until the grant lands.
  #
  # The registration retries in the background rather than running once. At boot
  # this service usually wins the race against tailscaled authenticating, so the
  # single attempt failed with "Logged out." and was swallowed. static-web-server
  # then stayed healthy forever, so Restart=always never fired and the serve path
  # never got registered — a service that looks up while /diffs 404s, until
  # someone restarts it by hand (observed on nixos-host 2026-08-29). Retrying
  # decouples registration from tailscaled's start order without blocking the
  # local server, which is useful on its own over 127.0.0.1.
  #
  # `--https=${tailnetPort}` is load-bearing: never let this default back to
  # 443. `tailscale serve --bg` on 443 leaves a persistent tailscaled listener
  # on the tailnet IP that survives service restarts. On a host that also
  # runs a reverse proxy (e.g. Traefik in podman) bound to the wildcard
  # address on 443, tailscaled wins the bind race at boot and the proxy can
  # never reclaim the port after any restart — which took down every routed
  # service on nixos-host on 2026-08-19. See nix-server commits 721f1f85
  # (Traefik pinned off wildcard as a partial mitigation) and a5c7a192 /
  # 4ca4996 (the deploy + rollback that triggered the outage). Fixed here by
  # keeping diff-viewer off 443 entirely.
  startScript = pkgs.writeShellScript "diff-viewer-start" ''
    (
      for _ in $(seq 1 60); do
        if ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.tailnetPort} --set-path=${servePath} ${toString port}; then
          exit 0
        fi
        sleep 5
      done
      echo "diff-viewer: tailscale serve did not register after 5 minutes; /diffs is reachable on 127.0.0.1:${toString port} only." >&2
    ) &
    exec ${pkgs.static-web-server}/bin/static-web-server \
      --host 127.0.0.1 --port ${toString port} \
      --root ${outputDir} \
      --directory-listing true \
      --log-level warn
  '';

  cleanupCmd = "${pkgs.findutils}/bin/find ${outputDir} -name '*.html' -mtime +30 -delete";

  # The whole render pipeline lives here rather than as steps in SKILL.md so
  # the agent never invokes `git` itself. That is load-bearing, not tidiness:
  # `git diff | diff2html` is silently corrupted on these hosts by two
  # independent wrappers. The rtk PreToolUse hook (modules/claude-code.nix)
  # rewrites a bare `git diff` to `rtk git diff`, and an interactive shell also
  # carries a `git` function. rtk's pretty-printer emits a human-readable
  # summary (stat lines, a "--- Changes ---" header, "+3 -3" footers) with no
  # `diff --git` headers, so diff2html parses zero files and still writes a
  # ~298KB page containing only its template. The file is written, served, and
  # returns HTTP 200 — the failure is completely silent until someone opens the
  # page and reads "Files changed (0)". Pinning git and diff2html to store
  # paths makes both wrappers unreachable, and the two assertions below turn
  # any remaining malformed input into a loud non-zero exit.
  git = "${pkgs.git}/bin/git";
  diff2html = "${pkgs.diff2html-cli}/bin/diff2html";
  decorateHtml = pkgs.writeText "diff-viewer-header.py" (
    builtins.readFile ../scripts/diff-viewer-header.py
  );

  renderScript = pkgs.writeShellApplication {
    name = "diff-viewer-render";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.python3
      pkgs.tailscale
    ];
    text = ''
      outputDir="${outputDir}"
      cssFile="$outputDir/frappe.css"

      if [ ! -d "$outputDir" ]; then
        echo "diff-viewer: $outputDir is missing — the diff-viewer home-manager module is not applied on this host." >&2
        exit 1
      fi

      if ! toplevel=$(${git} rev-parse --show-toplevel 2>&1); then
        echo "diff-viewer: not inside a git repository." >&2
        exit 1
      fi
      repo=$(basename "$toplevel")
      branch=$(${git} symbolic-ref --quiet --short HEAD || printf 'detached')
      commit=$(${git} rev-parse --short=7 HEAD)

      # Arguments are spliced into `git diff`, so they must be literal
      # git-diff arguments (--staged, main..HEAD, a path filter, or nothing).
      # A prose description makes the command malformed; let git reject it and
      # surface its own error rather than rendering something meaningless.
      tmp=$(mktemp)
      trap 'rm -f "$tmp"' EXIT
      if ! ${git} diff "$@" >"$tmp" 2>"$tmp.err"; then
        echo "diff-viewer: 'git diff $*' failed:" >&2
        cat "$tmp.err" >&2
        echo "diff-viewer: arguments must be literal git-diff arguments (e.g. --staged, main..HEAD, a path filter, or none) — not a prose description." >&2
        rm -f "$tmp.err"
        exit 1
      fi
      rm -f "$tmp.err"

      if [ ! -s "$tmp" ]; then
        echo "diff-viewer: diff is empty — nothing to render."
        exit 3
      fi

      # Precondition: an empty diff is not the only bad input. A wrapper's
      # human-readable summary is non-empty but unparseable, so require the
      # one marker that proves this is real unified-diff format.
      if ! grep -q '^diff --git' "$tmp"; then
        echo "diff-viewer: refusing to render — input is not unified diff format (no 'diff --git' header found)." >&2
        echo "diff-viewer: this is what a wrapped/pretty-printed git produces. Never pipe 'rtk git diff' into a parser." >&2
        echo "diff-viewer: first lines received:" >&2
        head -n 5 "$tmp" >&2
        exit 1
      fi

      slug=$(printf '%s' "$*" | tr -c 'A-Za-z0-9._-' '-' | sed -e 's/-\+/-/g' -e 's/^-//' -e 's/-$//')
      if [ -n "$slug" ]; then slug="-$slug"; fi
      filename="$repo$slug-$(date +%Y%m%dT%H%M%S).html"
      target="$outputDir/$filename"
      targetTmp="$outputDir/.$filename"
      trap 'rm -f "$tmp" "$targetTmp"' EXIT

      ${diff2html} -i stdin -o stdout -s side --cs dark \
        -t "$repo: git diff $*" <"$tmp" >"$targetTmp"

      # Add repository context and the Catppuccin Frappé theme to the
      # generated page. The commit button uses the browser clipboard API.
      if [ ! -f "$cssFile" ]; then
        echo "diff-viewer: warning — $cssFile missing, page will use the default theme." >&2
      fi
      python3 ${decorateHtml} "$targetTmp" \
        --css "$cssFile" --repo "$repo" --branch "$branch" --commit "$commit"

      # Post-render verification: a served 200 is not proof the render worked.
      # diff2html exits 0 and writes a full-size page even when it parsed zero
      # files, so confirm a real changed path actually reached the HTML.
      firstFile=$(${git} diff --name-only "$@" | head -n 1)
      if [ -n "$firstFile" ] && ! grep -qF "$(basename "$firstFile")" "$targetTmp"; then
        echo "diff-viewer: render verification FAILED — '$(basename "$firstFile")' is not in the generated HTML." >&2
        echo "diff-viewer: diff2html parsed no files; refusing to serve a misleading page." >&2
        exit 1
      fi

      mv "$targetTmp" "$target"

      host=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)
      if [ -z "$host" ]; then
        echo "diff-viewer: rendered $target but could not resolve this host's tailnet name." >&2
        exit 1
      fi

      echo "https://$host:${toString cfg.tailnetPort}${servePath}/$filename"
      echo "index: https://$host:${toString cfg.tailnetPort}${servePath}/"
    '';
  };
in
{
  options.services.diffViewer.tailnetPort = lib.mkOption {
    type = lib.types.port;
    default = 8443;
    description = ''
      Tailnet HTTPS port the diff-viewer skill is served on via
      `tailscale serve`. Must not be 443 — see the comment on
      `startScript` in this module for why.
    '';
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.tailnetPort != 443;
          message = ''
            services.diffViewer.tailnetPort must not be 443: tailscale serve
            --bg would then claim the tailnet IP's port 443 permanently,
            colliding with any host reverse proxy bound to the wildcard
            address. See the comment on `startScript` in
            modules/diff-viewer.nix for the incident this caused.
          '';
        }
      ];

      home.packages = [ renderScript ];

      home.file."diff-viewer/.keep".text = "";

      # Skills are deployed as slash commands (modules/lib/skills.nix reads
      # only SKILL.md), so files sitting next to a SKILL.md never reach the
      # host. Install the Catppuccin Frappé stylesheet the skill injects here
      # instead. The cleanup timer only deletes *.html, so this survives.
      home.file."diff-viewer/frappe.css".source = ../skills/diff-viewer/frappe.css;
    }
    (lib.mkIf pkgs.stdenv.isDarwin {
      launchd.agents.diff-viewer-server = {
        enable = true;
        config = {
          ProgramArguments = [ "${startScript}" ];
          RunAtLoad = true;
          KeepAlive = true;
        };
      };
      launchd.agents.diff-viewer-cleanup = {
        enable = true;
        config = {
          ProgramArguments = [
            "${pkgs.bash}/bin/bash"
            "-c"
            cleanupCmd
          ];
          StartInterval = 86400;
          RunAtLoad = false;
        };
      };
    })
    (lib.mkIf (!pkgs.stdenv.isDarwin) {
      systemd.user.services.diff-viewer-server = {
        Unit.Description = "Local static server for the diff-viewer skill, exposed via tailscale serve";
        Service = {
          ExecStart = "${startScript}";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
      systemd.user.services.diff-viewer-cleanup = {
        Unit.Description = "Delete diff-viewer HTML files older than 30 days";
        Service = {
          Type = "oneshot";
          ExecStart = cleanupCmd;
        };
      };
      systemd.user.timers.diff-viewer-cleanup = {
        Unit.Description = "Timer for diff-viewer-cleanup";
        Timer = {
          OnBootSec = "1h";
          OnUnitActiveSec = "1d";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ];
}
