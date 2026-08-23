# Launches the LTW dedicated server.
#
# Usage lives in server.md. Short version:
#   .\run_server.ps1                 headless on the configured port
#   .\run_server.ps1 -Windowed       same, but with the log window
#   .\run_server.ps1 -Port 7778      on another port
#
# Ctrl+C stops it.

param(
    [int]$Port = 0,
    [switch]$Windowed,
    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"

# Where Godot is: the -Godot argument, then the GODOT environment variable,
# then the usual spot. Nothing here is a project setting, it is just where this
# machine happens to keep the editor.
$exe = $Godot
if ([string]::IsNullOrWhiteSpace($exe)) { $exe = $env:GODOT }
if ([string]::IsNullOrWhiteSpace($exe)) { $exe = Join-Path $env:USERPROFILE "Desktop\Godot 4.7.1.exe" }

if (-not (Test-Path $exe)) {
    Write-Host "Godot executable not found:" -ForegroundColor Red
    Write-Host "  $exe"
    Write-Host ""
    Write-Host "Point this script at it once, either way:"
    Write-Host '  $env:GODOT = "C:\path\to\Godot.exe"      (this terminal only)'
    Write-Host '  .\run_server.ps1 -Godot "C:\path\to\Godot.exe"'
    exit 1
}

# Refuse to start a second server on the same port. Without this the second one
# fails deep inside ENet with "Could not open the server port", which reads like
# a bug rather than like "one is already running". Two servers on DIFFERENT
# ports is legitimate, so -Port skips the check.
$projectName = Split-Path $PSScriptRoot -Leaf
$running = @(Get-CimInstance Win32_Process -Filter "Name like '%odot%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*--server*" -and $_.CommandLine -like "*$projectName*" })

if ($running.Count -gt 0 -and $Port -le 0) {
    Write-Host "A server is already running:" -ForegroundColor Yellow
    foreach ($r in $running) { Write-Host ("  PID {0}" -f $r.ProcessId) }
    Write-Host ""
    Write-Host "Stop it first:      .\stop_server.ps1"
    Write-Host "Or use a new port:  .\run_server.ps1 -Port 7778"
    exit 1
}

# --server after the "--" separator, because Godot treats an unrecognised
# argument BEFORE the separator as an engine argument and refuses to start.
$argList = @("--path", $PSScriptRoot)
if (-not $Windowed) { $argList += "--headless" }
$argList += @("--", "--server")
if ($Port -gt 0) { $argList += @("--port", "$Port") }

$mode = "headless"
if ($Windowed) { $mode = "windowed" }
Write-Host "Starting the LTW dedicated server ($mode). Ctrl+C to stop." -ForegroundColor Cyan
Write-Host ""

& $exe $argList
