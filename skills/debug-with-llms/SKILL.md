---
name: debug-with-llms
description: "How to debug effectively when working with LLM coding assistants. Use when hitting a bug, test failure, or unexpected behavior in AI-assisted code — or when the assistant itself is looping, patching symptoms, or generating slop. Distilled from Uberto Barbini's *Process Over Magic: Beyond Vibe Coding* (Pragmatic Bookshelf, 2026)."
---

# Debug With LLMs

Debugging with an LLM assistant fails predictably in the same ways: the assistant patches the symptom instead of finding the cause, the human keeps prompting through a loop of death, and hours vanish into "almost working" code. This skill exists to interrupt that pattern.

## When to invoke this skill

- A bug reproduces in AI-assisted code and the obvious fix hasn't landed on the second try.
- The assistant "fixed it" but the failure keeps returning, or new failures appear as old ones close.
- You catch yourself typing "and now also fix…" for the third turn.
- Tests suddenly change to accommodate broken code (assistant is mutating tests, not code).
- You've been in the same session for > 20 minutes on one problem.

If any of the above — stop the current loop, restart with the workflow below.

---

## Prime directive

**LLMs have a cause-and-effect blindspot.** They optimize for "change something that looks relevant to the error message." They do not model *why* a failure happens. If you show them code and a symptom, they will patch the symptom and shatter the abstraction. The fix is to move the LLM out of the mutator role and into the planner role.

Corollary: **every response is a hallucination.** Better training makes wrong answers rarer and *therefore harder to spot*. Confident-looking output during debugging is the exact moment your vigilance must rise, not drop.

---

## The core loop

```
1. Stop  →  2. Ask (no code)  →  3. Progressive Plan  →  4. Short-Leash Fix  →  5. Revert or Commit
```

Each step is small enough to complete in a few minutes. If any step drags past its budget, revert and restart the loop with a narrower scope.

---

## Step 1 — Stop

Before you write another prompt: commit the current tree (even in a broken state, if that's what "current" is), then ensure you have a **clean, green baseline** to return to. If not, revert first. You need a rollback point that pre-dates the confusion.

Rule: **never debug on a dirty tree.** You lose your only safe undo.

---

## Step 2 — Ask Mode (no code shown)

Switch the assistant to Ask Mode (or explicitly instruct: "do not write code, do not propose diffs, answer only in prose"). Describe **the symptom and the observable behavior only**. Do not paste the failing function. Do not paste the stack trace of the specific line. Give it the *problem*, not the *token pattern* that will make it pattern-match.

**Why the withhold matters**: with code, the assistant will "find" a bug in what you showed and propose a defensive `if` around the actual root cause. Without code, it must reason from the problem, which is where the real cause lives.

**Template:**

```
In production, <observable symptom> happens under <trigger conditions>.
Expected behavior: <what should happen>.
I have not shown you the implementation on purpose.

Do not write code. Enumerate a progressive debugging plan by
eliminating possible causes step by step.
Start with the most likely cause and go toward the least likely.
For each step include:
  - What to check
  - How to validate (test, log, query, config)
  - What to do based on the outcome
```

You should get back an ordered list. If you don't, re-ask more specifically.

---

## Step 3 — Progressive plan → walk it yourself

Take the returned list and check off items *manually*. Skip the ones you've already covered. Where the assistant's step is fuzzy ("check the DB"), sharpen it into a real query or log before running it. If a step's outcome contradicts an earlier assumption, stop and re-enter Step 2 with the new information.

Rule of thumb from the book: the real cause is very often not on the LLM's list at all. The list is scaffolding — walking it forces *you* to think.

---

## Step 4 — Short-leash fix

Only when the cause is identified do you allow the assistant to touch code, and only under leash:

1. Describe the ticket (root cause + intended fix + how to test it) as a single prompt.
2. Ask for a **detailed root-cause + fix + test analysis** — not code yet.
3. Read the analysis carefully. Fix ambiguities before implementation.
4. Reuse that analysis as the seed of a *fresh* implementation chat.
5. Implement one step at a time. **Kill any step that runs > ~5 minutes** and re-ask, more specifically.

**Junior-Developer Framing** (put this in the prompt, not the ruleset alone):

> "You are a junior developer doing your best. If an instruction seems unclear, wrong, or unfamiliar, ask for more information before continuing."

This one framing measurably reduces hallucinations vs. "expert who never makes mistakes." (Anthropic, arxiv 2507.21509.)

---

## Step 5 — Revert or commit

After the fix lands:

- **Commit** if: tests pass, diff is clean, no unrequested changes, no test assertions were edited to make code pass, no dead code left over.
- **Revert** if: two failed attempts in a row, > 20 minutes stuck, the assistant is regenerating instead of editing, or you can't defend the diff in review.

Reverts are cheap and diagnostic, not embarrassing. A failed attempt tells you the plan was wrong; that's information.

---

## Anti-patterns — catch yourself doing these

| Smell | Response |
|---|---|
| "Fix the bug" one-shot with code attached | Withhold the code; go back to Step 2. |
| Assistant changed a test's assertion to pass | Stop it; force the code fix instead. |
| Assistant "fixed" it but a new failure appeared | Loop of Death — revert and re-plan. |
| Third fix attempt this session | Gambling Mode + sunk cost — revert. |
| Assistant added a defensive `if` around the failing line | It patched the symptom. Cause is elsewhere. |
| Assistant regenerated the whole function | Dead code likely left behind; demand cleanup or revert. |
| Passing tests, but assertions are "not empty" / "contains newline" | Weak assertions — the tests are theater. |
| You can't explain the diff to a reviewer | You're vibe-committing. Slow down. |
| Assistant says "you're absolutely right!" | Sycophancy; verify against actual behavior, not tone. |
| You're 20+ min in and haven't reverted | You are past the two-strike line. Revert now. |

---

## Thresholds & rules of thumb

| Knob | Value |
|---|---|
| Stuck threshold before revert | ~20 min OR 2 failed attempts, whichever first |
| Assistant autonomy per turn | ≤ 5 min; longer produces code you can't re-internalize |
| Show code during diagnosis | Never (Step 2/3). Only during Step 4 implementation. |
| Commit granularity | One prompt, one commit. Feature XOR refactor XOR fix. |
| Temperature for debug prompts | 0 |
| Ruleset must include | "If ambiguous, ask before proceeding." "Never invent APIs; ask if unsure." |

---

## When the assistant itself is the bug

Sometimes the loop of death isn't in your code — it's in the collaboration. Signals:

- Same reasoning appearing in different words each turn.
- Assistant contradicting an earlier claim without acknowledging it.
- "Almost working" for the third turn.
- You've stopped reading the diffs closely.

Break the loop by:

1. **Revert** to last green commit.
2. **Restart in a fresh session** — do not "clear context" and continue. Start with a new conversation.
3. **Re-anchor** by asking the assistant to reread the spec / ruleset before any suggestion.
4. **Narrow the scope** by one level: if the last prompt was "fix login redirect," the next is "add a failing test that captures the redirect bug."

---

## Copy-paste prompts

**Diagnostic probe (Step 2):**

```
I am debugging an issue and I want you to help me plan, not fix.
Do not write code. Do not propose diffs. Answer only in prose.

Symptom: <one sentence>
Trigger conditions: <when it happens>
Expected behavior: <what should happen>
Environment: <language, framework, deploy target>

Enumerate 5–10 possible causes, ordered most-likely to least-likely.
For each: what to check, how to validate, what to do based on outcome.
```

**Implementation seed (Step 4):**

```
Root cause: <what you found in Step 3>
Fix: <one-sentence description of the change>
Test: <the test that proves the fix works>

You are a junior developer doing your best. If any instruction seems
unclear, wrong, or unfamiliar, ask for more information before continuing.

Please write:
1. The failing test that captures the bug.
2. The narrowest code change that makes it pass.

Do not touch code unrelated to this fix. Do not change other tests'
assertions. Do not regenerate the whole file; edit in place.
```

**Post-fix review (before committing):**

```
Show me the diff. For each hunk, explain in one sentence:
  - what changed
  - why it was necessary for this fix
  - what could break because of it

Flag anything that is not directly required by the stated fix.
```

---

## What this skill is not

- **Not** a bug tracker or an incident-response playbook.
- **Not** a substitute for domain understanding. LLMs are planning partners; the decision remains yours.
- **Not** a general prompt-engineering guide. See `process-over-magic` for the broader knowledge base.

---

## Provenance

Distilled from *Process Over Magic: Beyond Vibe Coding* by Uberto Barbini (Pragmatic Bookshelf, 2026), Ch 1 (loop of death, drunken intern, hallucinations, probability shaping), Ch 2 (Keep the Edge, One Prompt/One Commit, roll-back rule), Ch 3 (sycophancy, learning by supervising), Ch 4 (Progressive Debugging Plan, Junior-Developer Prompt Framing, Short-Leash Loop, Ten Recipes), Appendix 1 (cause-and-effect blindspot in LLM internals).
