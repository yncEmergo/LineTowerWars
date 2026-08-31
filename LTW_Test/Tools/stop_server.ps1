# Stops any LTW dedicated server running on this machine.
#
#   .\Tools\stop_server.ps1          stop them
#   .\Tools\stop_server.ps1 -List    just show what is running
#
# A server is identified by its COMMAND LINE containing "--server", scoped to
# this project folder. Matching on the process name alone is not enough: the
# editor and every game window it launches are all "Godot", and killing those
# by mistake takes the editor with them.

param(
    [switch]$List
)
# This script lives in Tools/, so the PROJECT is one level up. Everything below
# aims at $projectRoot rather than $PSScriptRoot - Godot is handed the project
# folder, and the running-server check matches on that folder's name.
$projectRoot = Split-Path $PSScriptRoot -Parent


$projectName = Split-Path $projectRoot -Leaf

$servers = @(Get-CimInstance Win32_Process -Filter "Name like '%odot%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*--server*" -and $_.CommandLine -like "*$projectName*" })

if ($servers.Count -eq 0) {
    Write-Host "No LTW server is running." -ForegroundColor DarkGray
    exit 0
}

foreach ($s in $servers) {
    $port = "default"
    if ($s.CommandLine -match "--port\s+(\d+)") { $port = $Matches[1] }
    if ($List) {
        Write-Host ("  PID {0}   port {1}" -f $s.ProcessId, $port)
    } else {
        Stop-Process -Id $s.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host ("Stopped server PID {0} (port {1})" -f $s.ProcessId, $port) -ForegroundColor Yellow
    }
}

if (-not $List) {
    # The OS can hold the UDP socket for a moment after the process dies, which
    # is why an immediate restart sometimes reports the port as already in use.
    Start-Sleep -Milliseconds 700
}
