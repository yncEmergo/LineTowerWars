# Makes an ISOLATED COPY of the project for a LockstepProbe run, with the probe
# switched on. See run_lockstep_probe.ps1 for the runs themselves.
#
#   .\Tools\new_probe_copy.ps1 -Name head
#   .\Tools\new_probe_copy.ps1 -Name fix -Files Scripts/Multiplayer/MatchStartService.gd
#
# Why a copy rather than the working tree:
# - LockstepProbe is an autoload only through an override.cfg, and an override.cfg
#   in the real project would also be read by the editor the next time it starts.
# - Another session's half-finished edits in the shared working tree stop every
#   headless run from compiling. A copy of HEAD plus only the files under test
#   does not care.
# - A pure HEAD copy also stands in for a tester's build ("the old build").
#
# What it does NOT isolate you from: the other session's COMMITS. It archives
# HEAD, and concurrent sessions here share one working tree and one .git - so a
# copy is always current HEAD plus the files you name, and there is no way to ask
# it for an earlier commit. That is the right shape while your own edits are
# uncommitted; it is worth knowing because a verification run before somebody
# else's commit has tested code that is no longer HEAD.
#
# What it does: git archive of HEAD, the -Files overlaid from the working tree, a
# copy of .godot (so the import is quick), the override.cfg, then a headless
# --import. It refuses a name that already exists rather than deleting anything.

param(
    [Parameter(Mandatory = $true)][string] $Name,
    [string[]] $Files = @(),
    [string] $Root = "",
    [string] $Godot = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $projectRoot -Parent
$projectFolder = Split-Path $projectRoot -Leaf

. (Join-Path $PSScriptRoot "godot_path.ps1")
$exe = Resolve-GodotExe -Explicit $Godot -ProjectRoot $projectRoot -ScriptName "new_probe_copy.ps1"
if ([string]::IsNullOrWhiteSpace($exe)) { exit 1 }

if ($Root -eq "") { $Root = Join-Path $env:TEMP "ltw_probe" }
$dest = Join-Path $Root $Name
if (Test-Path $dest) {
    Write-Host "$dest already exists. Pick another -Name, or delete it yourself." -ForegroundColor Red
    exit 1
}
New-Item -ItemType Directory -Force $dest | Out-Null

# A native command's stderr is a terminating error under "Stop" (CLAUDE.md), so
# git runs under Continue and is judged by its exit code instead.
$zip = Join-Path $dest "head.zip"
$ErrorActionPreference = "Continue"
& git -C $repoRoot archive --format=zip -o $zip HEAD $projectFolder 2>$null
$gitExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($gitExit -ne 0 -or -not (Test-Path $zip)) { throw "git archive failed ($gitExit)" }
Expand-Archive -Path $zip -DestinationPath $dest
Remove-Item $zip
$copy = Join-Path $dest $projectFolder

foreach ($file in $Files) {
    $from = Join-Path $projectRoot $file
    if (-not (Test-Path $from)) { throw "No such file in the working tree: $file" }
    $to = Join-Path $copy $file
    New-Item -ItemType Directory -Force (Split-Path $to -Parent) | Out-Null
    Copy-Item -Force $from $to
    Write-Host "  overlaid $file"
}

$dotGodot = Join-Path $projectRoot ".godot"
if (Test-Path $dotGodot) { Copy-Item -Recurse $dotGodot (Join-Path $copy ".godot") }

Set-Content -Encoding ascii -Path (Join-Path $copy "override.cfg") -Value @(
    "[autoload]",
    "",
    'LockstepProbe="*res://Scripts/Dev/LockstepProbe.gd"'
)

# --path . with the copy as the working directory: Start-Process does not quote
# arguments, and the temp path holds a space on this machine.
$log = Join-Path $dest "import.log"
$import = Start-Process -FilePath $exe -WorkingDirectory $copy `
    -ArgumentList @('--path', '.', '--headless', '--import') `
    -RedirectStandardOutput $log -RedirectStandardError (Join-Path $dest "import.err.log") `
    -NoNewWindow -Wait -PassThru

# Assert the effect, not the command (CLAUDE.md): the class cache must exist.
$cache = Join-Path $copy ".godot\global_script_class_cache.cfg"
if (-not (Test-Path $cache)) { throw "The import left no class cache; see $log" }
Write-Host "Probe copy ready (import exit $($import.ExitCode)): $copy" -ForegroundColor Green
Write-Host "Run it: .\Tools\run_lockstep_probe.ps1 -Copy $Name -Name <scenario>"
