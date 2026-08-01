# Claude Code status line (Windows / PowerShell 7)
# ------------------------------------------------
# Renders:  (<alias>) <rel-path> > <model>  <branch> <dirty/clean>  <5h%> / <7d%>
#           #<context%>  @<cached-tokens>  $<cost>  +<added>/-<removed>  <duration>  <clock>
# Quota turns red when a window is over 80%. Fully portable: no hard-coded paths.
# Git branch/status uses a single fast `git status --porcelain --branch` call
# (400ms timeout, killed if it hangs) and is silent in non-repo directories.
# See README.md for one-line install instructions.

$raw = [Console]::In.ReadToEnd()

# emit UTF-8 regardless of the console codepage: redirected stdout otherwise
# uses the legacy codepage, which turns the owl badge (a surrogate pair) into ??
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$e = [char]27
function Color([string]$code, [string]$text) { "$e[${code}m$text$e[0m" }

try { $j = $raw | ConvertFrom-Json } catch { $j = $null }
if (-not $j) { "> ?"; exit 0 }

$parts = @()

# (nix alias) path > model
# Inside an `o`/`x` session nix exports NIX_ALIAS + NIX_ALIAS_PATH, so the alias
# root collapses to its name and only the part below it is spelled out. Outside
# one (or in an unrelated directory) fall back to the full absolute path.
$cwd = "$($j.cwd)"
$aliasName = $env:NIX_ALIAS
$aliasRoot = "$($env:NIX_ALIAS_PATH)".TrimEnd('\', '/')
$rel = $null
if ($aliasName -and $aliasRoot -and $cwd) {
    if ($cwd.TrimEnd('\', '/') -eq $aliasRoot) {
        $rel = ''
    } elseif ($cwd.StartsWith($aliasRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $cwd.Substring($aliasRoot.Length + 1)
    }
}

if ($null -ne $rel) {
    $pathSeg = Color '33' "($aliasName)"
    if ($rel -ne '') { $pathSeg += ' ' + (Color '36' $rel) }
} else {
    $pathSeg = Color '36' $cwd
    if ($aliasName) { $pathSeg = (Color '33' "($aliasName)") + ' ' + $pathSeg }
}
$parts += $pathSeg + (Color '90' ' > ') + (Color '35' "$($j.model.display_name)")

# fast external call with a hard timeout — used for git and hoot below;
# anything that hangs is killed so the status line never stalls
function Invoke-Fast {
    param([string]$FileName, [string[]]$CmdArgs, [string]$WorkDir, [int]$TimeoutMs = 400)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FileName
        $psi.Arguments = ($CmdArgs -join ' ')
        $psi.WorkingDirectory = $WorkDir
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            return $null
        }
        $out = $p.StandardOutput.ReadToEnd()
        if ($p.ExitCode -ne 0) { return $null }
        return $out
    } catch { return $null }
}

$gitCwd = $j.cwd
if (-not $gitCwd) { $gitCwd = $j.workspace.current_dir }

if ($gitCwd -and (Test-Path $gitCwd)) {
    # one call: first line is "## branch...upstream [ahead/behind]", rest are dirty entries
    $gitOut = Invoke-Fast -FileName 'git' -CmdArgs @('--no-optional-locks', 'status', '--porcelain=v1', '--branch') -WorkDir $gitCwd -TimeoutMs 400
    if ($gitOut) {
        # wrap in @(...) — a single-line $gitOut would otherwise unwrap to a scalar
        # [char] after -split, and $lines[0].StartsWith would crash
        $lines = @($gitOut -split "`r?`n" | Where-Object { $_ -ne '' })
        if ($lines.Count -gt 0 -and $lines[0].StartsWith('## ')) {
            $branch = ($lines[0].Substring(3) -split '\.\.\.')[0].Trim()
            if ($branch -match '^HEAD \(no branch\)') { $branch = 'detached' }
            $dirty = $lines.Count -gt 1
            $indicator = if ($dirty) { Color '33' '*dirty' } else { Color '32' 'clean' }
            $parts += (Color '36' $branch) + ' ' + $indicator
        }
    }
}

# hoot: unseen inbox badge — hidden when the inbox is empty or hoot is absent.
# Reading the count also gives hoot's piggybacked nag a regular heartbeat.
$hootOut = Invoke-Fast -FileName 'hoot' -CmdArgs @('count') -WorkDir $env:USERPROFILE -TimeoutMs 500
if ($hootOut) {
    $n = $hootOut.Trim() -as [int]
    if ($n -gt 0) { $parts += Color '33' "$([char]::ConvertFromUtf32(0x1F989))$n" }
}

# quota (rate limits): 5-hour / 7-day — red when over 80%, else yellow
if ($j.rate_limits) {
    $h5 = $j.rate_limits.five_hour.used_percentage
    $d7 = $j.rate_limits.seven_day.used_percentage
    $c5 = if ($h5 -gt 80) { '31' } else { '33' }
    $c7 = if ($d7 -gt 80) { '31' } else { '33' }

    function TimeLeft([long]$unix) {
        if (-not $unix) { return $null }
        try {
            $diff = [DateTimeOffset]::FromUnixTimeSeconds($unix).UtcDateTime - [datetime]::UtcNow
            if ($diff.TotalSeconds -le 0) { return $null }
            $h = [int]$diff.TotalHours
            $m = $diff.Minutes
            if ($h -gt 0) { return "@${h}h${m}m" } else { return "@${m}m" }
        } catch { return $null }
    }

    $r5 = TimeLeft $j.rate_limits.five_hour.resets_at
    $r7 = TimeLeft $j.rate_limits.seven_day.resets_at

    $seg5 = (Color $c5 "${h5}%") + $(if ($r5) { Color '90' " $r5" } else { '' })
    $seg7 = (Color $c7 "${d7}%") + $(if ($r7) { Color '90' " $r7" } else { '' })
    $parts += $seg5 + (Color '33' ' / ') + $seg7
}

# context window usage
if ($null -ne $j.context_window.used_percentage) {
    $parts += Color '32' "#$($j.context_window.used_percentage)%"
}

# cached context tokens (cache_read + cache_creation), formatted with k/M suffixes
function Format-TokenCount([long]$n) {
    if ($n -ge 1000000) { return "{0:N1}M" -f ($n / 1000000) }
    if ($n -ge 1000) { return "{0:N1}k" -f ($n / 1000) }
    return "$n"
}

$cacheRead = $j.context_window.current_usage.cache_read_input_tokens
$cacheCreate = $j.context_window.current_usage.cache_creation_input_tokens
$cachedTotal = [long]0
if ($cacheRead) { $cachedTotal += [long]$cacheRead }
if ($cacheCreate) { $cachedTotal += [long]$cacheCreate }

if ($cachedTotal -gt 0) {
    $parts += Color '90' "@$(Format-TokenCount $cachedTotal)"
}

# session cost so far
$cost = $j.cost.total_cost_usd
if ($cost -and $cost -gt 0) {
    $parts += Color '92' ('$' + ('{0:N2}' -f $cost))
}

# lines added / removed this session
$added = [int]$j.cost.total_lines_added
$removed = [int]$j.cost.total_lines_removed
if ($added -gt 0 -or $removed -gt 0) {
    $parts += (Color '32' "+$added") + (Color '90' '/') + (Color '31' "-$removed")
}

# session wall-clock duration
$ms = $j.cost.total_duration_ms
if ($ms -and $ms -gt 0) {
    $span = [TimeSpan]::FromMilliseconds([double]$ms)
    $dur = if ($span.TotalHours -ge 1) { "{0}h{1}m" -f [int]$span.TotalHours, $span.Minutes }
           elseif ($span.TotalMinutes -ge 1) { "{0}m" -f [int]$span.TotalMinutes }
           else { "{0}s" -f [int]$span.TotalSeconds }
    $parts += Color '90' $dur
}

# wall clock
$parts += Color '90' (Get-Date -Format 'HH:mm')

($parts -join '  ')
