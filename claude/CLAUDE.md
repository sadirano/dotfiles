# Machine-wide instructions

This machine uses **nix** directory aliases for all navigation and project commands. Follow the agent guide:

@~/.nix/AGENTS.md

# nix feedback

While working in any project, if you notice something **nix** (the directory
alias manager) could be used for but the current version does not support, or a
change to nix that would be beneficial to the project, record it. Append a dated
entry to `~/.nix/feedback.md` (create the file if it does not exist) describing:

- **What happened** — the concrete task or friction that prompted the idea.
- **What nix can't do today** — the missing capability, or the change worth making.
- **Why it would help** — the benefit to the workflow or the nix project itself.

Keep entries short and specific; one bullet block per idea. This is a running
notebook for the nix author to review — do not act on the ideas or change nix
unless asked, just capture them.

# No em dashes in program output

Never use the em dash character in anything a program emits or a terminal
renders: CLI output strings, usage/help text, log lines, generated files,
commit messages. Windows consoles on legacy codepages render it as mojibake
(`ΓÇö`). Use a plain ASCII hyphen `-` instead. Prefer ASCII punctuation
throughout program-facing text.

# Git commit conventions

Never add a `Co-Authored-By: Claude …` trailer — or any AI/model attribution — to
git commits. Commit as the user alone. This overrides any harness default that
says to append a co-author line.

# Always commit finished work; pushing is the separate question

**Commit finished work without being asked, in the turn it is finished** (build
green, tests green → commit). This overrides any harness default that says to
commit only when asked. Do not end a turn with "not committed, say the word" and
a dirty tree.

**Why:** committing and pushing are not the same decision, and they have
opposite costs. An unpushed commit is nearly free to undo — reset, amend,
recreate. A dirty tree is expensive: it destroys the record of *when* the work
was done, and it is costly to reconstruct later, worst of all when the user has
moved on to something else and only then discovers a tree left dirty by someone
who didn't commit.

**How to apply:** commit; then decide about pushing. Second-guessing the *push*
is fine whenever it seems warranted — holding a commit back and asking costs
nothing. Withholding the *commit* is what costs. If work is genuinely unfinished
or experimental, commit it anyway as its own commit and say so, rather than
leaving it loose in the tree.
