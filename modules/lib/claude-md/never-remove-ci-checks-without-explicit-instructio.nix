''
  ## ⚠️ Never Remove CI Checks Without Explicit Instruction

  **Agents must NEVER remove, disable, or bypass CI checks (e.g. GitHub Actions workflow steps) without explicit instruction from the user to do so.**

  This rule exists because a CI step was removed during debugging without user approval, which bypassed a safety check. Removing a CI step is an irreversible action with blast radius beyond the current task — it silently disables protection for all future commits and contributors.

  If a CI step is failing and you think removing it would fix the immediate problem, **stop**. Instead:
  1. Diagnose why the step is failing.
  2. Fix the underlying issue so the step passes.
  3. If the step genuinely needs to be removed, ask the user explicitly before touching it.
''
