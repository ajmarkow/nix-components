---
name: agent-dropbox
description: Use when the user asks to drop, upload, send, or share a file to the shared dropbox — a background job syncs it to cloud storage automatically.
argument-hint: <file-or-directory>
allowed-tools: [Read, Bash, Glob]
user-invocable: true
---

Copy or write a file into the shared dropbox outbox folder so it syncs to shared cloud storage automatically.

## Steps

1. Resolve the target file (from `$ARGUMENTS`, or from context if the user just produced the file in this conversation).
2. Copy or write it into `~/dropbox-outbox/`, preserving the original filename:
   ```bash
   rtk cp <source-file> ~/dropbox-outbox/
   ```
3. Tell the user the file is queued and will sync to the shared dropbox within about 5 minutes. Do not claim it has synced immediately.

## Notes

- This skill only ever touches `~/dropbox-outbox/`. It never runs `rclone`, never reads credentials, and never references the destination bucket — a background job (outside this skill's concern) handles the actual sync.
- If `~/dropbox-outbox/` does not exist, something is misconfigured on this host — report that to the user rather than creating the folder yourself.
