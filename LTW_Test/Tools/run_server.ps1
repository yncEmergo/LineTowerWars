# Launches the LTW dedicated server.
#
# Usage lives in server.md. Short version:
#   .\Tools\run_server.ps1                 headless on the configured port
#   .\Tools\run_server.ps1 -Windowed       same, but with the log window
#   .\Tools\run_server.ps1 -Port 7778      on another port
#   .\Tools\run_server.ps1 -MatchProcesses each match in a process of its own (D44)
#
# Ctrl+C stops it.

param(
    [int]$Port = 0,
    [switch]$Windowed,
    [switch]$MatchProcesses,
    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
# This script lives in Tools/, so the PROJECT is one level up. Everything below
# aims at $projectRoot rather than $PSScriptRoot - Godot is handed the project
# folder, and the running-server check matches on that folder's name.
$projectRoot = Split-Path $PSScriptRoot -Parent


# Where Godot is: the -Godot argument, then $env:GODOT, then the path this
# machine remembered, then a look in the usual places. Nothing here is a project
# setting, it is just where this PC happens to keep the editor - and the hunt
# for it is shared with build_client.ps1 and run_bench.ps1 rather than guessed
# at three times over. godot_path.ps1 has the reasoning.
. (Join-Path $PSScriptRoot "godot_path.ps1")
$exe = Resolve-GodotExe -Explicit $Godot -ProjectRoot $projectRoot -ScriptName "run_server.ps1"
if ([string]::IsNullOrWhiteSpace($exe)) { exit 1 }

# Refuse to start a second server on the same port. Without this the second one
# fails deep inside ENet with "Could not open the server port", which reads like
# a bug rather than like "one is already running". Two servers on DIFFERENT
# ports is legitimate, so -Port skips the check.
#
# `--match-server` is excluded explicitly (D44). It is belt and braces rather
# than a fix: `*--server*` does not actually match `--match-server`, because the
# pattern needs two consecutive hyphens and there the `server` is preceded by
# one. Said out loud because the opposite was believed for a while and put a
# false comment in two scripts - see `stop_server.ps1`, where the same mistake
# was a real bug.
$projectName = Split-Path $projectRoot -Leaf
$running = @(Get-CimInstance Win32_Process -Filter "Name like '%odot%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*--server*" -and
                   $_.CommandLine -notlike "*--match-server*" -and
                   $_.CommandLine -like "*$projectName*" })

if ($running.Count -gt 0 -and $Port -le 0) {
    Write-Host "A server is already running:" -ForegroundColor Yellow
    foreach ($r in $running) { Write-Host ("  PID {0}" -f $r.ProcessId) }
    Write-Host ""
    Write-Host "Stop it first:      .\Tools\stop_server.ps1"
    Write-Host "Or use a new port:  .\Tools\run_server.ps1 -Port 7778"
    exit 1
}

# --server after the "--" separator, because Godot treats an unrecognised
# argument BEFORE the separator as an engine argument and refuses to start.
$argList = @("--path", $projectRoot)
if (-not $Windowed) { $argList += "--headless" }
$argList += @("--", "--server")
if ($Port -gt 0) { $argList += @("--port", "$Port") }
# D44: each match in a process of its own. Off by default, because the whole of
# that work sits on main without changing anything for anyone until it ships.
if ($MatchProcesses) { $argList += "--match-processes" }

$mode = "headless"
if ($Windowed) { $mode = "windowed" }
Write-Host "Starting the LTW dedicated server ($mode). Ctrl+C to stop." -ForegroundColor Cyan
Write-Host ""

& $exe $argList
