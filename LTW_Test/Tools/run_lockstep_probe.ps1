# Runs ONE LockstepProbe scenario on loopback: a headless relay, two probe clients
# (host and join), and optionally a third peer that connects mid-match. It stops
# only the processes it started.
#
# Make the copy first (new_probe_copy.ps1), then for example:
#   .\Tools\run_lockstep_probe.ps1 -Copy head -Name plain
#   .\Tools\run_lockstep_probe.ps1 -Copy head -Name kill -KillJoinAfter 10
#   .\Tools\run_lockstep_probe.ps1 -Copy head -Name third -Third browse
#   .\Tools\run_lockstep_probe.ps1 -Copy head -Name drain -ShutdownAfter 8
#   .\Tools\run_lockstep_probe.ps1 -Copy fix -Name old-server -ServerDir <an older copy>
#   python Tools\probe_table.py $env:TEMP\ltw_probe\runs
#
# Probe flags for one side go through -HostArgs / -JoinArgs, e.g.
# -JoinArgs '--hitch','900'. LockstepProbe.gd lists them all.
#
# Each run writes <OutRoot>\<Name>\summary.txt: every PROBE RESULT line, and the
# relay lines that say what happened. A scenario with NO PROBE RESULT line did not
# run; that is a failed run, not a pass (CLAUDE.md, the positive control).
# user:// of every process is redirected under OutRoot, so nothing touches the
# real APPDATA.

param(
    [Parameter(Mandatory = $true)][string] $Name,
    [string] $Copy = "",             # a copy made by new_probe_copy.ps1, used for both sides
    [string] $ServerDir = "",        # or name the relay's project folder directly...
    [string] $ClientDir = "",        # ...and the clients' (an old build, a new build)
    [int] $Port = 7790,
    [int] $Play = 30,
    [string[]] $HostArgs = @(),
    [string[]] $JoinArgs = @(),
    [string] $Third = "",            # "browse" or "spoof": a third peer, connected mid-match
    [int] $ThirdDelay = 22,          # seconds after the join client starts
    [int] $KillJoinAfter = 0,        # seconds after the join client says "PROBE playing"; 0 = never
    [int] $ShutdownAfter = 0,        # seconds after "PROBE playing" to ask the relay to shut down
    [switch] $SecondMatch,           # after the first match ends, play a second on the SAME relay
    [int] $KillRelayAfter = 0,       # seconds after "PROBE playing" to hard-kill the RELAY
    [int] $RelayQuitAfter = 0,       # engine --quit-after frames: the relay quits with no notice
    [string] $OutRoot = "",
    [string] $Godot = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$projectFolder = Split-Path $projectRoot -Leaf
. (Join-Path $PSScriptRoot "godot_path.ps1")
$godotExe = Resolve-GodotExe -Explicit $Godot -ProjectRoot $projectRoot -ScriptName "run_lockstep_probe.ps1"
if ([string]::IsNullOrWhiteSpace($godotExe)) { exit 1 }

$probeRoot = Join-Path $env:TEMP "ltw_probe"
if ($Copy -ne "") {
    $copyDir = Join-Path (Join-Path $probeRoot $Copy) $projectFolder
    if ($ServerDir -eq "") { $ServerDir = $copyDir }
    if ($ClientDir -eq "") { $ClientDir = $copyDir }
}
if ($ServerDir -eq "" -or $ClientDir -eq "") { throw "Give -Copy, or both -ServerDir and -ClientDir." }
# Without the override the probe is not loaded, every client idles, and the run
# reads as a hang rather than as "the probe never started".
if (-not (Test-Path (Join-Path $ClientDir "override.cfg"))) {
    throw "$ClientDir has no override.cfg, so LockstepProbe would not load. Use new_probe_copy.ps1."
}

if ($OutRoot -eq "") { $OutRoot = Join-Path $probeRoot "runs" }
$dir = Join-Path $OutRoot $Name
New-Item -ItemType Directory -Force $dir | Out-Null
$appdata = Join-Path $OutRoot "appdata"
New-Item -ItemType Directory -Force $appdata | Out-Null
$env:APPDATA = $appdata

# The log files are still open while this reads them.
function Read-Shared([string] $path) {
    if (-not (Test-Path $path)) { return "" }
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try { $raw = (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
        return ($raw -replace "\x1B\[[0-9;]*m", "")
    } catch { return "" }
}
# --path . with the folder as the working directory: Start-Process does not quote.
function Launch([string] $label, [string] $workDir, [string[]] $argv) {
    $o = Join-Path $dir "$label.out.txt"
    $e = Join-Path $dir "$label.err.txt"
    Remove-Item $o, $e -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $godotExe -WorkingDirectory $workDir -ArgumentList $argv `
        -RedirectStandardOutput $o -RedirectStandardError $e -PassThru
    return @{ proc = $p; out = $o; label = $label }
}
function WaitFor([string] $file, [string] $needle, [int] $ms) {
    $w = [System.Diagnostics.Stopwatch]::StartNew()
    while ($w.ElapsedMilliseconds -lt $ms) {
        if ((Read-Shared $file).Contains($needle)) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

$started = @()
$summary = @("SCENARIO $Name  port=$Port play=$Play host=[$($HostArgs -join ' ')] join=[$($JoinArgs -join ' ')] third=$Third kill_join_after=$KillJoinAfter")
try {
    $flag = Join-Path $dir "shutdown.flag"
    Remove-Item $flag -ErrorAction SilentlyContinue
    $relayArgs = @('--path', '.', '--headless')
    if ($RelayQuitAfter -gt 0) { $relayArgs += @('--quit-after', "$RelayQuitAfter") }
    $relayArgs += @('--', '--server', '--port', "$Port")
    if ($ShutdownAfter -gt 0) { $relayArgs += @('--shutdown-file', $flag) }
    $relay = Launch "relay" $ServerDir $relayArgs
    $started += $relay.proc
    if (-not (WaitFor $relay.out "Listening on port $Port" 60000)) { throw "relay never listened" }

    $common = @('--path', '.', '--headless', '--', '--port', "$Port", '--address', '127.0.0.1', '--play', "$Play")
    $hostP = Launch "host" $ClientDir ($common + @('--probe', 'host') + $HostArgs)
    $started += $hostP.proc
    Start-Sleep -Milliseconds 1500
    $joinP = Launch "join" $ClientDir ($common + @('--probe', 'join') + $JoinArgs)
    $started += $joinP.proc
    $clients = @($hostP, $joinP)

    $thirdLaunched = $false
    $killed = $false
    $asked = $false
    $relayGoneAt = -1
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $playingAt = -1
    while ($clock.Elapsed.TotalSeconds -lt ($Play + 150)) {
        if (($ShutdownAfter -gt 0 -or $KillJoinAfter -gt 0 -or $KillRelayAfter -gt 0) -and $playingAt -lt 0 `
                -and (Read-Shared $joinP.out).Contains("PROBE playing")) {
            $playingAt = $clock.Elapsed.TotalSeconds
        }
        if ($KillRelayAfter -gt 0 -and -not $relay.proc.HasExited -and $playingAt -ge 0 `
                -and $clock.Elapsed.TotalSeconds -ge $playingAt + $KillRelayAfter) {
            Stop-Process -Id $relay.proc.Id -Force
            $summary += "HARD-KILLED THE RELAY at t=$([math]::Round($clock.Elapsed.TotalSeconds,1))s"
        }
        if ($RelayQuitAfter -gt 0 -and $relayGoneAt -lt 0 -and $relay.proc.HasExited) {
            $relayGoneAt = $clock.Elapsed.TotalSeconds
            $summary += "RELAY QUIT CLEANLY (no notice) at t=$([math]::Round($relayGoneAt,1))s"
        }
        if ($ShutdownAfter -gt 0 -and -not $asked -and $playingAt -ge 0 `
                -and $clock.Elapsed.TotalSeconds -ge $playingAt + $ShutdownAfter) {
            New-Item -ItemType File $flag | Out-Null
            $asked = $true
            $askedAt = $clock.Elapsed.TotalSeconds
            $summary += "SHUTDOWN REQUESTED at t=$([math]::Round($askedAt,1))s"
        }
        if ($asked -and $relayGoneAt -lt 0 -and $relay.proc.HasExited) {
            $relayGoneAt = $clock.Elapsed.TotalSeconds
            $summary += "RELAY EXITED BY ITSELF $([math]::Round($relayGoneAt - $askedAt,1))s after the request, code=$($relay.proc.ExitCode)"
        }
        if ($Third -ne "" -and -not $thirdLaunched -and $clock.Elapsed.TotalSeconds -ge $ThirdDelay) {
            $thirdP = Launch $Third $ClientDir ($common + @('--probe', $Third))
            $started += $thirdP.proc
            $clients += $thirdP
            $thirdLaunched = $true
        }
        if ($KillJoinAfter -gt 0 -and -not $killed) {
            if ($playingAt -ge 0 -and $clock.Elapsed.TotalSeconds -ge $playingAt + $KillJoinAfter) {
                Stop-Process -Id $joinP.proc.Id -Force
                $killed = $true
                $summary += "HARD-KILLED join at t=$([math]::Round($clock.Elapsed.TotalSeconds,1))s"
            }
        }
        $alive = @($clients | Where-Object { -not $_.proc.HasExited })
        if ($alive.Count -eq 0 -and ($Third -eq "" -or $thirdLaunched)) { break }
        Start-Sleep -Milliseconds 250
    }
    if ($SecondMatch) {
        # The first match only ends once its players' grace has run out.
        if (-not (WaitFor $relay.out "Match over" 45000)) { $summary += "FIRST MATCH NEVER ENDED" }
        $host2 = Launch "host2" $ClientDir ($common + @('--probe', 'host'))
        $started += $host2.proc
        Start-Sleep -Milliseconds 1500
        $join2 = Launch "join2" $ClientDir ($common + @('--probe', 'join'))
        $started += $join2.proc
        $w = [System.Diagnostics.Stopwatch]::StartNew()
        while ($w.Elapsed.TotalSeconds -lt ($Play + 120) -and -not ($host2.proc.HasExited -and $join2.proc.HasExited)) {
            Start-Sleep -Milliseconds 250
        }
    }
    Start-Sleep -Seconds 2
} finally {
    foreach ($p in $started) {
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
}

# Results: every PROBE RESULT line, and the relay lines that say what happened.
foreach ($label in @('host', 'join', 'browse', 'spoof', 'host2', 'join2')) {
    $f = Join-Path $dir "$label.out.txt"
    if (-not (Test-Path $f)) { continue }
    $text = Read-Shared $f
    $res = ($text -split "`n") | Where-Object { $_ -match 'PROBE RESULT|PROBE DESYNC|PROBE saw a player dropped|SCRIPT ERROR|Match cancelled|Lost connection|Lost the server|Back in the lobby browser' }
    if ($res.Count -eq 0) { $summary += "[$label] NO PROBE RESULT LINE" }
    foreach ($line in $res) { $summary += "[$label] $($line.Trim())" }
}
$relayText = Read-Shared (Join-Path $dir "relay.out.txt")
$keys = 'Initial world|Sealed stream opened|Player dropped|Relay match summary|diverged|disagree|gone silent|went quiet|refused|Refusing|SCRIPT ERROR|ERROR:|Match over|Back from a match|Match start|Relay match ready|Shut|shutdown|Editor helper'
foreach ($line in ($relayText -split "`n")) {
    if ($line -match $keys) { $summary += "[relay] $($line.Trim())" }
}
$summary | Set-Content -Encoding utf8 (Join-Path $dir "summary.txt")
$summary
