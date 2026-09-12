''
  ## Build Verification — Never Trust a Pipe's Exit Code

  **Never interpret the exit code of a piped or backgrounded command as build success** — the exit code is the last command in the pipe, not the build. Grep the log for explicit success/failure markers instead.
''
