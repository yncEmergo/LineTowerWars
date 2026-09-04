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

# How long a server has been up, and whether that is long enough to have gone
# stale. A running server holds the scripts it PARSED AT BOOT, so every pull,
# checkout, deploy or revert since then has silently moved the working tree out
# from under it. Godot routes an rpc by its INDEX in the method list, so two
# builds whose @rpc sets differ deliver calls to the wrong function - and the
# build handshake does not catch it, because protocol_version never changed.
#
# Cost an hour on 2026-09-04: a server left up overnight against a client three
# commits newer, which presented as the lobby browser hanging on "Creating
# lobby..." for ever. Uptime next to a fresh checkout is the tell, so print it.
function Format-Uptime([datetime] $start) {
    $span = (Get-Date) - $start
    if ($span.TotalHours -ge 1) {
        return ("up {0:n1}h  (since {1:HH:mm} on {1:ddd})" -f $span.TotalHours, $start)
    }
    return ("up {0:n0}m" -f $span.TotalMinutes)
}

foreach ($s in $servers) {
    $port = "default"
    if ($s.CommandLine -match "--port\s+(\d+)") { $port = $Matches[1] }

    $proc = Get-Process -Id $s.ProcessId -ErrorAction SilentlyContinue
    $age = ""
    $stale = $false
    if ($proc -and $proc.StartTime) {
        $age = Format-Uptime $proc.StartTime
        $stale = ((Get-Date) - $proc.StartTime).TotalHours -ge 1
    }

    if ($List) {
        Write-Host ("  PID {0}   port {1}   {2}" -f $s.ProcessId, $port, $age)
        if ($stale) {
            Write-Host ("     ^ running since before your last checkout? " +
                "Restart it - it still holds the scripts it booted with.") -ForegroundColor Yellow
        }
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
