# Claude Code status line (Windows / PowerShell 7)
# ------------------------------------------------
# Renders:  <path> > <model>  <branch> <dirty/clean>  <5h%> / <7d%>  #<context%>  @<cached-tokens>  <RAM>MB  <session>
# Quota turns red when a window is over 80%. Fully portable: no hard-coded paths.
# Git branch/status uses a single fast `git status --porcelain --branch` call
# (400ms timeout, killed if it hangs) and is silent in non-repo directories.
# See README.md for one-line install instructions.

$raw = [Console]::In.ReadToEnd()
$e = [char]27
function Color([string]$code, [string]$text) { "$e[${code}m$text$e[0m" }

try { $j = $raw | ConvertFrom-Json } catch { $j = $null }
if (-not $j) { "> ?"; exit 0 }

$parts = @()

# (nix alias) path > model
$pathSeg = (Color '36' "$($j.cwd)") + (Color '90' ' > ') + (Color '35' "$($j.model.display_name)")
if ($env:nix_alias) { $pathSeg = (Color '33' "($($env:nix_alias))") + ' ' + $pathSeg }
$parts += $pathSeg

# git branch + dirty/clean status — single fast call, silent on non-repos
function Invoke-GitFast {
    param([string[]]$GitArgs, [string]$WorkDir, [int]$TimeoutMs = 400)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'git'
        $psi.Arguments = ($GitArgs -join ' ')
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
    $gitOut = Invoke-GitFast -GitArgs @('--no-optional-locks', 'status', '--porcelain=v1', '--branch') -WorkDir $gitCwd -TimeoutMs 400
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

# Claude (node) process RAM in MB - cached per session for speed
$memMB = 0
$nodePid = $null
$cacheFile = Join-Path $env:TEMP "claude-sl-$($j.session_id).pid"
if (Test-Path $cacheFile) {
    $cached = (Get-Content $cacheFile -ErrorAction SilentlyContinue) -as [string]
    if ($cached -match '^\d+$') {
        $p = Get-Process -Id ([int]$cached) -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -match 'node|claude') { $nodePid = [int]$cached }
    }
}
if (-not $nodePid) {
    $cur = $PID
    for ($i = 0; $i -lt 6; $i++) {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -Property ParentProcessId, Name -ErrorAction SilentlyContinue
        if (-not $cim) { break }
        $ppid = $cim.ParentProcessId
        if (-not $ppid -or $ppid -eq 0) { break }
        $pproc = Get-Process -Id $ppid -ErrorAction SilentlyContinue
        if (-not $pproc) { break }
        if ($pproc.ProcessName -match 'node|claude') { $nodePid = [int]$ppid; break }
        $cur = $ppid
    }
    if ($nodePid) { try { Set-Content -Path $cacheFile -Value $nodePid -ErrorAction SilentlyContinue } catch {} }
}
if ($nodePid) {
    $np = Get-Process -Id $nodePid -ErrorAction SilentlyContinue
    if ($np) { $memMB = [math]::Round($np.WorkingSet64 / 1MB) }
}
if ($memMB -gt 0) { $parts += Color '90' "${memMB}MB" }

# session id (short)
$sid = "$($j.session_id)"
if ($sid.Length -gt 8) { $sid = $sid.Substring(0, 8) }
$parts += Color '90' $sid

($parts -join '  ')
