# setup.ps1 - the small, work-safe machine setup.
#
# Installs the command-line tools I use through Scoop, registers this repo as
# the nix alias `dotenv`, exports its commands (hosts, env, h, restart) onto
# PATH, and configures clink. Everything lands under the user profile and needs
# no admin rights. The one registry change (cmd's AutoRun, to load clink in
# every cmd window) is asked first and can be skipped.
#
# Needs Scoop and git first (see README). Safe to re-run: installs and the
# alias are skipped when already in place.
#
#   powershell -File setup.ps1
#   powershell -File setup.ps1 -Print        the commands still needed here; changes nothing
#   powershell -File setup.ps1 -Print -All   every command, as on a new machine
#
# -Print writes paste-ready PowerShell, with everything else as comments, so
# `> setup-cmds.ps1` saves a script you can read and run yourself.

param([switch]$Print, [switch]$All)

function Step($text) {
    if ($Print) { "`n# == $text" } else { Write-Host "`n== $text" -ForegroundColor Cyan }
}
function Say($text) {
    if ($Print) { "# $text" } else { Write-Host $text }
}
# Run prints the command under -Print and runs it otherwise, so the printed
# list is always what setup does.
function Run($cmd) {
    if ($Print) { $cmd } else { Invoke-Expression $cmd }
}
# Have answers a check as "not there yet" under -All, so the whole list prints.
function Have($found) { (-not $All) -and $found }

$scoop = [bool](Get-Command scoop -ErrorAction SilentlyContinue)
if (-not (Have $scoop)) {
    if (-not $Print) {
        Write-Host "Scoop is missing. Install it first (see README), then re-run this." -ForegroundColor Yellow
        exit 1
    }
    Step "Scoop and git"
    "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
    "irm get.scoop.sh | iex"
    "scoop install git"
}

Step "Scoop packages"
$buckets = if ($scoop) { (scoop bucket list).Name } else { @() }
if (-not (Have ($buckets -contains "sadirano"))) {
    Run "scoop bucket add sadirano https://github.com/sadirano/bucket"
}
foreach ($b in "extras", "nerd-fonts") {
    if (-not (Have ($buckets -contains $b))) { Run "scoop bucket add $b" }
}
$apps = "nix", "clink", "fzf", "ripgrep", "fd", "bat", "neovim",
        "pwsh", "gh", "delta", "jq", "everything-cli", "Mononoki-NF-Mono"
$dev = "python", "zig", "gitleaks", "rga"
if (-not $Print -and (Read-Host "Also install dev tools ($($dev -join ', '))? [y/N]") -eq "y") {
    $apps += $dev
}
foreach ($app in $apps) {
    $found = Test-Path "$env:USERPROFILE\scoop\apps\$app"
    # nix-nightly provides the same nix; installing both would collide.
    if ($app -eq "nix") { $found = $found -or (Test-Path "$env:USERPROFILE\scoop\apps\nix-nightly") }
    if (Have $found) { Say "$app is installed" }
    else { Run "scoop install $app" }
}
if ($Print) {
    $missing = $dev | Where-Object { -not (Have (Test-Path "$env:USERPROFILE\scoop\apps\$_")) }
    if ($missing) {
        Say "optional dev tools:"
        Say "scoop install $($missing -join ' ')"
    }
}

Step "nix alias 'dotenv' -> $PSScriptRoot"
$current = if (Get-Command nix -ErrorAction SilentlyContinue) { [string](nix dotenv 2>$null | Select-Object -First 1) } else { "" }
if (-not (Have (($current.Trim().TrimEnd("\", "/") -replace "/", "\") -eq $PSScriptRoot.TrimEnd("\")))) {
    Run "nix dotenv '$PSScriptRoot'"
} else {
    Say "Already registered."
}

Step "Commands on PATH (hosts, env, h, restart)"
Say "nix shows what this repo's actions run and asks before trusting them."
Run "nix --trust dotenv"
Run "nix --sync-bin"

Step "clink"
Run "clink set clink.logo none | Out-Null"
Run "clink set clink.autostart '' | Out-Null"
Run "clink set clink.autoupdate off | Out-Null"
Run "clink set autosuggest.inline true | Out-Null"
if (-not $Print) { Write-Host "Settings applied." }

$key = "HKCU:\Software\Microsoft\Command Processor"
$autoRun = (Get-ItemProperty -Path $key -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
if (Have ($autoRun -match "clink")) {
    Say "Already hooked into cmd."
} elseif ($Print) {
    Say "optional: hook clink into every cmd window. This writes cmd's AutoRun"
    Say "registry value, which security software can flag on a managed machine."
    Say "--nolog: clink would otherwise write clink.log on every cmd start."
    Say "clink autorun install -- --nolog"
    Say "Then point AutoRun at the x64 loader instead of clink.bat:"
    Say "`$k = '$key'; Set-ItemProperty `$k AutoRun ((Get-ItemProperty `$k).AutoRun -replace 'clink\.bat', 'clink_x64.exe')"
} else {
    Write-Host "Hooking clink into every cmd window writes cmd's AutoRun registry value."
    Write-Host "Security software can flag that on a managed machine."
    if ((Read-Host "Hook it in? [y/N]") -eq "y") {
        # --nolog: clink would otherwise write clink.log on every cmd start.
        clink autorun install -- --nolog | Out-Null
        # autorun install points at clink.bat, which cmd re-parses on every
        # start just to pick the loader. Point at the x64 loader directly.
        $autoRun = (Get-ItemProperty -Path $key -Name AutoRun).AutoRun
        if ($autoRun -match '"?([A-Za-z]:\\[^"]*?)\\clink\.bat"?\s+inject') {
            $exe = Join-Path $matches[1] "clink_x64.exe"
            if (Test-Path $exe) {
                Set-ItemProperty -Path $key -Name AutoRun -Value $autoRun.Replace((Join-Path $matches[1] "clink.bat"), $exe)
            }
        }
        Write-Host "Hooked. Open a new cmd window to use it."
    } else {
        Write-Host "Skipped. Run 'clink inject' in a cmd window to load it once."
    }
}

if (-not $Print) { Step "Done" }
