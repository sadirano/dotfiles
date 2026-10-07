# dotfiles

A small, portable setup for a Windows machine that runs
[Claude Code](https://claude.com/claude-code): a Scoop-based setup script, a
Claude Code status line (PowerShell and bash), a guard hook against
process kills that take every session down with them, and an example agent
guide to start your own from.

Nothing here syncs itself, commits itself, or phones anywhere. You copy what
you want, once.

## Layout

```
setup.ps1                     new-machine setup through Scoop (see below)
claude/
  statusline.ps1              Claude Code status line, Windows / PowerShell 7
  statusline.sh               the same line for Linux / macOS (bash 4.2+, jq)
  hooks/guard_broad_kill.py   PreToolUse hook: blocks kill-by-image-name commands
  settings.example.json       the settings that wire the two above in
  AGENTS.example.md           a starter machine-wide agent guide
.nix/actions.toml             optional Windows conveniences as nix actions
samples/
  _default.toml               machine-wide nix actions to copy into ~/.nix/actions/
  config.toml                 nix preferences to copy into ~/.nix/
```

## Setup (Windows)

Install Scoop and git, clone, and run the script:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex          # Scoop's official installer
scoop install git
git clone https://github.com/sadirano/dotfiles $HOME/.dotfiles
powershell -File $HOME/.dotfiles/setup.ps1
```

It installs [nix](https://github.com/sadirano/nix) (a directory alias and
action runner), clink, fzf, ripgrep, fd, bat, neovim, pwsh, gh, delta, jq,
everything-cli and a Nerd Font, plus python, zig, gitleaks and rga if you say
yes to dev tools. nix comes from the `sadirano` Scoop bucket, which the script
adds. It then registers this repo as the nix alias `dotenv` and asks nix to
show you its actions before trusting them.

Everything installs under your user profile, without admin rights. The one
registry change, hooking clink into every cmd window through cmd's
`AutoRun` value, is asked first; security software can flag it, and saying no
is fine.

`setup.ps1 -Print` prints the commands this machine still needs, as
paste-ready PowerShell, and changes nothing. Add `-All` for the full list as
on a new machine.

The optional nix actions, once trusted:

| Command | What it does |
|---|---|
| `hosts` | opens the hosts file elevated, in `$EDITOR` or notepad |
| `env` | opens the Environment Variables editor elevated |
| `h` | hibernates immediately |
| `restart` | kills Explorer, waits for a key, starts it again |

## Claude Code

The paths below assume the clone lives at `~/.dotfiles`; adjust them if not.
Merge the keys from `claude/settings.example.json` into
`~/.claude/settings.json`.

### Status line

```
(alias) <rel-path> > <model>  <branch> <clean|*dirty>  <5h%> / <7d%>
  #<context%>  @<cached>  $<cost>  +<added>/-<removed>  <duration>  <clock>
```

- **quota**: the 5-hour and weekly windows, red past 80%, with time until reset
- **git**: branch and dirty flag from one `git status` call with a timeout,
  hidden outside a repo
- **#context**: context window used; **@cached**: cached input tokens
- **$cost**, **+added/-removed**, **duration**: this session's totals, hidden
  until nonzero
- **(alias)**: when run inside a nix alias, the path is shown relative to it

Windows needs PowerShell 7. Linux and macOS need bash 4.2 or newer (macOS
ships 3.2; install a newer one) and `jq`. Git is optional.

```json
"statusLine": {
  "type": "command",
  "command": "\"$HOME/.dotfiles/claude/statusline.sh\""
}
```

Each render starts a shell, which costs a few hundred milliseconds on
Windows. [gaze](https://github.com/sadirano/gaze) renders the same line as a
native binary in a few milliseconds, with quota pace on top.

### Kill guard

`claude/hooks/guard_broad_kill.py` blocks commands like `taskkill /im
node.exe` or `Stop-Process -Name pwsh`, which kill every process with that
name, Claude Code sessions included. Killing by PID is never blocked. A broad
kill goes through once you type `allow broad kill` in the session. It matches
common command shapes, so treat it as a speed bump rather than a sandbox.
Needs Python.

### Agent guide

`claude/AGENTS.example.md` is a short starting point for
`~/.claude/AGENTS.md`. Copy it and make it yours; it is meant to be edited.

## License

MIT
