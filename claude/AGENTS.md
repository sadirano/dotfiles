# Agent guide (machine-wide)

Windows 11. PowerShell 7 and Git Bash are both present and take different
syntax. Two tools here are mine: **nix** (directory aliases) and **hoot**
(notifications).

## nix owns where things live

Navigation and project commands go through nix. Full guide:

@~/.nix/AGENTS.md

Refer to a tool by its nix name, never a filesystem path: register it
(`nix <name> <path>`), add a `[bin]` export to its `.nix/actions.toml`, end the
build action with `nix --sync-bin`, then call the bare name. An absolute path in
config means nix was skipped there - it rots on the next move, and it fails in
ways that look like the tool is broken rather than the config.

Registering an alias and `nix --sync-bin` work from an agent shell.
`nix --trust` and `--force` are mine to run.

If nix lacked something you needed, append a dated entry to `~/.nix/feedback.md`
- what happened, what nix can't do today, why it would help. Check for an
existing entry on the same idea first. Capture only; never change nix unasked.

## Tell me things through hoot

`hoot` is on PATH and pops a Windows toast I see even when tabbed away from you.
Use it - I am usually not watching the terminal.

```
hoot send "tests green, 214 passed" --tag <project> --level warn
hoot send "blocked: need the migration approved" --tag <project> --level warn
```

`info` logs quietly, `warn` toasts, `alert` is for drop-everything. Send one when
you finish something long-running or when you are blocked on me. One per event -
do not re-send on silence.

## Shell reality on Windows

Paths cross between PowerShell and Git Bash constantly, and every failure below
looks like a broken program rather than a quoting bug:

- **Config strings are run through a shell**, so use forward slashes. A JSON
  `"C:\\path\\to.exe"` arrives as `C:\path\to.exe`, the backslashes are read as
  escapes, and you get `C:pathto.exe: command not found`.
- **`echo` eats backslashes.** Build JSON test payloads with a JSON library, not
  string literals in a shell.
- **MSYS rewrites POSIX-looking arguments** into `C:/Program Files/Git/...` on
  the way to a native binary. `MSYS2_ARG_CONV_EXCL='*'` disables it; `gh` wants
  the leading slash dropped (`gh api repos/...`).

## Git

Conventional commits with a scope, matching what the repo already uses:
`feat(statusline):`, `fix(gaze):`, `chore(claude):`, `docs:`.

Never add `Co-Authored-By: Claude` or any AI attribution. Commit as me alone.

**Commit finished work without being asked, in the turn it is finished** (build
green, tests green -> commit). Pushing is the separate decision and is always
fine to ask about; withholding the *commit* is what costs. An unpushed commit is
nearly free to undo, while a dirty tree destroys the record of when the work was
done and is expensive to reconstruct later. If work is unfinished or
experimental, commit it anyway as its own commit and say so.

## Program output is ASCII

No em dashes in anything a program emits: CLI strings, help text, log lines,
generated files, commit messages. Windows consoles on legacy codepages render
them as `ΓÇö`. Use a plain hyphen. Prose docs like this file are exempt.

## Repo guidance goes in AGENTS.md

In a project repo, the committed file documenting the codebase for agents is
`AGENTS.md`, worded for any agent rather than one vendor's tool. Never create a
repo-level `CLAUDE.md`; if one exists, offer to rename it rather than doing it
unasked.
