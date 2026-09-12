# Plays computer opponents against each other and prints what happened.
#
# The question it answers is "is this difficulty actually harder than that one",
# and there is no other way to ask it: a profile is a dozen numbers and what they
# add up to is a match, not a sum.
#
#   .\Tools\run_ai_bench.ps1                          Normal against Normal
#   .\Tools\run_ai_bench.ps1 -A Hard -B Easy          one against the other
#   .\Tools\run_ai_bench.ps1 -Players 4 -Minutes 25   a free for all, to the endgame
#   .\Tools\run_ai_bench.ps1 -Seed 7                  the same match again
#
# Headless and faster than real time: the engine rate is raised for the run and
# put back afterwards, and nothing in the simulation reads it - see
# MatchSession._sim_ticks_per_second. A twenty-five minute match takes about two.

param(
	[string]$A = "Normal",
	[string]$B = "",
	[int]$Players = 2,
	[double]$Minutes = 25,
	[int]$Seed = 0,
	[int]$Speed = 240,
	[string]$Godot = ""
)

$ErrorActionPreference = "Stop"
# This script lives in Tools/, so the PROJECT is one level up.
$projectRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $PSScriptRoot "godot_path.ps1")
$exe = Resolve-GodotExe -Explicit $Godot -ProjectRoot $projectRoot -ScriptName "run_ai_bench.ps1"
if ([string]::IsNullOrWhiteSpace($exe)) { exit 1 }

if ([string]::IsNullOrWhiteSpace($B)) { $B = $A }
if ($Seed -le 0) { $Seed = Get-Random -Minimum 1 -Maximum 2147483647 }

$benchArgs = @(
	"--path", $projectRoot, "--headless",
	"res://Scenes/Tools/ai_bench.tscn", "--",
	"a=$A", "b=$B", "players=$Players", "minutes=$Minutes", "seed=$Seed", "speed=$Speed"
)

# Start-Process rather than the call operator, because the editor binary is a
# GUI-subsystem executable: `& $exe` returns before it has done anything and
# never sets $LASTEXITCODE. build_client.ps1 has the long version of that trap.
#
# **And it does NOT quote for you, where `&` did.** This project's own folder
# holds a space, so an unquoted project path arrives split in two and Godot
# refuses a path truncated at the first one. Same fix as build_client.ps1.
$quoted = @()
foreach ($argument in $benchArgs) {
    if ($argument -match '\s') { $quoted += ('"' + $argument + '"') } else { $quoted += $argument }
}
$run = Start-Process -FilePath $exe -ArgumentList $quoted -NoNewWindow -Wait -PassThru
if ($run.ExitCode -ne 0) {
	Write-Host "The bench exited with $($run.ExitCode)." -ForegroundColor Yellow
	exit $run.ExitCode
}
