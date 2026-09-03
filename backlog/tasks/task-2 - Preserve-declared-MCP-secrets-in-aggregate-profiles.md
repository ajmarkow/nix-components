---
id: TASK-2
title: Preserve declared MCP secrets in aggregate profiles
status: In Progress
assignee: []
created_date: "2026-09-03 20:32"
updated_date: "2026-09-03 20:43"
labels: []
dependencies: []
modified_files:
  - pkgs/mcpm.nix
  - modules/lib/mcp.nix
  - docs/adding-mcp.md
  - per-system.nix
  - tests/test_mcpm_env.py
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Fix MCPM 2.15.0 aggregate profiles so each child receives only its declared runtime secret variables. Keep secret values out of Nix-generated files and the Nix store.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [x] #1 Aggregate profile children receive declared runtime environment variables
- [x] #2 Unrelated environment variables are not passed to aggregate profile children
- [x] #3 GitHub, n8n, Context7, and Todoist declare the correct runtime secret variable names
- [x] #4 Comments and MCP documentation describe the actual environment behavior
- [x] #5 nix flake check --no-build succeeds
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->

1. Declare MCPM runtime environment references per server. 2. Patch MCPM 2.15.0 to resolve declared references through get_filtered_env_vars. 3. Add a Nix check for declared propagation and unrelated-variable isolation. 4. Update documentation and verify the flake.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->

Patched the installed wheel during postInstall because uv2nix does not expose wheel contents during patchPhase. Focused mcpm-environment check passed. Statix and Deadnix passed on changed Nix files. nix flake check --no-build --accept-flake-config passed.

<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->

MCPM aggregate children now resolve only environment variables declared by each server. GitHub, n8n, Context7, and Todoist use runtime references, and the flake includes a regression check.

<!-- SECTION:FINAL_SUMMARY:END -->
