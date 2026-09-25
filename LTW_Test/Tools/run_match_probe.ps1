# Runs ONE match-process scenario (D44): a hand-written match file, a real
# MATCH PROCESS started from it, and N probe clients that dial its port with
# their seats' tokens.
#
# This is P2's proof harness. It deliberately has no lobby in it: the lobby side
# is P3, and testing the handoff against a lobby that also has to work would not
# say which half was wrong.
#
#   .\Tools\new_probe_copy.ps1 -Name mp -Root C:\Users\yaand\lp
#   .\Tools\run_match_probe.ps1 -Dir C:\Users\yaand\lp\mp\LTW_Test -Name plain
#   .\Tools\run_match_probe.ps1 -Dir ... -Name reclaim -SeatArgs @(@(),@('--redial-after','6'))
#   python Tools\probe_table.py $env:TEMP\ltw_probe\runs
#
# **The match file is written TWICE**: one for the match process, which deletes
# it the moment it has read it so a token does not sit on disk, and one copy the
# probes read. A probe started afterwards would otherwise find nothing.
#
# A run with no PROBE RESULT line did not run. The positive-control rule in
# CLAUDE.md applies to every result here, and the fields that carry it are
# `claims` (a seat was really claimed) and `go_id` equal to `own_id` (the re-key
# ran). A green line with claims=0 proves nothing at all.

param(
    [Parameter(Mandatory = $true)][string] $Name,
    [Parameter(Mandatory = $true)][string] $Dir,   # a copy made by new_probe_copy.ps1
    [int] $Port = 7810,
    [int] $Seats = 2,
    [int] $Play = 25,
    [object[]] $SeatArgs = @(),                    # extra probe flags, one array per seat
    [switch] $NoProbes,                            # start only the match process
    [switch] $BlockPort,                           # hold the port first, to force PORT_TAKEN
    [switch] $ShutdownAtBoot,                      # the shutdown file exists BEFORE the child listens
    [int] $ShutdownAfter = 0,                      # seconds after READY to ask for a shutdown
    [string] $OutRoot = "",
    [string] $Godot = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "godot_path.ps1")
$godotExe = Resolve-GodotExe -Explicit $Godot -ProjectRoot $projectRoot -ScriptName "run_match_probe.ps1"
if ([string]::IsNullOrWhiteSpace($godotExe)) { exit 1 }

# **The output directory is $outDir, not $dir, and the name is the point.**
# PowerShell variable names are CASE-INSENSITIVE, so a local $dir IS the -Dir
# parameter. Naming the output folder $dir silently overwrote the project path,
# every process was launched with the output folder as its project root, and
# Godot printed its banner and sat there with no error anywhere. It cost a long
# debugging cycle on P2's first run: by hand the same command worked every time.
$probeRoot = Join-Path $env:TEMP "ltw_probe"
if ($OutRoot -eq "") { $OutRoot = Join-Path $probeRoot "runs" }
$outDir = Join-Path $OutRoot $Name
New-Item -ItemType Directory -Force $outDir | Out-Null
$runDir = Join-Path $outDir "run"
New-Item -ItemType Directory -Force $runDir | Out-Null
$appdata = Join-Path $OutRoot "appdata"
New-Item -ItemType Directory -Force $appdata | Out-Null
$env:APPDATA = $appdata

$matchId = "m-$Name"

# The match file, in the exact shape MatchHandoff fixes: format, setup, tokens
# as hex keyed by slot as a STRING, countdown_ends in Unix seconds, lobby_pid.
$players = @()
$tokens = @{}
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
for ($slot = 1; $slot -le $Seats; $slot++) {
    $players += @{
        slot = $slot
        display_name = "Seat$slot"
        network_id = 0
        color_index = $slot
        ai_difficulty = -1
    }
    $bytes = New-Object byte[] 16
    $rng.GetBytes($bytes)
    $tokens["$slot"] = -join ($bytes | ForEach-Object { $_.ToString("x2") })
}
$matchFile = @{
    format = 1
    setup = @{
        mode = 1
        match_id = $matchId
        players = $players
        local_slot = 0
        rng_seed = 20260925
    }
    tokens = $tokens
    countdown_ends = [int][double]::Parse((Get-Date -UFormat %s))
    lobby_pid = $PID
}
$json = $matchFile | ConvertTo-Json -Depth 8 -Compress
# Forward slashes throughout. A Windows path with backslashes reads as MISSING
# to Godot's file access, and the child then exits BAD_MATCH_FILE for a file
# that is plainly sitting there. MatchHandoff normalises too; this keeps the
# logs readable as well.
$forChild = (Join-Path $runDir "$matchId.match") -replace '\\', '/'
$forProbes = (Join-Path $outDir "probes.match") -replace '\\', '/'
$childLog = (Join-Path $outDir "child.godot.log") -replace '\\', '/'
$shutdownFile = (Join-Path $runDir "$matchId.shutdown") -replace '\\', '/'
$resultFile = (Join-Path $runDir "$matchId.result") -replace '\\', '/'
$readyFile = (Join-Path $runDir "$matchId.ready") -replace '\\', '/'
[System.IO.File]::WriteAllText($forChild, $json)
[System.IO.File]::WriteAllText($forProbes, $json)

function Read-Shared([string] $path) {
    if (-not (Test-Path $path)) { return "" }
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try { $raw = (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
        return ($raw -replace "\x1B\[[0-9;]*m", "")
    } catch { return "" }
}
function Launch([string] $label, [string[]] $argv) {
    $o = Join-Path $outDir "$label.out.txt"
    $e = Join-Path $outDir "$label.err.txt"
    Remove-Item $o, $e -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $godotExe -WorkingDirectory $Dir -ArgumentList $argv `
        -RedirectStandardOutput $o -RedirectStandardError $e -PassThru
    # **Touching .Handle is what makes .ExitCode readable later.** A process
    # started with -PassThru and never waited on reads an EMPTY exit code once
    # it has gone, because PowerShell let the handle close; asking for the
    # handle now caches it. The exit code IS the test in several of these
    # scenarios, so an empty one is indistinguishable from a pass.
    $null = $p.Handle
    return @{ proc = $p; out = $o; label = $label }
}

$started = @()
$summary = @("SCENARIO $Name  port=$Port seats=$Seats play=$Play block_port=$BlockPort")
$blocker = $null
try {
    if ($BlockPort) {
        # **A second MATCH PROCESS, not a .NET UdpClient.** A UdpClient does not
        # stop ENet binding the same port at all - the first attempt at this
        # scenario "passed" with the child listening happily on a port the
        # harness believed it held, which is the positive-control trap exactly:
        # the run proved the harness wrong and said nothing. ENet against ENet is
        # the case the lobby will actually meet.
        $blockerFile = (Join-Path $runDir "blocker.match") -replace '\\', '/'
        [System.IO.File]::WriteAllText($blockerFile, $json)
        $blocker = Launch "blocker" @(
            '--path', '.', '--headless', '--',
            '--match-server', '--match-id', $matchId, '--match-file', $blockerFile,
            '--port', "$Port"
        )
        $started += $blocker.proc
        $bw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($bw.Elapsed.TotalSeconds -lt 30 -and -not (Test-Path $readyFile)) {
            Start-Sleep -Milliseconds 200
        }
        $summary += "PORT $Port HELD by a first match process (ready=$(Test-Path $readyFile))"
    }

    $childArgs = @(
        '--path', '.', '--headless',
        '--log-file', $childLog,
        '--',
        '--match-server', '--match-id', $matchId, '--match-file', $forChild,
        '--port', "$Port", '--shutdown-file', $shutdownFile
    )
    if ($ShutdownAtBoot) {
        # A D45 request aimed at a child that is still booting arrives as exactly
        # this: the file already there when the child gets to it. The old
        # `_arm_shutdown_file` deleted it as stale, which swallowed the request
        # and left the match playing on through a deploy.
        New-Item -ItemType File -Force $shutdownFile | Out-Null
        $summary += "SHUTDOWN FILE PLANTED BEFORE THE CHILD STARTED"
    }
    $child = Launch "child" $childArgs
    $started += $child.proc

    if (-not $BlockPort) {
        # READY is the child saying a lobby may announce its port. Waiting for
        # the FILE rather than for a log line is what the lobby will do in P3.
        $w = [System.Diagnostics.Stopwatch]::StartNew()
        while ($w.Elapsed.TotalSeconds -lt 60 -and -not (Test-Path $readyFile)) {
            if ($child.proc.HasExited) { break }
            Start-Sleep -Milliseconds 200
        }
        if (Test-Path $readyFile) {
            $summary += "CHILD READY after $([math]::Round($w.Elapsed.TotalSeconds,1))s"
        } else {
            $summary += "CHILD NEVER WROTE READY"
        }
    }

    $clients = @()
    if (-not $NoProbes -and -not $BlockPort) {
        for ($slot = 1; $slot -le $Seats; $slot++) {
            $extra = @()
            if ($slot - 1 -lt $SeatArgs.Count) { $extra = @($SeatArgs[$slot - 1]) }
            $argv = @(
                '--path', '.', '--headless', '--',
                '--probe', 'match', '--match-port', "$Port", '--match-file', $forProbes,
                '--slot', "$slot", '--address', '127.0.0.1', '--play', "$Play"
            ) + $extra
            $p = Launch "seat$slot" $argv
            $started += $p.proc
            $clients += $p
            Start-Sleep -Milliseconds 400
        }
        $summary += "PROBES LAUNCHED: $($clients.Count) for $Seats seats"
    }

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $asked = $false
    while ($clock.Elapsed.TotalSeconds -lt ($Play + 150)) {
        if ($ShutdownAfter -gt 0 -and -not $asked -and $clock.Elapsed.TotalSeconds -ge $ShutdownAfter) {
            New-Item -ItemType File -Force $shutdownFile | Out-Null
            $asked = $true
            $summary += "SHUTDOWN REQUESTED at t=$([math]::Round($clock.Elapsed.TotalSeconds,1))s"
        }
        if ($child.proc.HasExited -and ($clients.Count -eq 0 -or
            (@($clients | Where-Object { -not $_.proc.HasExited }).Count -eq 0))) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $child.proc.HasExited) {
        # **Asked to stop, not killed**, for two reasons. It is the D45 road, so
        # the scenario exercises it for free - and a killed process never flushes
        # its stdout, so a harness that kills the child gets the banner and
        # nothing else, whatever the child actually did. That cost a debugging
        # cycle on the first P2 run.
        $summary += "ASKING THE CHILD TO SHUT DOWN (D45)"
        New-Item -ItemType File -Force $shutdownFile | Out-Null
        $w2 = [System.Diagnostics.Stopwatch]::StartNew()
        while ($w2.Elapsed.TotalSeconds -lt 30 -and -not $child.proc.HasExited) {
            Start-Sleep -Milliseconds 200
        }
    }
    if ($child.proc.HasExited) {
        # WaitForExit on an already-exited process refreshes the object. Without
        # it .ExitCode reads EMPTY for a process started with -PassThru and never
        # waited on, and the exit code is the whole point of these scenarios.
        $child.proc.WaitForExit()
        $summary += "CHILD EXITED code=$($child.proc.ExitCode) after $([math]::Round($clock.Elapsed.TotalSeconds,1))s"
    } else {
        $summary += "CHILD STILL RUNNING at the end of the scenario"
    }
    Start-Sleep -Seconds 1
} finally {
    foreach ($p in $started) {
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }

}

# What the child left behind. The RESULT stays for the lobby to read; the match
# file must be GONE, because the child deletes it the moment it has read it.
if (Test-Path $resultFile) {
    $summary += "RESULT " + ((Read-Shared $resultFile) -replace "\s+", " ")
} else {
    $summary += "NO RESULT FILE"
}
$summary += "MATCH FILE REMOVED BY CHILD: " + (-not (Test-Path $forChild))

foreach ($label in (@('child') + (1..$Seats | ForEach-Object { "seat$_" }))) {
    # **The child's evidence is read from its --log-file, not from its stdout.**
    # Godot's stdout redirected to a file is fully BUFFERED, so a child that is
    # killed rather than asked to stop flushes nothing and every line below would
    # be silently empty. The log file is written unbuffered.
    $f = Join-Path $outDir "$label.out.txt"
    if ($label -eq 'child' -and (Test-Path $childLog)) { $f = $childLog }
    if (-not (Test-Path $f)) { continue }
    $text = Read-Shared $f
    $keys = 'PROBE RESULT|PROBE DESYNC|SCRIPT ERROR|ERROR:|Match process|Seat claimed|Seat released|' +
            'Client loaded|Client unloaded|Match start|Match result|Match under way|Editor helper|' +
            'Sealed stream|Initial world|PROBE admitted|PROBE move failed|PROBE match cancelled|' +
            'seat|token|oom_score'
    $lines = ($text -split "`n") | Where-Object { $_ -match $keys }
    if ($label -ne 'child' -and (($lines | Where-Object { $_ -match 'PROBE RESULT' }).Count -eq 0)) {
        $summary += "[$label] NO PROBE RESULT LINE"
    }
    foreach ($line in $lines) { $summary += "[$label] $($line.Trim())" }
}
$summary | Set-Content -Encoding utf8 (Join-Path $outDir "summary.txt")
$summary
