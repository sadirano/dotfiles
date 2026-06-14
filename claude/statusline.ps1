# Claude Code status line (Windows / PowerShell 7)
# ------------------------------------------------
# Renders:  <path> > <model>  <5h%> / <7d%>  #<context%>  <RAM>MB  <session>
# Quota turns red when a window is over 80%. Fully portable: no hard-coded paths.
# See README.md for one-line install instructions.

$raw = [Console]::In.ReadToEnd()
$e = [char]27
function Color([string]$code, [string]$text) { "$e[${code}m$text$e[0m" }

try { $j = $raw | ConvertFrom-Json } catch { $j = $null }
if (-not $j) { "> ?"; exit 0 }

$parts = @()

# path > model
$parts += (Color '36' "$($j.cwd)") + (Color '90' ' > ') + (Color '35' "$($j.model.display_name)")

# quota (rate limits): 5-hour / 7-day — red when over 80%, else yellow
if ($j.rate_limits) {
    $h5 = $j.rate_limits.five_hour.used_percentage
    $d7 = $j.rate_limits.seven_day.used_percentage
    $c5 = if ($h5 -gt 80) { '31' } else { '33' }
    $c7 = if ($d7 -gt 80) { '31' } else { '33' }

    function TimeLeft([string]$iso) {
        if (-not $iso) { return $null }
        try {
            $diff = ([datetime]::Parse($iso).ToUniversalTime()) - [datetime]::UtcNow
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
