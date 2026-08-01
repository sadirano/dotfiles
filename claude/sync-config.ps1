# Keeps the Claude Code config in this repo in sync with the live copy in ~/.claude,
# then commits whatever moved. Wired to a SessionStart hook in ~/.claude/settings.json,
# and runnable by hand: r dotenv :sync
#
# Two sync modes, one per file class:
#   linked   - the repo holds the real file and ~/.claude gets a symlink to it.
#              Used for files the user owns (CLAUDE.md): edits land in the repo
#              instantly, so history is never stale. Self-heals if an editor
#              replaces the symlink with a plain file on save.
#   mirrored - the repo holds a FILTERED copy refreshed on each run. Used for
#              files Claude Code rewrites itself (settings.json), where a symlink
#              would be clobbered by the app's own atomic writes.
#
# This repo is public, and settings.json is a file both Claude Code and I write.
# It legitimately supports keys that must never be published - `env` is the
# documented home for ANTHROPIC_API_KEY, and apiKeyHelper / awsAuthRefresh /
# awsCredentialExport are credential plumbing - so the mirror publishes an
# ALLOWLIST of top-level keys and drops everything else. It fails closed: a key
# nobody has vetted is omitted, including keys added by future Claude versions.
#
# The consequence, on purpose: the mirrored file is a publishable subset, not a
# backup. Restoring from it will not bring back anything unlisted.
#
# Never pushes. Committing is cheap to undo, pushing is the separate decision.

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$repoDir = Join-Path $repo 'claude'
$liveDir = Join-Path $HOME '.claude'

$linked = @('CLAUDE.md')
$mirrored = @('settings.json')

# Top-level settings.json keys safe to publish. Add to this deliberately, after
# checking the key cannot carry a credential or a private path.
$publishable = @{
    'settings.json' = @(
        'model',
        'hooks',
        'statusLine',
        'tui',
        'agentPushNotifEnabled',
        'cleanupPeriodDays',
        'includeCoAuthoredBy',
        'outputStyle',
        'spinnerTipsEnabled',
        'theme',
        'verbose'
    )
}

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

# Keeps only allowlisted top-level keys, in the order the live file lists them so
# a reordering by Claude Code does not churn the diff. Returns $null when the
# file cannot be parsed, which the caller treats as "publish nothing new" - an
# unreadable file must not fall through to publishing it verbatim.
function Get-PublishableJson($text, $allowed) {
    try {
        $obj = $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "settings.json is not valid JSON; leaving the mirrored copy untouched"
        return $null
    }

    $kept = [ordered]@{}
    $dropped = @()
    foreach ($p in $obj.PSObject.Properties) {
        if ($allowed -contains $p.Name) { $kept[$p.Name] = $p.Value } else { $dropped += $p.Name }
    }

    if ($dropped.Count -gt 0) {
        Write-Warning "not publishing $($dropped -join ', ') - add to `$publishable in sync-config.ps1 if intended"
    }

    # Depth 100: hooks nest several levels and the default of 2 would silently
    # stringify them into "System.Object[]".
    ($kept | ConvertTo-Json -Depth 100) + "`n"
}

function Sync-Mirrored($name) {
    $live = Join-Path $liveDir $name
    $repoFile = Join-Path $repoDir $name
    if (-not (Test-Path -LiteralPath $live)) { return }

    $text = Get-Text $live
    if ($publishable.ContainsKey($name)) {
        $text = Get-PublishableJson $text $publishable[$name]
        if ($null -eq $text) { return }
    }
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
