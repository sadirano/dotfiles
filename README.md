# dotfiles

Personal machine config, kept under version control. Currently: my
[Claude Code](https://claude.com/claude-code) setup - a status line for
Windows and Unix, plus a small script that mirrors the live config back into
this repo and commits it.

Everything here is portable. No absolute paths are baked into any tracked
file; the scripts resolve their own location and `$HOME` at runtime.

## Layout

```
claude/
  CLAUDE.md          global instructions, symlinked to ~/.claude/CLAUDE.md
  settings.json      publishable subset of ~/.claude/settings.json
  statusline.ps1     status line, Windows / PowerShell 7
  statusline.sh      status line, Linux / macOS / bash
  sync-config.ps1    pulls ~/.claude config into this repo and commits it
.nix/actions.toml    nix action definitions (see "nix" below)
```

## Status line

> **Not what this machine currently runs.** `~/.claude/settings.json` points at
> [gaze](../repo/owl/thril/gaze), a native binary that renders the same line in
> ~7ms instead of ~690ms - almost all of the difference being the cost of
> starting PowerShell or bash at all. These two scripts are kept as the
> portable reference: they need nothing but a shell, and gaze's output is
> verified against `statusline.ps1` payload by payload.

Renders a single line:

```
(alias) <rel-path> > <model>  <branch> <clean|*dirty>  <5h%> / <7d%>
  #<context%>  @<cached>  $<cost>  +<added>/-<removed>  <duration>  <clock>
```

- **path** collapses the nix alias root to its name, so only the part below it
  is spelled out (`(owl) src/core`). Outside a nix session, or in a directory
  under no alias, it falls back to the full absolute path
- **quota** turns red past 80% in either window, with time until reset
- **git** branch and dirty flag come from one `git status --porcelain --branch`
  call with a 400ms timeout, killed if it hangs, and stay hidden outside a repo
- **@cached** is `cache_read + cache_creation` input tokens, k/M suffixed
- **$cost**, **+added/-removed** and **duration** are this session's running
  totals, each hidden until it is nonzero

Optional segments appear only when their source exists: a `(alias)` prefix when
`$NIX_ALIAS` is set, and an owl badge with an unread count when `hoot`, my
notification CLI, is installed.

### Install

Clone anywhere, then point `statusLine` at the script. Both forms below expand
`$HOME` under bash and PowerShell alike, so they work whichever shell the hook
runner lands in.

Windows, in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NonInteractive -File \"$HOME/.dotfiles/claude/statusline.ps1\""
  }
}
```

Linux / macOS:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"$HOME/.dotfiles/claude/statusline.sh\""
  }
}
```

Requires PowerShell 7 (`.ps1`) or `jq` (`.sh`). Git is optional; the git
segment is simply omitted when it is missing or the directory is not a repo.

## Config sync

`claude/sync-config.ps1` keeps this repo current with `~/.claude` and commits
whatever moved. It runs from a `SessionStart` hook, asynchronously so it never
delays startup, and by hand via `r dotenv :sync`.

Two sync modes, one per file class:

- **linked** - the repo holds the real file and `~/.claude` gets a symlink to
  it. Used for files I own (`CLAUDE.md`), so edits land in the repo the instant
  they are saved and history is never stale. If an editor replaces the symlink
  with a plain file on save, the next run copies the newer content in and
  re-links.
- **mirrored** - the repo holds a filtered copy refreshed each run. Used for
  files Claude Code rewrites itself (`settings.json`), where a symlink would be
  clobbered by the app's own atomic writes.

It commits only paths under `claude/`, so anything else staged in the repo is
left alone, and it never pushes. Committing is cheap to undo; pushing is a
separate decision.

### What the mirror publishes

This repo is public, and `settings.json` supports keys that must never be:
`env` is the documented home for `ANTHROPIC_API_KEY`, `apiKeyHelper` /
`awsAuthRefresh` / `awsCredentialExport` are credential plumbing, and
`permissions` enumerates local paths. So the mirror copies an **allowlist** of
top-level keys (`$publishable` in `sync-config.ps1`) and drops the rest,
warning about what it dropped. It fails closed: a key nobody has vetted is
omitted, including keys added by future Claude Code versions.

The trade is deliberate - the mirrored file is a **publishable subset, not a
backup**. Restoring from it will not bring back anything unlisted.

Creating the symlink needs Developer Mode or an elevated shell on Windows. If
that fails the script falls back to copying and warns, so the live file is
never left missing.

## nix

Navigation and project commands on this machine go through
[nix](https://github.com/sadirano/nix), a directory alias manager. The
`.nix/actions.toml` here defines `r dotenv :sync`. Nothing else in the repo
depends on nix being installed.

## Caveats for anyone copying this

`settings.json` is my live config, not a template. The `Notification` hook
shells out to `hoot`, which you almost certainly do not have, so drop that
block or swap in your own notifier. The status line degrades gracefully
without `hoot` and needs no edit.
