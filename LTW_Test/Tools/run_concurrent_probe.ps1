# Runs N match PAIRS AT THE SAME TIME against one lobby server (D44).
#
# This exists because nothing else could express it. `run_lockstep_probe.ps1
# -SecondMatch` plays two matches one AFTER the other - it waits for "Match over"
# before starting the second - so it proves that a lobby can run a second match,
# not that it can run two. Many matches at once is what D44 is FOR, and it was
# the one claim with no evidence behind it.
#
#   .\Tools\new_probe_copy.ps1 -Name p3 -Root C:\Users\yaand\lp
#   .\Tools\run_concurrent_probe.ps1 -Dir C:\Users\yaand\lp\p3\LTW_Test -Name conc -Pairs 3
#
# Each pair makes its OWN lobby (`--lobby pair<n>`), because a join probe
# otherwise takes the first lobby it sees and both pairs end up in one.
#
# What to read in the summary:
#   MATCHES CONCURRENT     the most children the lobby held at once. Below the
#                          pair count, the matches did NOT overlap and the run
#                          proves nothing about concurrency.
#   distinct ports         one per match; a repeat means the pool handed one out
#                          twice.
#   every PROBE RESULT     turns_run > 0 and desyncs 0 on every client.

param(
    [Parameter(Mandatory = $true)][string] $Name,
    [Parameter(Mandatory = $true)][string] $Dir,
    [int] $Port = 7860,
    [int] $Pairs = 2,
    [int] $Play = 30,
    [string] $OutRoot = "",
    [string] $Godot = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "godot_path.ps1")
$godotExe = Resolve-GodotExe -Explicit $Godot -ProjectRoot $projectRoot -ScriptName "run_concurrent_probe.ps1"
if ([string]::IsNullOrWhiteSpace($godotExe)) { exit 1 }

# $outDir, never $dir: PowerShell cannot tell it from the -Dir parameter.
$probeRoot = Join-Path $env:TEMP "ltw_probe"
if ($OutRoot -eq "") { $OutRoot = Join-Path $probeRoot "runs" }
$outDir = Join-Path $OutRoot $Name
New-Item -ItemType Directory -Force $outDir | Out-Null
$appdata = Join-Path $OutRoot "appdata"
New-Item -ItemType Directory -Force $appdata | Out-Null
$env:APPDATA = $appdata

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
    $null = $p.Handle
    return @{ proc = $p; out = $o; label = $label }
}

$started = @()
$summary = @("SCENARIO $Name  port=$Port pairs=$Pairs play=$Play")
try {
    $relayLog = (Join-Path $outDir "relay.godot.log") -replace '\\', '/'
    $relay = Launch "relay" @(
        '--path', '.', '--headless', '--log-file', $relayLog,
        '--', '--server', '--port', "$Port", '--match-processes'
    )
    $started += $relay.proc
    $w = [System.Diagnostics.Stopwatch]::StartNew()
    while ($w.Elapsed.TotalSeconds -lt 60 -and -not (Read-Shared $relay.out).Contains("Listening on port $Port")) {
        Start-Sleep -Milliseconds 200
    }
    $summary += "RELAY UP after $([math]::Round($w.Elapsed.TotalSeconds,1))s"

    $common = @('--path', '.', '--headless', '--', '--port', "$Port",
                '--address', '127.0.0.1', '--play', "$Play")
    $clients = @()
    for ($i = 1; $i -le $Pairs; $i++) {
        $lobby = "pair$i"
        $h = Launch "host$i" ($common + @('--probe', 'host', '--lobby', $lobby))
        $started += $h.proc
        $clients += $h
        Start-Sleep -Milliseconds 900
        $j = Launch "join$i" ($common + @('--probe', 'join', '--lobby', $lobby))
        $started += $j.proc
        $clients += $j
        Start-Sleep -Milliseconds 400
    }
    $summary += "PAIRS LAUNCHED: $Pairs ($($clients.Count) clients)"

    # The peak is what the whole run is for, so it is sampled rather than
    # inferred at the end - by then every match has been reaped and the count is
    # back to zero whether they overlapped or not.
    $peak = 0
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt ($Play + 180)) {
        $live = @(Get-CimInstance Win32_Process -Filter "Name like '%odot%'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*--match-server*" })
        if ($live.Count -gt $peak) { $peak = $live.Count }
        if (@($clients | Where-Object { -not $_.proc.HasExited }).Count -eq 0) { break }
        Start-Sleep -Milliseconds 400
    }
    $summary += "MATCHES CONCURRENT: $peak (of $Pairs pairs)"
    Start-Sleep -Seconds 2
} finally {
    foreach ($p in $started) {
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
}

$relayText = Read-Shared (Join-Path $outDir "relay.godot.log")
if ($relayText -eq "") { $relayText = Read-Shared (Join-Path $outDir "relay.out.txt") }
$ports = @()
foreach ($line in ($relayText -split "`n")) {
    if ($line -match 'Match process spawned.*"port": (\d+)') { $ports += $Matches[1] }
    if ($line -match 'Handing a match over|Match process spawned|Matches running|Match result|server is full') {
        $summary += "[relay] $($line.Trim())"
    }
}
$summary += "PORTS HANDED OUT: $($ports -join ', ')  distinct=$(($ports | Select-Object -Unique).Count) of $($ports.Count)"

for ($i = 1; $i -le $Pairs; $i++) {
    foreach ($label in @("host$i", "join$i")) {
        $text = Read-Shared (Join-Path $outDir "$label.out.txt")
        $res = ($text -split "`n") | Where-Object { $_ -match 'PROBE RESULT|PROBE DESYNC|SCRIPT ERROR' }
        if ($res.Count -eq 0) { $summary += "[$label] NO PROBE RESULT LINE" }
        foreach ($line in $res) { $summary += "[$label] $($line.Trim())" }
    }
}
$summary | Set-Content -Encoding utf8 (Join-Path $outDir "summary.txt")
$summary
