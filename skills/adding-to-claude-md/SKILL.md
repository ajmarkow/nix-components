---
name: adding-to-claude-md
description: Use when adding new rules, instructions, or guidance to modules/claude-code-claude-md.nix before writing the addition to the file.
---

# Adding to CLAUDE.md

## Overview

Every line added to CLAUDE.md loads into every future conversation. Run these checks before writing — the minimum viable instruction always wins.

## Pre-Flight: Five Questions

Answer these before writing a single word:

**1. Is this already covered?**
Search existing sections. If a rule covers 80% of the intent, extend that section — don't add a parallel rule.

**2. Is this a judgment call or a mechanical constraint?**
Mechanical (enforceable by a hook, linter, or CI check) → automate it, don't document it.
Judgment call (requires context to apply correctly) → document it.

**3. What's the minimum viable statement?**
Write the rule as one sentence first. Add explanation only if the sentence alone will be misapplied.

**4. Does this belong in an existing section?**
Almost always yes. Extending an existing `##` section beats creating a new one.

**5. Is the "why" load-bearing?**
Include the reason only if omitting it causes violations. Git commit messages are the right place for history.

## Format by Content Type

| Content type | Format |
|---|---|
| Single rule | One sentence — bold the key prohibition or requirement |
| Decision with tradeoffs | Table |
| Process with order | Numbered list |
| Related rules | Bullet list under existing heading |
| Context/reason | Include only if misapplication is otherwise likely |

## Bloat Patterns to Cut

| Pattern | Fix |
|---|---|
| Restating what the rule already implies | Delete the restatement |
| "Why we added this" anecdote | Move to git commit; keep only if needed to prevent misapplication |
| Hedge words: "prefer", "consider", "generally" | Either it's a rule or it isn't |
| Multiple examples of the same pattern | Keep the best one; delete the rest |
| New `##` heading for one sentence | Absorb into the most relevant existing section |

## Minimum Viable Addition Shape

Write the instruction in this order:
1. **The rule** — one sentence, declarative
2. **The reason** — only if load-bearing (one sentence max)
3. **Supporting detail** — only if misapplication is likely without it

If you reach step 3, ask whether the rule could be stated more clearly instead.

## Red Flags — Stop and Simplify

- More than 3 sentences for a single rule
- Creating a new `##` section for one instruction
- Adding a constraint already covered in another section
- Explaining context that belongs in a PR description or commit message
