# Keeps the Claude Code config in this repo in sync with the live copy in ~/.claude,
# then commits whatever moved. Wired to a SessionStart hook in ~/.claude/settings.json,
# and runnable by hand: r dotenv :sync
#
# Two sync modes, one per file class:
#   linked   - the repo holds the real file and ~/.claude gets a symlink to it.
#              Used for files the user owns (CLAUDE.md): edits land in the repo
#              instantly, so history is never stale. Self-heals if an editor
#              replaces the symlink with a plain file on save.
#   mirrored - the repo holds a copy refreshed on each run. Used for files Claude
#              Code rewrites itself (settings.json), where a symlink would be
#              clobbered by the app's own atomic writes.
#
# Never pushes. Committing is cheap to undo, pushing is the separate decision.

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$repoDir = Join-Path $repo 'claude'
$liveDir = Join-Path $HOME '.claude'

$linked = @('CLAUDE.md')
$mirrored = @('settings.json')

function Get-Text($path) {
    if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { $null }
}

function Set-Text($path, $text) {
    # -NoNewline: $text already carries the file's own trailing newline.
    Set-Content -LiteralPath $path -Value $text -NoNewline -Encoding utf8NoBOM
}

function Test-LinkedTo($path, $target) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.LinkType -ne 'SymbolicLink') { return $false }
    $actual = @($item.Target)[0]
    if (-not $actual) { return $false }
    return [IO.Path]::GetFullPath($actual) -eq [IO.Path]::GetFullPath($target)
}

function Sync-Linked($name) {
    $live = Join-Path $liveDir $name
    $repoFile = Join-Path $repoDir $name

    if (Test-LinkedTo $live $repoFile) { return }

    if (Test-Path -LiteralPath $live) {
        # A real file sits where the link should be: either first run, or an
        # editor did a replace-on-save. Its content is the newest, so it wins.
        $text = Get-Text $live
        if ($text -ne (Get-Text $repoFile)) { Set-Text $repoFile $text }
        Remove-Item -LiteralPath $live -Force
    } elseif (-not (Test-Path -LiteralPath $repoFile)) {
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $live -Target $repoFile -Force | Out-Null
    } catch {
        # No symlink privilege (needs Developer Mode or admin). Fall back to a
        # copy so the live file is never left missing.
        Copy-Item -LiteralPath $repoFile -Destination $live -Force
        Write-Warning "could not link $name, copied instead: $($_.Exception.Message)"
    }
}

function Sync-Mirrored($name) {
    $live = Join-Path $liveDir $name
    $repoFile = Join-Path $repoDir $name
    if (-not (Test-Path -LiteralPath $live)) { return }
    $text = Get-Text $live
    if ($text -ne (Get-Text $repoFile)) { Set-Text $repoFile $text }
}

try {
    foreach ($n in $linked) { Sync-Linked $n }
    foreach ($n in $mirrored) { Sync-Mirrored $n }

    $dirty = git -C $repo status --porcelain -- claude
    if ($LASTEXITCODE -ne 0 -or -not $dirty) { exit 0 }

    $files = @($dirty | ForEach-Object { ($_ -replace '^.{3}', '') -replace '^claude/', '' }) -join ', '
    # Stage first so new files are picked up, then commit with a pathspec so
    # anything else already staged in this repo is left alone.
    git -C $repo add -- claude | Out-Null
    git -C $repo commit -q -m "chore(claude): sync $files" -- claude | Out-Null
} catch {
    Write-Warning "claude config sync failed: $($_.Exception.Message)"
}

exit 0
