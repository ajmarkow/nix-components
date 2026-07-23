---
name: ruleset-design
description: "Design and audit persistent rule files for AI coding assistants — AGENTS.md, CLAUDE.md, rules.md, .cursorrules, .windsurfrules, and equivalents. Use when creating a new ruleset for a project, auditing an existing one, or when the assistant is repeatedly making the same class of mistake (rewriting instead of editing, adding freebie features, mutating tests, skipping test runs). Distilled from Uberto Barbini's *Process Over Magic: Beyond Vibe Coding* (Pragmatic Bookshelf, 2026)."
---

# Ruleset Design

A ruleset is a 1,000–2,000-word persistent prompt auto-appended to every request the assistant sees. It is the durable equivalent of a system prompt, versioned with the code. Good rulesets shape behavior across sessions and developers; bad ones feel authoritative and change nothing.

## When to invoke this skill

- Creating a new `AGENTS.md`, `CLAUDE.md`, `rules.md`, `.cursorrules`, `.windsurfrules`, or equivalent.
- Auditing an existing ruleset that "isn't working" — assistant keeps making the same class of mistake.
- Adopting AI on a team and needing a shared baseline.
- Consolidating scattered advice from multiple contributors into a single file.

## Two modes

- **Design** (new project): produce a ruleset from scratch. Skip to "Section skeleton" below.
- **Audit** (existing file): read the existing file first, then run the audit checklist at the end of this skill. Report findings before rewriting.

---

## Prime directive

**Concrete verifiable rules > personas > adjectives.** In descending order of usefulness:

1. **Concrete verifiable behavior** — "Never commit before running all tests and verifying pass."
2. **Persona + spelled-out behavior** — "Explain as if to a senior back-end engineer new to Play Framework; include one working example."
3. **Persona alone** — "You are a senior Scala developer." ❌ Sounds authoritative, produces nothing.
4. **Style adjectives** — "Be careful / precise / don't make mistakes." ❌ Changes voice, not quality. (Yin et al., arxiv:2504.13656 — style adjectives measurably fail to improve output.)

If you can't write a test or a diff-inspection that would catch a rule being violated, the rule is decoration. Rewrite it or delete it.

---

## Section skeleton

Use these seven sections in this order. Missing sections are the usual cause of missing behavior.

### 1. Interaction Rules
How the assistant should behave in dialogue.

- Ask clarifying questions if input is unclear.
- If a task is not feasible, explain why and suggest alternatives.
- Don't modify code unrelated to the current task.
- Match the style of surrounding code.
- Never invent unknown APIs; ask if unsure.

### 2. Coding Standards
Concrete engineering rules — not "write clean code."

- Language, framework, library choices (e.g. "functional Kotlin with sealed classes and immutability; http4k for web").
- Test discipline (meaningful assertions; no duplicated coverage; no "not empty" as a real assertion).
- Kent Beck's Four Rules of Simple Design: (1) passes tests, (2) reveals intent, (3) no duplication, (4) fewest elements.
- Style preferences that would show up in a diff (functional vs. imperative; short functions; explicit parameters).

### 3. Architecture
Structural constraints the assistant should default to.

- Modularize by concern, not by technical layer.
- One responsibility per module; low inter-module coupling.
- Prefer Ports & Adapters over mocks for I/O boundaries.
- Explicit "no accidental complexity, no speculative abstraction" clauses.

### 4. Workflow
The session cadence the assistant must follow.

- Read `spec.md` (or equivalent) before coding.
- Update `spec.md` after task, logging what changed.
- Write and pass tests before finalizing.
- Cap autonomous runs at ~5 minutes; ask before proceeding on ambiguous branches.

### 5. Commit Strategy
The single most impactful section for AI-generated diffs.

- One prompt = one commit.
- Feature XOR refactor XOR fix — never bundled.
- Never auto-commit — human reviews the diff first.
- 50/70 message format (or your team's convention).
- Commit-then-fix rule: if you spot a second issue mid-task, commit current working code first, then fix in a new commit.

### 6. Safe Practices
Guardrails against the assistant's known failure modes.

- Do not change test assertions during refactoring.
- Do not skip failing tests.
- Do not invent unknown APIs; ask if unsure.
- Do not regenerate a whole file when editing in place would work; call out replaced code for deletion.
- Do not add unrequested features — surface the idea, don't ship it.

### 7. Goal
One or two lines at the end restating the target.

- "Produce consistent, safe, testable, and maintainable code. Stick to the rules — no shortcuts."

---

## The concrete-verifiable test

Before adding any rule, ask:

1. **Could I write a test or diff-check that catches a violation?**
2. **Does it name a specific behavior, technology, or action?**
3. **Would I be able to explain to a junior dev why they got a comment in code review?**

If you can't answer yes to all three, the rule is either an adjective or a persona in disguise. Rewrite or delete.

**Contrast table:**

| ❌ Adjective / Persona | ✅ Concrete Verifiable |
|---|---|
| Be careful with tests | Never modify test assertions during refactor — fix the implementation instead |
| Be precise | If ambiguous, ask a clarifying question before proceeding |
| You are a senior engineer | Prefer functional style: immutability, explicit parameters, no shared mutable state |
| Write professional code | Match the style of the file you are touching; if new file, use the language's community style guide |
| Don't hallucinate | If unsure whether an API exists, ask — do not invent method signatures |
| Follow best practices | Apply Kent Beck's Four Rules of Simple Design in order |
| Be helpful | Explain what you did and why in one paragraph after each change |

---

## Junior-developer framing (embed in the ruleset)

Include this literal instruction in the Interaction Rules section — it measurably reduces hallucinations (Anthropic arxiv:2507.21509):

> "Behave as a junior developer doing their best. If an instruction seems unclear, wrong, or unfamiliar, ask for more information before continuing. Do not fabricate APIs or file paths — ask if unsure."

Do **not** replace this with "You are a senior expert." Confidence framings raise hallucination rates.

---

## Team pattern — shared rules + personal overrides

For team repos, split the ruleset into two files:

- **`rules.md`** (or `AGENTS.md`) — committed to the repo. The team's baseline.
- **`personal_rules.md`** — in `.gitignore`. Individual style, editor quirks, personal shortcuts.

Reference the personal file from the shared file so both load together:

```markdown
## Personal Overrides
If a file `personal_rules.md` exists in this repo, load and apply its rules
after these shared rules. Personal rules may extend but should not
contradict the shared baseline; if they do, flag the contradiction.
```

Then a one-liner in `.gitignore`:

```
personal_rules.md
```

This gives you uniformity where it matters and freedom where it doesn't. It also stops the git-history churn from every dev tweaking the shared file.

---

## Length rule

**1,000–2,000 words.** Anything shorter under-specifies; anything longer eats prompt-tokens on every turn without proportional benefit. If you feel the pressure to add more, externalize the extra material into a separate skill file (e.g. `skills/writing-tests.md`) that the assistant loads only when relevant. Rulesets are for what applies *always*; skills are for what applies *sometimes*.

---

## What NOT to put in the ruleset

- **Tutorials or explanations.** Rulesets are commands, not textbooks.
- **How-to guides for specific tasks.** Externalize into skills files.
- **Historical context / rationale.** Keep in the commit message or an ADR.
- **Aspirational values.** ("We value quality" — verify with rules, not with slogans.)
- **Long code examples.** One short template is fine; a 200-line snippet is a skill file waiting to happen.

---

## Starter template (copy-paste)

```markdown
# AGENTS.md — Ruleset for AI Coding Assistants

## 1. Interaction Rules
* Behave as a junior developer doing their best. If an instruction seems
  unclear, wrong, or unfamiliar, ask for more information before continuing.
* Do not fabricate APIs, file paths, or library methods — ask if unsure.
* Do not modify code unrelated to the current task.
* Match the style of the file you are touching.
* Explain what you did and why in one paragraph after each change.

## 2. Coding Standards
* Languages / frameworks in this repo: <fill in>
* Write meaningful tests with real assertions. Avoid "not empty" and
  duplicated coverage.
* Apply Kent Beck's Four Rules of Simple Design in order:
  1. Passes tests
  2. Reveals intent
  3. No duplication
  4. Fewest elements
* Prefer functional style: immutability, explicit parameters, minimal state.

## 3. Architecture
* Modularize by concern, not by technical layer.
* One responsibility per module. Low inter-module coupling.
* Prefer Ports & Adapters over mocks at I/O boundaries.
* No speculative abstraction. Add layers only when a concrete use demands one.

## 4. Workflow
* Read `spec.md` before coding. Update it after the task if behavior changed.
* Write and pass tests before finalizing any change.
* Cap autonomous runs at ~5 minutes. If a step runs long, pause and ask.

## 5. Commit Strategy
* One prompt = one commit.
* Feature XOR refactor XOR fix — never bundled in a single commit.
* Never auto-commit; wait for human review of the diff.
* Commit message: 50/70 format (subject ≤ 50 chars, body wrapped at 70).
* Commit-then-fix: if you notice a second issue mid-task, commit the
  current working code first, then fix in a new commit.

## 6. Safe Practices
* Do not change test assertions to make code pass — fix the code.
* Do not skip failing tests.
* Do not regenerate a whole file when editing in place would work.
* Do not add unrequested features — surface the idea instead.
* Never commit before all tests pass.

## 7. Personal Overrides
If `personal_rules.md` exists in this repo, load and apply it after these
shared rules. Personal rules may extend but not contradict this baseline;
flag any contradiction.

## Goal
Produce consistent, safe, testable, maintainable code.
Stick to the rules — no shortcuts.
```

Fill in `<fill in>` and any project-specific sections. Delete sections that don't apply. Keep the total under 2,000 words.

---

## Audit checklist (for existing rulesets)

When auditing an existing file, walk this list and produce a per-item finding before rewriting anything:

1. **Length** — Between 1,000 and 2,000 words? Under: under-specified. Over: bleeds prompt budget.
2. **Persona-only sentences** — Any "You are a senior X" without behavioral follow-through? Flag for deletion.
3. **Style adjectives** — "Be careful / precise / thorough / professional"? Flag for rewrite as concrete behavior.
4. **Untestable rules** — For each rule, could you catch a violation in a diff or test? If not, rewrite or delete.
5. **Missing sections** — Is one of the seven sections absent? Explain what class of mistakes the assistant will keep making.
6. **Junior-developer framing** — Is the framing present? If it says "expert" instead, that raises hallucination rates. Fix.
7. **Commit strategy** — Is "One prompt, one commit" and "never auto-commit" spelled out? If not, add.
8. **Safe Practices** — Are the known LLM failure modes (mutate tests, regenerate files, add freebies) explicitly forbidden? If not, add.
9. **Externalizable content** — Any tutorial-length material or task-specific how-to that belongs in a separate skill file? Extract.
10. **Personal-override pattern** — For team repos, is `personal_rules.md` referenced and `.gitignore`d? If not, add.

Report format:

```
## Audit — <path/to/ruleset>

Length: <N> words (target 1,000–2,000)

Findings:
- ❌ Line X: "Be precise" — style adjective, no verifiable behavior. Suggest: "If ambiguous, ask before proceeding."
- ❌ Missing: Commit Strategy section. Class of miss: assistant may auto-commit and mix concerns.
- ✅ Interaction rules present and concrete.
- ⚠ Junior-developer framing missing; current framing raises hallucination rates.

Recommendation: <rewrite / minor edits / add sections>
```

Only rewrite after the user has seen the findings.

---

## Anti-patterns — catch yourself doing these while writing

| Smell | Fix |
|---|---|
| "You are a 10x developer" | Replace with concrete behavior. |
| Long list of "always" and "never" without examples | Add a one-line contrast example per rule. |
| Ruleset over 2,000 words | Externalize task-specific material into a skill file. |
| Aspirational values statement at the top | Delete — verify with rules, not slogans. |
| Same rule stated three different ways | Consolidate. |
| "Follow best practices" | Name the practices. |
| No commit strategy | Add it — highest-impact section for AI diffs. |
| No safe-practices guardrails | Add explicit forbids for known LLM failure modes. |
| Missing test-discipline rule | Add "meaningful assertions" clause; the assistant will otherwise ship coverage theater. |

---

## Provenance

Distilled from *Process Over Magic: Beyond Vibe Coding* by Uberto Barbini (Pragmatic Bookshelf, 2026), Ch 2 (Ruleset, sample starter, Four Rules of Simple Design, One Prompt/One Commit, safe-practices catalog), Ch 4 (Junior-Developer Prompt Framing), Ch 5 (Shared Rules + Personal Overrides). Research citations: Yin et al. arxiv:2504.13656 (style adjectives don't improve output); Anthropic arxiv:2507.21509 (junior-developer framing reduces hallucinations).
