---
name: check-claude-usage
description: Use before starting a long or expensive task, when told to self-meter or pace work, or when the user asks how much Claude usage, quota, or rate limit is left.
---

# Check Claude Usage

## Overview

Reads the Claude.ai usage page (`https://claude.ai/new#settings/usage`) through a persistent, logged-in Camoufox session, so any agent can see the current usage and throttle itself.

## One-Time Setup

Claude.ai login is not a static form (email, OTP, SSO). A human must complete it once. Do not try to automate it.

1. `camofox_create_tab` with `url` `https://claude.ai/login`, `userId` `claude-usage`, `sessionKey` `claude-usage`.
2. Hand off to VNC (see below) so the user can reach that tab — it runs on a headless remote browser, not the user's own machine.
3. Tell the user to log in at the VNC URL. Use `camofox_snapshot` to check when the account page has loaded.
4. Run `camofox_save_profile` with `tabId` from step 1 and `profileId` `claude-usage`.
5. `camofox_toggle_display` with `userId` `claude-usage`, `headless` `true`, to switch back to headless now that login is done.

Redo this only when a check below shows a login screen instead of usage data.

## Visual / Interactive Access (VNC)

The camofox session runs headless on the server, not in the user's own browser — it has no way to open the tab directly. Hand off to VNC whenever:

- Login setup (above) needs a human to actually see and use the page.
- A check below hits a CAPTCHA, 2FA prompt, or anything else that needs a human click-through.
- The user explicitly asks to see, watch, or interact with the browser session.

Steps:

1. `camofox_toggle_display` with `userId` `claude-usage`, `headless` `"virtual"`. The response's `vncUrl` looks like `http://localhost:6080/vnc.html?autoconnect=true&resize=scale&token=...` — `localhost:6080` is internal to the host, not reachable from the user's machine.
2. Rewrite that URL to `https://camofox-vnc.tail772f0.ts.net/vnc.html?autoconnect=true&resize=scale&token=...` (same path and query string, new host, no port — the Tailscale Service serves HTTPS on 443) and give the user that URL.
3. When the user is done, `camofox_toggle_display` with `headless` `true` again — don't leave the session sitting in virtual/headed mode longer than needed.

Never try to route around a visual blocker (guessing at a CAPTCHA or OTP) — hand off to VNC instead.

## Checking Usage

1. `camofox_server_status` — confirm the server is up.
2. `camofox_create_tab` with `userId` `claude-usage` and `sessionKey` `claude-usage`. This reuses the saved browser context, so the login carries over between checks.
3. `camofox_load_profile` with `profileId` `claude-usage` on the new `tabId`.
4. `camofox_navigate_and_snapshot` to `https://claude.ai/new#settings/usage`, with `waitForText` set to something that only appears once the usage widgets render (e.g. `"Usage"` or `"resets"`).
5. Read the snapshot for plan name, percent used, and reset time. If the numbers are missing, `camofox_wait_for` a beat and take another `camofox_snapshot` — the usage bars load after the rest of the page.
6. If the snapshot shows a login screen, the saved profile expired. Stop, tell the user, and repeat One-Time Setup.
7. `camofox_close_tab` when done, so tabs don't pile up across checks.

## Self-Metering

State the numbers plainly — plan, percent used, reset time — then act on them:

- Under 70% used: proceed normally.
- 70-90% used: tell the user before starting large or multi-step work.
- Over 90% used, or limit already reached: pause new large tasks and wait for the user's call.

## Common Mistakes

- Using a fresh `userId`/`sessionKey` each check — this drops the reused context and can force a re-login. Always reuse `claude-usage`.
- Treating a login screen as a load hiccup and retrying blindly — it means the session expired, not that the page is slow.
- Guessing at login credentials or OTP codes instead of asking the user to log in by hand.
- Handing the user the raw `vncUrl` from `camofox_toggle_display` — its `localhost:6080` host is only reachable on the server itself. Always rewrite it to the `camofox-vnc.tail772f0.ts.net` URL first.
- Leaving the display in virtual/headed mode after VNC use — toggle back to `headless: true` when done.
