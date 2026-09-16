# This file must stay a top-level modules/*.nix file: home-modules.nix
# auto-exports it as homeModules.reflect by readDir'ing this directory
# (top-level regular files only). The hook script, settings wiring, and
# switch are all in this one file so the feature can be enabled or removed
# by adding or dropping a single import line.
#
# What it does: deploys the reflect capture hook (UserPromptSubmit) that
# POSTs detected corrections as JSON items to the private queue issue in
# the reflections-queue repo. The capture script is vendored from
# ajmarkow/claude-reflect branch reflect/declarative
# (scripts/capture_learning.py + the kept parts of
# scripts/lib/reflect_utils.py); only the dependency-free capture path is
# vendored here, never the deleted file-queue or routing code.
#
# Inert by default: `nix-components.reflect.enable` defaults to false, and
# even when enabled an empty `captureRepos` allowlist captures nothing.
# The token reaches the hook only through `tokenFile` (0600, rendered by
# the host's Infisical manifest as reflect-capture.env) — never through
# sessionVariables or the Nix store.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-components.reflect;

  # Vendored from ajmarkow/claude-reflect (reflect/declarative):
  # detect_patterns + pattern tables + create_queue_item +
  # should_include_message + normalize_repo_identity + deny list.
  # Pure logic, no file I/O, no network.
  reflectUtils = pkgs.writeText "reflect_utils.py" ''
    import re
    import uuid
    from datetime import datetime, timezone
    from typing import Dict, List, Optional, Tuple
    from urllib.parse import urlsplit


    def iso_timestamp() -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


    EXPLICIT_PATTERNS = [
        (r"remember:", "remember:", 0.90, 120),
    ]

    POSITIVE_PATTERNS = [
        (r"perfect!|exactly right|that's exactly", "perfect", 0.70, 90),
        (r"that's what I wanted|great approach", "great-approach", 0.70, 90),
        (r"keep doing this|love it|excellent|nailed it", "keep-doing", 0.70, 90),
    ]

    CORRECTION_PATTERNS = [
        (r"^no[,. ]+", "no,", True),
        (r"^don't\b|^do not\b", "don't", True),
        (r"^stop\b|^never\b", "stop/never", True),
        (r"that's (wrong|incorrect)|that is (wrong|incorrect)", "that's-wrong", True),
        (r"^actually[,. ]", "actually", False),
        (r"^I meant\b|^I said\b", "I-meant/said", True),
        (r"^I told you\b|^I already told\b", "I-told-you", True),
        (r"use .{1,30} not\b", "use-X-not-Y", True),
    ]

    GUARDRAIL_PATTERNS = [
        (r"don't (?:add|include|create) .{1,40} unless", "dont-unless-asked", 0.90, 120),
        (r"only (?:change|modify|edit|touch) what I (?:asked|requested|said)", "only-what-asked", 0.90, 120),
        (r"stop (?:refactoring|changing|modifying|editing) (?:unrelated|other|surrounding)", "stop-unrelated", 0.90, 120),
        (r"don't (?:over-engineer|add extra|be too|make unnecessary)", "dont-over-engineer", 0.85, 90),
        (r"don't (?:refactor|reorganize|restructure) (?:unless|without)", "dont-refactor-unless", 0.85, 90),
        (r"leave .{1,30} (?:alone|unchanged|as is)", "leave-alone", 0.85, 90),
        (r"don't (?:add|include) (?:comments|docstrings|type hints|annotations) (?:unless|to code)", "dont-add-annotations", 0.85, 90),
        (r"(?:minimal|minimum|only necessary) changes", "minimal-changes", 0.80, 90),
    ]

    FALSE_POSITIVE_PATTERNS = [
        r"[?\uff1f]$",
        r"[\u55ce\u5417\u5462\u304b\uae4c]$",
        r"^(please|can you|could you|would you|help me)\b",
        r"(help|fix|check|review|figure out|set up)\s+(this|that|it|the)\b",
        r"(error|failed|could not|cannot|can't|unable to)\s+\w+",
        r"(is|was|are|were)\s+(not|broken|failing)",
        r"^I (need|want|would like)\b",
        r"^(ok|okay|alright)[,.]?\s+(so|now|let)",
    ]

    NON_CORRECTION_PHRASES = [
        r"^no\s+problem",
        r"^no\s+worries",
        r"^no\s+need\b",
        r"^no\s+way\b",
        r"^don't\s+worry",
        r"^don't\s+mind",
        r"^don't\s+bother",
        r"^never\s+mind",
        r"^stop\s+worrying",
    ]

    CJK_CORRECTION_PATTERNS = [
        (r"^いや[、,.\s]|^いや違", "iya", True),
        (r"^違う[、，,.\s！!。]|^ちがう[、,.\s]", "chigau", True),
        (r"そうじゃなく[てけ]|そっちじゃなく[てけ]", "souja-nakute", True),
        (r"間違[いえっ]て", "machigatte", True),
        (r"じゃなくて.{0,30}にして", "janakute-nishite", True),
        (r"^やめて[。！!]?\s*$", "yamete", True),
        (r"^そうじゃない", "souja-nai", True),
        (r"って言った[のよでじゃ]", "tte-itta", True),
        (r"^不是[，,. ]", "bushi", True),
        (r"^错了|^錯了", "cuole", True),
        (r"不要.{0,20}要", "buyao-yao", True),
        (r"^아니[,. ]", "ani", True),
        (r"틀렸", "teullyeoss", True),
    ]

    MAX_CAPTURE_PROMPT_LENGTH = 500
    MAX_WEAK_PATTERN_LENGTH = 150
    MIN_SHORT_CORRECTION_LENGTH = 80


    def detect_patterns(text: str) -> Tuple[Optional[str], str, float, str, int]:
        stripped = text.strip()
        has_cjk = bool(re.search(r'[\u3000-\u9fff\uf900-\ufaff\uac00-\ud7af]', stripped))
        short_threshold = 2 if has_cjk else 4
        if len(stripped) <= short_threshold:
            return (None, "", 0.0, "correction", 90)

        for pattern, name, confidence, decay in EXPLICIT_PATTERNS:
            if re.search(pattern, text, re.IGNORECASE):
                return ("explicit", name, confidence, "correction", decay)

        for pattern, name, confidence, decay in GUARDRAIL_PATTERNS:
            if re.search(pattern, text, re.IGNORECASE):
                return ("guardrail", name, confidence, "correction", decay)

        for fp_pattern in FALSE_POSITIVE_PATTERNS:
            if re.search(fp_pattern, text, re.IGNORECASE):
                return (None, "", 0.0, "correction", 90)

        for nc_pattern in NON_CORRECTION_PHRASES:
            if re.search(nc_pattern, text, re.IGNORECASE):
                return (None, "", 0.0, "correction", 90)

        matched_positive = []
        for pattern, name, confidence, decay in POSITIVE_PATTERNS:
            if re.search(pattern, text, re.IGNORECASE):
                matched_positive.append(name)

        if matched_positive:
            return ("positive", " ".join(matched_positive), 0.70, "positive", 90)

        text_length = len(text)

        matched_cjk = []
        cjk_strong = False
        for pattern, name, is_strong in CJK_CORRECTION_PATTERNS:
            if re.search(pattern, stripped):
                matched_cjk.append(name)
                if is_strong:
                    cjk_strong = True

        if matched_cjk:
            confidence = 0.75 if cjk_strong else 0.60
            decay_days = 90 if cjk_strong else 60
            if text_length < MIN_SHORT_CORRECTION_LENGTH:
                confidence = min(0.90, confidence + 0.10)
            elif text_length > 300:
                confidence = max(0.50, confidence - 0.15)
            return ("auto", " ".join(matched_cjk), confidence, "correction", decay_days)

        matched_corrections = []
        pattern_count = 0
        has_strong_pattern = False
        has_i_told_you = False

        for pattern, name, is_strong in CORRECTION_PATTERNS:
            if re.search(pattern, text, re.IGNORECASE):
                if not is_strong and text_length > MAX_WEAK_PATTERN_LENGTH:
                    continue
                matched_corrections.append(name)
                pattern_count += 1
                if is_strong:
                    has_strong_pattern = True
                if name == "I-told-you":
                    has_i_told_you = True

        if matched_corrections:
            if has_i_told_you:
                confidence = 0.85
                decay_days = 120
            elif pattern_count >= 3:
                confidence = 0.85
                decay_days = 120
            elif pattern_count >= 2:
                confidence = 0.75
                decay_days = 90
            elif has_strong_pattern:
                confidence = 0.70
                decay_days = 60
            else:
                confidence = 0.55
                decay_days = 45

            if text_length < MIN_SHORT_CORRECTION_LENGTH:
                confidence = min(0.90, confidence + 0.10)
            elif text_length > 300:
                confidence = max(0.50, confidence - 0.15)
            elif text_length > 150:
                confidence = max(0.55, confidence - 0.10)

            return ("auto", " ".join(matched_corrections), confidence, "correction", decay_days)

        return (None, "", 0.0, "correction", 90)


    def create_queue_item(
        message: str,
        item_type: str,
        patterns: str,
        confidence: float,
    ) -> Dict[str, object]:
        return {
            "id": str(uuid.uuid4()),
            "created_at": iso_timestamp(),
            "message": message,
            "patterns": patterns,
            "type": item_type,
            "confidence": confidence,
            "status": "pending",
        }


    def should_include_message(text: str) -> bool:
        if not text.strip():
            return False

        skip_patterns = [
            r"^<",
            r"^\[",
            r"^\{",
            r"tool_result",
            r"tool_use_id",
            r"<command-",
            r"<task-notification>",
            r"<system-reminder>",
            r"This session is being continued",
            r"^Analysis:",
            r"^\*\*",
            r"^   -",
        ]

        for pattern in skip_patterns:
            if re.search(pattern, text):
                return False

        return True


    _SCP_LIKE_RE = re.compile(r"^(?:[^@/]+@)?([^:/\s]+):(.+)$")


    def normalize_repo_identity(origin_url: Optional[str]) -> Optional[str]:
        if not origin_url or not isinstance(origin_url, str):
            return None
        url = origin_url.strip()
        if not url:
            return None
        if url.lower().startswith("file://"):
            return None

        host: Optional[str] = None
        path = ""
        scp_match = _SCP_LIKE_RE.match(url)
        if scp_match and "://" not in url:
            host = scp_match.group(1).lower()
            path = scp_match.group(2)
        else:
            try:
                parts = urlsplit(url)
            except ValueError:
                return None
            if parts.scheme not in ("http", "https", "ssh", "git"):
                return None
            if not parts.hostname:
                return None
            host = parts.hostname.lower()
            path = parts.path or ""

        path = path.lstrip("/").rstrip("/")
        if path.lower().endswith(".git"):
            path = path[:-4]
        path = path.rstrip("/")
        segments = [seg for seg in path.split("/") if seg]
        if len(segments) != 2:
            return None
        owner, name = segments[0].lower(), segments[1].lower()
        if not host or not owner or not name:
            return None
        return f"{host}/{owner}/{name}"


    # URL-specific patterns come before credential-assignment: `token\s*[:=]`
    # matches the `?token=` inside a URL, so url-token-param would never fire
    # if credential-assignment ran first. Order is load-bearing.
    DENY_PATTERNS: List[Tuple[str, "re.Pattern[str]"]] = [
        ("openai-key", re.compile(r"\bsk-[A-Za-z0-9_-]{8,}")),
        ("github-pat", re.compile(r"\b(?:ghp_|github_pat_)[A-Za-z0-9_]{8,}")),
        ("github-oauth", re.compile(r"\bgho_[A-Za-z0-9_]{8,}")),
        ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{8,}")),
        ("slack-token", re.compile(r"\bxox[bpa]-.+[A-Za-z0-9-]{4,}")),
        ("auth-header", re.compile(r"(?i)\bauthorization\s*:")),
        ("bearer-token", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9\-._~+/=]{8,}")),
        ("private-key", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")),
        ("url-userinfo", re.compile(r"(?i)\bhttps?://[^/\s]+@")),
        ("url-token-param",
         re.compile(r"(?i)[?&](?:token|access_token|api_key|apikey|secret|key)=[^&\s]+")),
        ("credential-assignment",
         re.compile(r"(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]")),
        ("long-hex-run", re.compile(r"\b[0-9a-fA-F]{32,}\b")),
        ("long-base64-run", re.compile(r"[A-Za-z0-9+/]{32,}={0,2}")),
    ]


    def find_secret(text: str) -> Optional[str]:
        for name, pattern in DENY_PATTERNS:
            if pattern.search(text):
                return name
        return None
  '';

  # Vendored from ajmarkow/claude-reflect (reflect/declarative):
  # scripts/capture_learning.py. The lib arrives as a sibling directory at
  # build time: substituteLibDir splices this template with the real store
  # path because home-manager symlinks home.file entries individually, so
  # the script and the lib end up in DIFFERENT store paths and a relative
  # import can never work.
  captureScriptTemplate = ''
import json
import os
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, "@libDir@")

from reflect_utils import (
    create_queue_item,
    detect_patterns,
    find_secret,
    normalize_repo_identity,
    should_include_message,
    MAX_CAPTURE_PROMPT_LENGTH,
)

QUEUE_ISSUE_TITLE = "reflect queue"
QUEUE_LABEL = "reflect-queue"
HTTP_TIMEOUT = 3


class TokenExpiredError(Exception):
    pass


def _fail(reason: str) -> int:
    print(f"reflect: capture skipped: {reason}", file=sys.stderr)
    return 0


def _fail_loud(reason: str) -> int:
    print(f"reflect: CAPTURE TOKEN INVALID: {reason}", file=sys.stderr)
    print("reflect: fix REFLECT_CAPTURE_TOKEN, then retry the prompt.",
          file=sys.stderr)
    return 2


def _origin_url():
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode != 0 or proc.stdout.strip() != "true":
            return None
        proc = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode != 0:
            return None
        return proc.stdout.strip() or None
    except Exception:
        return None


def _allowlisted(allowlist: str, identity: str) -> bool:
    entries = [entry.strip().lower() for entry in allowlist.split(",")]
    entries = [entry for entry in entries if entry]
    return identity in entries


def _github(path: str, token: str, payload=None) -> object:
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = Request(
        f"https://api.github.com{path}",
        data=body,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method="POST" if payload is not None else "GET",
    )
    try:
        with urlopen(request, timeout=HTTP_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        status = getattr(exc, "code", None)
        if isinstance(exc, HTTPError) and status == 401:
            raise TokenExpiredError(
                f"GitHub API {path} returned 401 — token expired or revoked."
            ) from exc
        raise


def _find_queue_issue(repo: str, token: str):
    page = 1
    while True:
        try:
            issues = _github(
                f"/repos/{repo}/issues?state=open&labels={QUEUE_LABEL}&per_page=100&page={page}",
                token,
            )
        except TokenExpiredError:
            raise
        except Exception as exc:
            print(f"reflect: queue issue lookup failed: {exc}", file=sys.stderr)
            return None
        if not isinstance(issues, list):
            return None
        for issue in issues:
            if isinstance(issue, dict) and issue.get("title") == QUEUE_ISSUE_TITLE:
                number = issue.get("number")
                return str(number) if number is not None else None
        if len(issues) < 100:
            return None
        page += 1


def _post_item(repo: str, token: str, issue_number: str, item: dict) -> bool:
    comment = "```json\n" + json.dumps(item, indent=2) + "\n```"
    try:
        _github(
            f"/repos/{repo}/issues/{issue_number}/comments",
            token,
            {"body": comment},
        )
    except TokenExpiredError:
        raise
    except Exception as exc:
        print(f"reflect: queue POST failed: {exc}", file=sys.stderr)
        return False
    return True


def main() -> int:
    queue_repo = os.environ.get("REFLECT_QUEUE_REPO", "").strip()
    capture_token = os.environ.get("REFLECT_CAPTURE_TOKEN", "").strip()
    capture_repos = os.environ.get("REFLECT_CAPTURE_REPOS", "")
    if not queue_repo or not capture_token or not capture_repos.strip():
        return _fail("missing REFLECT_QUEUE_REPO, REFLECT_CAPTURE_TOKEN, "
                     "or REFLECT_CAPTURE_REPOS")

    identity = normalize_repo_identity(_origin_url())
    if identity is None:
        return _fail("could not determine repo identity from origin remote")
    if not _allowlisted(capture_repos, identity):
        return _fail(f"repo identity {identity} is not allowlisted")

    try:
        repo_info = _github(f"/repos/{queue_repo}", capture_token)
    except TokenExpiredError as exc:
        return _fail_loud(str(exc))
    except Exception as exc:
        print(f"reflect: queue repo check failed: {exc}", file=sys.stderr)
        return 0
    if not isinstance(repo_info, dict) or repo_info.get("private") is not True:
        return _fail(f"queue repo {queue_repo} is not private")

    try:
        input_data = sys.stdin.read()
    except Exception:
        input_data = ""
    if not input_data:
        return 0
    try:
        data = json.loads(input_data)
    except json.JSONDecodeError:
        return 0

    prompt = data.get("prompt") or data.get("message") or data.get("text")
    if not prompt or not isinstance(prompt, str):
        return 0

    if not should_include_message(prompt):
        return 0

    if len(prompt) > MAX_CAPTURE_PROMPT_LENGTH and "remember:" not in prompt.lower():
        return 0

    item_type, patterns, confidence, _sentiment, _decay_days = detect_patterns(prompt)
    if not item_type:
        return 0

    secret = find_secret(prompt)
    if secret is not None:
        return _fail(f"deny-list hit ({secret})")

    try:
        issue_number = _find_queue_issue(queue_repo, capture_token)
    except TokenExpiredError as exc:
        return _fail_loud(str(exc))
    if issue_number is None:
        return _fail("queue issue not found")
    item = create_queue_item(
        message=prompt,
        item_type=item_type,
        patterns=patterns,
        confidence=confidence,
    )
    try:
        _post_item(queue_repo, capture_token, issue_number, item)
    except TokenExpiredError as exc:
        return _fail_loud(str(exc))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"Warning: capture_learning.py error: {exc}", file=sys.stderr)
        sys.exit(0)
  '';

  libDir = pkgs.runCommand "reflect-lib" { } ''
    mkdir -p $out
    cp ${reflectUtils} $out/reflect_utils.py
  '';

  captureScript = pkgs.substitute {
    src = pkgs.writeText "capture_learning_template.py" captureScriptTemplate;
    substitutions = [
      "--replace"
      "@libDir@"
      "${libDir}"
    ];
  };



  # The hook entrypoint: sources the token from tokenFile (never the store),
  # exports the non-secret vars from the module options, then execs the
  # vendored capture script. Exit 2 (expired token) blocks the prompt by
  # design — a dead token must never pass as quiet capture. The store path
  # of captureScript is baked into this wrapper (unavoidable for a Nix-built
  # file), but the wrapper itself carries no secrets: token, queue repo, and
  # allowlist all arrive via file/env at runtime.
  hookScript = pkgs.writeShellScript "reflect-capture-hook" ''
    set -u
    if [ -r "${cfg.tokenFile}" ]; then
      # shellcheck disable=SC1090
      set -a; . "${cfg.tokenFile}"; set +a
    fi
    export REFLECT_QUEUE_REPO=${lib.escapeShellArg cfg.queueRepo}
    export REFLECT_CAPTURE_REPOS=${lib.escapeShellArg (lib.concatStringsSep "," cfg.captureRepos)}
    exec ${pkgs.python3}/bin/python3 ${captureScript}
  '';
in
{
  options.nix-components.reflect = {
    enable = lib.mkEnableOption "reflect correction-capture hook (posts to the private queue issue)";

    queueRepo = lib.mkOption {
      type = lib.types.str;
      default = "ajmarkow/reflections-queue";
      description = ''
        Queue repo in owner/name form. Must be private; the hook refuses a
        public queue at runtime.
      '';
    };

    captureRepos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Allowlist of exact host/owner/name repo identities capture runs in.
        Empty captures nothing, so a host with the module but no list is inert.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nixos/secrets/reflect-capture.env";
      description = ''
        File sourced at hook invocation for REFLECT_CAPTURE_TOKEN. Rendered
        by the host's Infisical manifest (0600); never the Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.captureRepos == map (r: lib.toLower r) cfg.captureRepos;
        message = "nix-components.reflect.captureRepos entries must be lowercase host/owner/name identities.";
      }
    ];

    home.file = {
      ".claude/hooks/reflect-capture.py" = {
        executable = true;
        source = captureScript;
      };
      ".claude/hooks/lib/reflect_utils.py" = {
        source = reflectUtils;
      };
      ".claude/hooks/reflect-capture-hook.sh" = {
        executable = true;
        source = hookScript;
      };
    };

    programs.claude-code.settings.hooks.UserPromptSubmit = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${config.home.homeDirectory}/.claude/hooks/reflect-capture-hook.sh";
          }
        ];
      }
    ];
  };
}
