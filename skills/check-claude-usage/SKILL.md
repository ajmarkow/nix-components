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
2. Tell the user to log in in that tab. Use `camofox_snapshot` to check when the account page has loaded.
3. Run `camofox_save_profile` with `tabId` from step 1 and `profileId` `claude-usage`.

Redo this only when a check below shows a login screen instead of usage data.

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
