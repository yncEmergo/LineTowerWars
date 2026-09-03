# Runs the match load test and prints what a tick costs.
#
# Each scenario is its OWN Godot process, deliberately: a run that has already
# filled ten mazes cannot be torn back down to a clean world, and one that
# crashes must not take the rest of the matrix with it.
#
#   .\Tools\run_bench.ps1                  the whole matrix, headless
#   .\Tools\run_bench.ps1 -Quick           the same, with short measurement windows
#   .\Tools\run_bench.ps1 -Only ten        only the scenarios whose name matches
#   .\Tools\run_bench.ps1 -Players 12      override the crowded scenarios' lane count
#
# The client scenarios open a window on purpose - they are the ones measuring
# what it costs to DRAW this, and a headless Godot has no renderer.
#
# Reports land in Reports\ as JSON, one per scenario, so two runs can be
# compared after a change.

param(
    [string]$Godot = "",
    [int]$TimeoutSeconds = 600,
    [int]$Players = 10,
    [string]$Only = "",
    [switch]$Quick,
    [switch]$KeepLogs
)

$ErrorActionPreference = "Stop"
# This script lives in Tools/, so the PROJECT is one level up. Everything below
# aims at $projectRoot rather than $PSScriptRoot - Godot is handed the project
# folder, and the running-server check matches on that folder's name.
$projectRoot = Split-Path $PSScriptRoot -Parent


# Where Godot is: the -Godot argument, then the GODOT environment variable,
# then the usual spot. Same order as run_server.ps1, and for the same reason -
# none of it is a project setting.
$exe = $Godot
if ([string]::IsNullOrWhiteSpace($exe)) { $exe = $env:GODOT }
if ([string]::IsNullOrWhiteSpace($exe)) { $exe = Join-Path $env:USERPROFILE "Desktop\Godot 4.7.1.exe" }

if (-not (Test-Path $exe)) {
    Write-Host "Godot executable not found:" -ForegroundColor Red
    Write-Host "  $exe"
    Write-Host ""
    Write-Host "Point this script at it once, either way:"
    Write-Host '  $env:GODOT = "C:\path\to\Godot.exe"      (this terminal only)'
    Write-Host '  .\Tools\run_bench.ps1 -Godot "C:\path\to\Godot.exe"'
    exit 1
}

$seconds = if ($Quick) { 6 } else { 20 }

# Each scenario answers one question, and they are ordered so that the answer
# to the next one is the difference from the last: towers alone, then towers
# with a full population, then the same on ten lanes, then the same again with
# a renderer and a HUD in front of it.
$scenarios = @(
    @{ name = "1v1-towers";      scene = "server"; players = 2;        creeps = 0   }
    @{ name = "1v1-full";        scene = "server"; players = 2;        creeps = 100 }
    @{ name = "ten-towers";      scene = "server"; players = $Players; creeps = 0   }
    @{ name = "ten-full";        scene = "server"; players = $Players; creeps = 100 }
    @{ name = "ten-plain";       scene = "server"; players = $Players; creeps = 100; tower = "archer_stats" }
    @{ name = "client-1v1";      scene = "client"; players = 2;        creeps = 100 }
    @{ name = "client-ten";      scene = "client"; players = $Players; creeps = 100 }
    # FEW TOWERS, MANY CREEPS - the early game, and the shape a stutter was
    # actually reported in. Every scenario above fills the maze, so the whole
    # matrix asked "what does a LOT of towers cost" and none of it asked what a
    # lane full of creeps costs on its own. Creeps were already the dominant
    # cost with a full maze; this is the same question with the towers taken
    # away, which is what separates a per-creep cost from a per-tower one.
    @{ name = "1v1-fewtowers";    scene = "server"; players = 2; creeps = 150; towers = 8 }
    @{ name = "client-fewtowers"; scene = "client"; players = 2; creeps = 150; towers = 8 }
)

if (-not [string]::IsNullOrWhiteSpace($Only)) {
    $scenarios = @($scenarios | Where-Object { $_.name -like "*$Only*" })
    if ($scenarios.Count -eq 0) {
        Write-Host "No scenario matches '$Only'." -ForegroundColor Red
        exit 1
    }
}

$reports = Join-Path $projectRoot "Reports"
if (-not (Test-Path $reports)) { New-Item -ItemType Directory -Path $reports | Out-Null }

Write-Host ""
Write-Host "Godot:   $exe"
Write-Host "Reports: $reports"
Write-Host ""

$summary = @()

foreach ($s in $scenarios) {
    $log = Join-Path $env:TEMP ("ltw_bench_" + $s.name + ".log")
    $err = Join-Path $env:TEMP ("ltw_bench_" + $s.name + ".err")
    $json = Join-Path $reports ($s.name + ".json")

    # --headless for the server scenarios only. A client scenario is measuring
    # the renderer, so taking the renderer away would measure nothing.
    # Quoted by hand: Start-Process joins the array with spaces, so a project
    # path with a space in it arrives as two arguments and Godot aborts on the
    # first half. Cost a run to find.
    $argList = @("--path", "`"$projectRoot`"")
    if ($s.scene -eq "server") { $argList += "--headless" }
    $argList += @("res://Scenes/Tools/perf_bench.tscn", "--")
    $argList += @("scene=$($s.scene)", "players=$($s.players)", "creeps=$($s.creeps)")
    $argList += @("seconds=$seconds", "`"out=$json`"")
    if ($s.ContainsKey("tower")) { $argList += "tower=$($s.tower)" }
    if ($s.ContainsKey("towers")) { $argList += "towers=$($s.towers)" }

    Write-Host ("-- {0}  ({1} scene, {2} players, {3} creeps each)" -f `
        $s.name, $s.scene, $s.players, $s.creeps) -ForegroundColor Cyan

    $proc = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $err

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        Write-Host "   timed out after $TimeoutSeconds s, killed" -ForegroundColor Red
        try { $proc.Kill() } catch {}
        continue
    }

    $lines = @()
    if (Test-Path $log) { $lines = @(Get-Content $log | Where-Object { $_ -like "BENCH *" }) }

    if ($lines.Count -eq 0) {
        Write-Host "   no report - see $log and $err" -ForegroundColor Red
        continue
    }

    foreach ($line in $lines) { Write-Host ("   " + $line.Substring(6)) }
    Write-Host ""

    $tick = $lines | Where-Object { $_ -like "BENCH tick_ms *" } | Select-Object -First 1
    $world = $lines | Where-Object { $_ -like "BENCH world *" } | Select-Object -First 1
    $summary += [pscustomobject]@{
        Scenario = $s.name
        World    = if ($world) { $world.Substring(12) } else { "" }
        Tick     = if ($tick) { $tick.Substring(14) } else { "" }
    }

    if (-not $KeepLogs) {
        Remove-Item $log, $err -ErrorAction SilentlyContinue
    }
}

Write-Host "==== summary ====" -ForegroundColor Green
$summary | Format-List
Write-Host "JSON reports in $reports"
