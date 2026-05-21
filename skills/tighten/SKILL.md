---
name: tighten
description: "Refactor AGENTS.md to follow progressive disclosure principles: identify contradictions, extract essentials, group instructions, and flag for deletion."
---

# Tighten AGENTS.md

Refactor an AGENTS.md file to follow progressive disclosure principles, creating a minimal root file with linked documentation groups.

## When to use (trigger phrases)

Use this skill immediately when the user asks any of:

- "tighten agents.md"
- "refactor agents.md"
- "simplify agents.md with progressive disclosure"
- "reorganize agents.md"
- "clean up agents.md"

## Quick start

The skill will guide you through a 5-step refactoring process:

1. **Find contradictions** — Identify conflicting instructions and ask which version to keep
2. **Identify essentials** — Extract only what belongs in the root AGENTS.md
3. **Group the rest** — Organize remaining instructions into logical categories
4. **Create file structure** — Output minimal root file with links to category files
5. **Flag for deletion** — Identify redundant, vague, or obvious instructions

## What goes in root AGENTS.md

Keep only:
- One-sentence project description
- Package manager (if not npm)
- Non-standard build/typecheck commands
- Anything truly relevant to every single task

## Example output structure

```
AGENTS.md (minimal, with links)
├── docs/typescript-conventions.md
├── docs/testing-patterns.md
├── docs/api-design.md
├── docs/git-workflow.md
└── docs/performance.md
```

## Instructions for the agent

The refactoring agent will:

1. **Scan for contradictions**: Read the current AGENTS.md and list any conflicting instructions. For each, ask the user which version to keep.

2. **Extract essentials**: Identify what belongs in the root file using the criteria above. Everything else goes into category files.

3. **Group logically**: Organize remaining instructions by topic (e.g., TypeScript conventions, testing patterns, API design, Git workflow, performance, CI/CD, code style).

4. **Create structure**: Propose:
   - A minimal root AGENTS.md with markdown links to category files
   - Each category file with its relevant instructions and context
   - A suggested docs/ folder structure

5. **Flag for deletion**: Identify instructions that are:
   - Redundant (the agent already knows this)
   - Too vague to be actionable
   - Overly obvious (like "write clean code")
   - Outdated or superseded

6. **Propose changes**: Present the refactored structure to the user and ask which changes to apply.

## Key principles

- **Progressive disclosure**: Root file is minimal; details live in category files
- **User-driven**: Ask the user to decide contradictions, not the agent
- **Preserve intent**: Keep all useful guidance; just reorganize it
- **Link liberally**: Use markdown links in root file to guide readers to relevant docs
