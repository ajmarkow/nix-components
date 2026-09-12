''
  ## Context & Session Discipline

  ### Two-Strike Rule

  After **two failed attempts on the same issue**, stop. **Do not try a third fix.** Invoke the `debug-with-llms` skill and follow it. It replaces more attempts.

  ### Cap Shell Output

  Cap shell command output by default. Use focused filters (`--no-pager`, `head`, `grep`, line-range flags) and paste only the relevant failing excerpt back into context — never the full raw output.

  ### File Reading Discipline

  Before rereading a file, summarize what you already know about it. Prefer targeted symbol searches (`rg`, LSP go-to-definition) or narrow line ranges (`offset`/`limit`) over whole-file reads.
''
