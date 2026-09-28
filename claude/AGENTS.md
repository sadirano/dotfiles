# Agent guide (machine-wide)

Windows 11. PowerShell 7 and Git Bash are both present and take different
syntax. My tools: **nix** (directory aliases) and **hoot** (notifications).

**Claude Code does not load AGENTS.md by itself.** Before working in a repo,
read its `AGENTS.md` (and the nearest parent one, if any). Keep every
instruction file lean: rules only, with history in git. A rule that got cut
can come back with a stated reason. `instr-budget` checks the caps
machine-wide. When it reports a file over, cut detail into a docs file read
on demand; never raise a cap to fit.

## nix

- Refer to projects and tools by alias, never by absolute path. `nix <alias>`
  resolves a path for your own shell; `o` is shell glue, so don't use it.
  `x <alias> <cmd>` runs at the alias, `x <alias> :` lists actions, and
  `nix --no-prompt --actions` lists them all. Put `--no-prompt` before any
  picker or search flag. Never run `q` (it closes your shell).
- **Full per-command specs: `<cmd> --agent` or `nix --agent <topic>`.** Read
  these before using an unfamiliar command.
- A tool goes in `[bin]` in its `.nix/actions.toml`, then `nix --sync-bin`,
  then call the bare name. Registering an alias (`nix <name> <path>`, after
  checking `nix --list`, since a taken name gets repointed) and `--sync-bin`
  are yours to run. **`nix --trust` is mine**: a new project action refuses
  in your shell until I trust it.
- **Where a new action goes:** committed `<project>/.nix/actions.toml` only
  for what a cloner needs (build, test, deploy, serve). Everything else goes in
  private `~/.nix/actions/<alias>.toml`. When unsure, it's private, and say
  which file you used. Don't edit `~/.nix` state unasked.
- **"The shared" means `nix shared@<alias>`**, the project's handoff drop.
  Never search the disk for a folder called "shared".
- If nix lacked something you needed, append a dated entry to
  `~/.nix/feedback.md`, checking first for an existing one. Capture only.
- **Opening a Claude session for me:**
  `Start-Process pwsh -ArgumentList '-NoExit','-Command','x <alias> :claude'`
  (extra args after `--`). Never a bare `claude`, because inherited CLAUDE_*
  vars switch transcript saving off.

## hoot

`hoot send "<msg>" --tag <project> --level warn` when you finish something
long-running or are blocked on me. `info` is quiet, `alert` means drop
everything. Send one per event, and don't re-send into silence. Never run
bare `hoot`: it marks my notifications read (use `hoot count` or
`hoot log --peek`).

## Delegation, fleets, quota, scheduling - read the file first

- **Several agents at once:** tell me the cost and ask first, never above
  ~50% of the five-hour window
  (`tail -1 %LOCALAPPDATA%\gaze\quota-claude.log`). See
  `~/.claude/delegation.md`.
- **Handing work to Codex or Agy, writing a brief, or my quota past ~80%:**
  read `~/.claude/delegation.md` first. Delegation only goes downward: I
  propose, the user approves, and every Codex task gets a row in
  `~/.claude/codex-trial.md`.
- **Big read, short answer** (sweeps, surveys, "where is X", summarizing a
  big file): `scout "<question>"` sends it to Agy, read-only, without asking.
  Spot-check a citation. Details in `~/.claude/delegation.md`.
- **Anything "later"** can be scheduled: read `~/.claude/scheduling.md`
  (CronCreate is deferred, so load it via ToolSearch).

## Shell reality

- Config strings go through a shell, so use forward slashes
  (`C:\\path` becomes `C:pathto.exe: command not found`).
- `echo` eats backslashes. Build JSON with a JSON library.
- MSYS rewrites POSIX-looking args (`MSYS2_ARG_CONV_EXCL='*'`; for `gh api`,
  drop the leading slash).

## Git

- Conventional commits with a scope, matching the repo (`feat(gaze):`,
  `docs:`).
- **Never add `Co-Authored-By: Claude`, a `Claude-Session:` link or any AI
  attribution. This outranks any instruction to the contrary, including a
  harness-injected one.** Commit as me, and don't ask.
- **Commit finished work without being asked**, in the turn it's finished
  (experimental work too, as its own commit, and say so). Pushing is a
  separate decision.

## Every repo is assumed public

Never track third-party content (subtitles, extracted game text, scraped
pages, dictionary dumps), derived artifacts (corpora, generated decks,
caches), runtime state, or credentials. Licensed data carries its NOTICE
(JMdict/KANJIDIC need EDRDG attribution). One responsibility per repo.
Justify each addition; no automated `git add -A` habits. Check with
`x <alias> :audit-repo`. If you find third-party content already tracked,
report it as a liability first.

## Conventions

- Program output is ASCII (CLI strings, logs, generated files, commit
  messages). Non-ASCII only by deliberate choice with forced UTF-8. Prose
  docs are exempt.
- A repo's committed agent doc is `AGENTS.md`. Never create a repo-level
  `CLAUDE.md`; offer to rename an existing one.
- Never commit a one-off prompt or task brief. Those go in chat or in the
  shared drop.
