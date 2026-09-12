''
  ## Decision Points — Use AskUserQuestion

  Default to `AskUserQuestion` (not prose) for major/medium decisions: tradeoffs between approaches, risky/hard-to-reverse actions, or requirement ambiguity that changes the outcome. Skip it for calls you can resolve yourself (style, reading the code) or quick clarifications that don't need structured options. Batch related questions into one call.

  Rule of thumb: if you'd write "Would you like X or Y?" in prose, ask it as `AskUserQuestion` instead.
''
