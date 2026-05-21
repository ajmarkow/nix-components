---
name: paseo-send
description: Find a running paseo agent by repo/directory name and send it a message. Resolves the agent ID automatically so you never have to run paseo ls manually.
argument-hint: <repo-name> "<message>"
allowed-tools: [Bash]
user-invocable: true
---

Find a running paseo agent by repo or directory name, then send it a message.

## Parse Arguments

`$ARGUMENTS` contains everything typed after `/paseo-send`.

- First token (before the first quoted string or space boundary) = **name filter**
- Remaining text (may be quoted) = **message to send**

Examples:
- `/paseo-send nix-components "please review the flake changes"`
- `/paseo-send pi-coding-agent what is the current status?`

## Steps

### 1. List active agents

```bash
rtk paseo ls -g
```

This shows only running/idle agents (no closed). Do not use `-a` — it includes closed agents and adds noise.

### 2. Filter by name

Match lines where the repo/directory name contains the name filter (case-insensitive). Extract the agent ID (first column) from matching lines.

### 3. Branch on match count

**Exactly one match** — immediately present the resolved command to the user for approval, then run it:
```bash
rtk paseo send <id> "<message>"
```

**Multiple matches** — list the matching agents with their IDs and directories, ask the user to pick one, then run:
```bash
rtk paseo send <chosen-id> "<message>"
```

**Zero matches** — no active agent matched. Start a new detached agent automatically:
```bash
rtk paseo run "<message>" --detach --name <name-filter>
```

## Notes

- Always use `rtk paseo` (never bare `paseo`) per project bash conventions.
- The resolved `paseo send` command must be shown to the user before execution so they can approve or cancel.
- If the message was not provided in arguments, ask for it before proceeding.
