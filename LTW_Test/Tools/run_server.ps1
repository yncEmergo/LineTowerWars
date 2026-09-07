# Launches the LTW dedicated server.
#
# Usage lives in server.md. Short version:
#   .\Tools\run_server.ps1                 headless on the configured port
#   .\Tools\run_server.ps1 -Windowed       same, but with the log window
#   .\Tools\run_server.ps1 -Port 7778      on another port
#
# Ctrl+C stops it.

param(
    [int]$Port = 0,
    [switch]$Windowed,
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
$projectName = Split-Path $projectRoot -Leaf
$running = @(Get-CimInstance Win32_Process -Filter "Name like '%odot%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*--server*" -and $_.CommandLine -like "*$projectName*" })

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

$mode = "headless"
if ($Windowed) { $mode = "windowed" }
Write-Host "Starting the LTW dedicated server ($mode). Ctrl+C to stop." -ForegroundColor Cyan
Write-Host ""

& $exe $argList
