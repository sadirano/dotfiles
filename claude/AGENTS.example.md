# Agent guide (machine-wide) - example

A starting point for `~/.claude/AGENTS.md`, the guidance every Claude Code
session on your machine reads. Copy it, then make it yours: delete what does
not fit, and add the rules you find yourself repeating. Load it from
`~/.claude/CLAUDE.md` with a single line: `@~/.claude/AGENTS.md`.

Keep it short. Everything here is re-read by every session, so a rule earns
its place by preventing a mistake you have actually seen.

## Shell reality (Windows)

- PowerShell 7 and Git Bash take different syntax. Say which one a command is
  for, and do not mix `$env:X` with `$X`.
- Config strings often pass through a shell: use forward slashes in paths
  (`C:/tools/x.exe`), since backslashes get eaten.
- Build JSON with a JSON library, never with `echo` and string concatenation.

## Git

- Conventional commits with a scope matching the repo (`feat(cli):`, `docs:`).
- Ask before pushing, force-pushing, or rewriting history.
- Never commit secrets, generated artifacts, caches, or other people's content
  (scraped pages, datasets, subtitles). Assume every repo may become public.

## Working style

- Read a repo's own `AGENTS.md` (or `README.md`) before changing it.
- Prefer the smallest change that solves the problem; say what you left out.
- When something fails, report it with the output instead of guessing.
- Before deleting or overwriting anything, look at it first.
