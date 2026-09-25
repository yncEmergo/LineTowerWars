<#
.SYNOPSIS
    Ships the pushed HEAD of this repo to the public dedicated server and restarts it.

.DESCRIPTION
    The public server runs the project from a git checkout, so a deploy is a pull and a
    service restart - no build and no export. It ships what is ON THE REMOTE BRANCH, not
    what is in your working tree, so push first. -Check refuses to deploy when the two
    disagree.

    Server controls are documented in Docs/server.md. This script is the public server's
    half of run_server.ps1 / stop_server.ps1.

.PARAMETER Check
    Report what the server is running and whether it matches origin, then exit. Changes
    nothing.

.PARAMETER Log
    Follow the live server log instead of deploying. Ctrl+C to stop watching; the server
    keeps running.

.PARAMETER Restart
    Restart the service without pulling. For picking up a config change made by hand.

.PARAMETER Facts
    Read how the box is set up - the service file and the settings systemd applies to it,
    the firewall, the machine, the commit it runs, recent match summaries - and save it all
    to a file in TEMP. Reads only; changes nothing and disturbs no match.

.PARAMETER InstallShutdown
    Once, right AFTER the deploy that brings the code which understands it: adds the clean
    shutdown to the service (D45), so every later stop, restart and deploy cancels running
    matches and tells the players instead of freezing them. Stops the server while it does
    so - run it when nobody is playing. See Docs/server.md.

.EXAMPLE
    .\Tools\deploy_server.ps1
    .\Tools\deploy_server.ps1 -Check
    .\Tools\deploy_server.ps1 -Log
    .\Tools\deploy_server.ps1 -Facts
    .\Tools\deploy_server.ps1 -InstallShutdown
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [switch] $Log,
    [switch] $Restart,
    [switch] $Facts,
    [switch] $InstallShutdown,
    [string] $Server = "167.233.153.19",
    [string] $Key    = "$env:USERPROFILE\.ssh\ltw_server_ed25519",
    [string] $Path   = "/srv/ltw"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Key)) {
    Write-Host "No SSH key at $Key." -ForegroundColor Red
    Write-Host "That key is what authorises this machine against the server. Generate one with" `
        -ForegroundColor Yellow
    Write-Host "  ssh-keygen -t ed25519 -f `"$Key`" -N `"`"" -ForegroundColor Yellow
    Write-Host "then add its .pub half in the Hetzner console and rebuild the server, or append" `
        -ForegroundColor Yellow
    Write-Host "it to /root/.ssh/authorized_keys from a machine that already has access." `
        -ForegroundColor Yellow
    exit 1
}

# **`$ErrorActionPreference` is dropped to Continue around ssh ON PURPOSE, and it
# is a bug fix rather than sloppiness.** Windows PowerShell 5.1 wraps every line a
# native executable writes to stderr in an ErrorRecord, and with the preference
# set to Stop that record is TERMINATING - so one perfectly ordinary line of git
# progress ("From https://github.com/...") aborts the script mid-deploy.
#
# It cost a real deploy on 2026-09-04. `git fetch` and `git reset` had already run
# on the server, so the tree was on the new commit and this script cheerfully
# reported it, while `systemctl restart` never executed and the server went on
# running an hour-old build. The next client to connect was refused for being on
# "different code" - against a server that had, by every message this script
# printed, just been updated.
#
# The exit code is the honest signal and is still checked. stderr is not.
function Invoke-Server([string] $Command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & ssh -i $Key -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new "root@$Server" $Command
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) { throw "ssh returned $LASTEXITCODE" }
}

# ---- matches, and whether a stop is clean ----------------------------------------------

# How many matches the running server has open, read from its journal: a match is open from
# its "Relay match ready" line until its summary, or until it is over or abandoned, and a
# "Listening on port" line is a new process that has none. A count to print, never a gate:
# D45 says a deploy cancels running matches, it does not refuse.
function Get-OpenMatches {
    $read = "journalctl -u ltw-server --no-pager -o cat -n 5000 | " +
        "grep -E 'Listening on port|Relay match ready|Relay match summary|Match over|Match abandoned' | " +
        "sed -r 's/\x1B\[[0-9;]*[mK]//g'"
    $open = @{}
    foreach ($line in @(Invoke-Server $read)) {
        if ($line -match 'Listening on port') { $open = @{}; continue }
        $id = ""
        if ($line -match '"match": ([^,\s}]+)') { $id = $Matches[1] }
        elseif ($line -match 'everybody has left (\S+)') { $id = $Matches[1] }
        if ($id -eq "") { continue }
        if ($line -match 'Relay match ready') { $open[$id] = $true } else { $open.Remove($id) }
    }
    return $open.Count
}

# Whether the service stops through the clean shutdown (-InstallShutdown), so a restart tells
# the players rather than killing the relay mid-sentence.
function Test-CleanShutdown {
    $stop = (Invoke-Server "systemctl show -p ExecStop --value ltw-server") -join " "
    return $stop -match "shutdown"
}

# Says what a restart is about to do to whoever is playing. Informs, never refuses.
function Write-RestartWarning {
    $open = Get-OpenMatches
    if ($open -eq 0) { return }
    if (Test-CleanShutdown) {
        Write-Host "$open match(es) running. This restart cancels them and tells the players (D45)." `
            -ForegroundColor Yellow
        return
    }
    Write-Host "$open match(es) running, and the clean shutdown is NOT installed:" -ForegroundColor Red
    Write-Host "this restart FREEZES them for good. Wait for them to finish, or see -InstallShutdown." `
        -ForegroundColor Red
}

# ---- read how the box is set up --------------------------------------------------------
# Every command here only READS. The service file is not in the repo - it was written on
# the box once - so this is the only way to know what systemd does when it stops the
# server, and what it would do to a second process started beside it.
if ($Facts) {
    $out = Join-Path $env:TEMP "ltw_server_facts.txt"
    $read = @(
        "exec 2>&1"
        "echo '=== service file'", "systemctl cat ltw-server"
        "echo '=== settings systemd applies'"
        "systemctl show ltw-server -p User -p WorkingDirectory -p ExecStart -p ExecStop -p Restart -p KillMode -p OOMPolicy -p TimeoutStopUSec -p MemoryMax"
        "echo '=== commit it runs'", "git -C $Path rev-parse --short HEAD"
        "echo '=== versions'", "systemctl --version | head -1", "head -2 /etc/os-release", "/opt/godot/godot --version"
        "echo '=== firewall on the box (ufw)'", "ufw status verbose"
        "echo '=== UDP ports in use'", "ss -ulpn"
        "echo '=== machine'", "nproc", "free -m"
        "echo '=== match summaries and boots, last 30 days'"
        "journalctl -u ltw-server --no-pager --since '-30 days' | grep -E 'Relay match summary|Listening on port' | sed -r 's/\x1B\[[0-9;]*[mK]//g' | tail -n 40"
    ) -join "; "

    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & ssh -i $Key -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new "root@$Server" $read |
            Out-File -Encoding utf8 $out
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ssh returned $LASTEXITCODE - nothing was read. The lines above say why." `
            -ForegroundColor Red
        exit 1
    }
    Write-Host "Read the server's setup. Saved to $out" -ForegroundColor Green
    exit 0
}

# ---- follow the log ------------------------------------------------------------------
if ($Log) {
    Write-Host "Following the server log. Ctrl+C stops watching, not the server." `
        -ForegroundColor Cyan
    & ssh -i $Key -o StrictHostKeyChecking=accept-new "root@$Server" `
        "journalctl -u ltw-server -f -n 40 --no-pager"
    exit 0
}

# ---- install the clean shutdown (D45), once -------------------------------------------
# A systemd DROP-IN rather than an edit of the unit: the unit stays exactly as it was
# written, and undoing this is deleting one file. It gives the service a runtime directory
# for the shutdown file, starts the server watching that file, and makes every stop create
# it and wait for the process to leave on its own - which it does after cancelling every
# match with a reason (Net.begin_shutdown). Godot on Linux runs no code on SIGTERM, so
# without this every stop killed the relay mid-sentence and froze every running match.
#
# The server is STOPPED first, under the old settings, on purpose: the process running now
# was started without the shutdown file, so a stop through the new ExecStop would wait the
# full timeout for a file it never looks at.
if ($InstallShutdown) {
    Write-RestartWarning
    $dropIn = @'
# Written by Tools/deploy_server.ps1 -InstallShutdown - see Docs/server.md.
# Undo: delete this file, then: systemctl daemon-reload && systemctl restart ltw-server
[Service]
RuntimeDirectory=ltw-server
ExecStart=
ExecStart=/opt/godot/godot --path {PROJECT} --headless -- --server --shutdown-file /run/ltw-server/shutdown
ExecStop=/bin/sh -c 'touch /run/ltw-server/shutdown; while kill -0 $$MAINPID 2>/dev/null; do sleep 0.5; done'
TimeoutStopSec=30
'@.Replace("{PROJECT}", "$Path/LTW_Test")
    $install = @'
set -e
systemctl stop ltw-server
mkdir -p /etc/systemd/system/ltw-server.service.d
cat > /etc/systemd/system/ltw-server.service.d/clean-shutdown.conf <<'UNIT'
{DROPIN}
UNIT
systemctl daemon-reload
systemctl start ltw-server
'@.Replace("{DROPIN}", $dropIn)
    Invoke-Server $install

    # **Assert the effect, not the command.** The drop-in being written proves nothing; the
    # server's own boot line naming the shutdown file proves the new flag reached a process
    # that understands it. It only appears once that process has booted, so it is waited for.
    $armed = $false
    for ($i = 0; $i -lt 20 -and -not $armed; $i++) {
        Start-Sleep -Seconds 2
        $boot = (Invoke-Server ("journalctl -u ltw-server --no-pager -o cat -n 60 | " +
            "grep -c 'clean shutdown can be asked for' || true")) -join ""
        $armed = [int]$boot.Trim() -gt 0
    }
    if (-not $armed) {
        Write-Host "The drop-in is written, but the server never said it is watching the file." `
            -ForegroundColor Red
        Write-Host "Most likely the server is still on code from before the clean shutdown -" `
            -ForegroundColor Red
        Write-Host "deploy first, then run -InstallShutdown again. Its log: -Log" -ForegroundColor Red
        exit 1
    }
    Write-Host "Clean shutdown installed: stops and restarts now cancel matches and tell the players." `
        -ForegroundColor Green
    exit 0
}

# ---- restart only --------------------------------------------------------------------
if ($Restart) {
    Write-RestartWarning
    $before = (Invoke-Server "systemctl show -p MainPID --value ltw-server").Trim()
    Invoke-Server "systemctl restart ltw-server"
    $after = (Invoke-Server "systemctl show -p MainPID --value ltw-server").Trim()
    if ($after -eq $before -or $after -eq "0") {
        Write-Host "THE SERVICE DID NOT RESTART - still pid $before." -ForegroundColor Red
        exit 1
    }
    Write-Host "Restarted: pid $before -> $after." -ForegroundColor Green
    Invoke-Server "systemctl is-active ltw-server"
    exit 0
}

# ---- what is it running, and does that match origin? ---------------------------------
$remoteHead = (Invoke-Server "git -C $Path rev-parse HEAD").Trim()

& git fetch origin --quiet
$originHead = (& git rev-parse origin/HEAD 2>$null)
if (-not $originHead) { $originHead = (& git rev-parse origin/main) }
$originHead = $originHead.Trim()

$localHead = (& git rev-parse HEAD).Trim()

# Tracked modifications are the ones that matter: they are code the client runs and the
# server cannot have. Untracked files are almost always build junk - a warning that fires
# on those is a warning nobody reads by the third time.
$modified  = @(& git status --porcelain --untracked-files=no)
$untracked = @(& git status --porcelain | Where-Object { $_ -match '^\?\?' })

$localNote = if ($modified.Count)  { "+ $($modified.Count) modified" }
             elseif ($untracked.Count) { "clean ($($untracked.Count) untracked)" }
             else { "clean" }

Write-Host ""
Write-Host "server  $($remoteHead.Substring(0,8))  $(if ($remoteHead -eq $originHead) { '(current)' } else { '(behind)' })"
Write-Host "origin  $($originHead.Substring(0,8))"
Write-Host "local   $($localHead.Substring(0,8))  $localNote"
Write-Host ""

if ($localHead -ne $originHead) {
    Write-Host "Your local commit is not the one on origin - push before deploying, or the" `
        -ForegroundColor Yellow
    Write-Host "server will run something other than what you are testing." -ForegroundColor Yellow
}
if ($modified.Count) {
    Write-Host "You have tracked changes that are not committed. They CANNOT reach the server," `
        -ForegroundColor Yellow
    Write-Host "which deploys from git. A client running them against a server without them may" `
        -ForegroundColor Yellow
    Write-Host "well report 'Initial world DIFFERS from the server' - that is the mismatch," `
        -ForegroundColor Yellow
    Write-Host "not a bug. The files:" -ForegroundColor Yellow
    $modified | Select-Object -First 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    if ($modified.Count -gt 8) {
        Write-Host "  ... and $($modified.Count - 8) more" -ForegroundColor Yellow
    }
}

if ($Check) { exit 0 }

# **A restart that changes nothing is no longer free**: it cancels every running match
# (D45). So a deploy with nothing to deploy stops here, and -Restart is there for the day a
# restart is really wanted.
if ($remoteHead -eq $originHead) {
    Write-Host "Server is already on origin's HEAD - nothing to deploy, so no restart." `
        -ForegroundColor DarkGray
    Write-Host "To restart it anyway: .\Tools\deploy_server.ps1 -Restart" -ForegroundColor DarkGray
    exit 0
}
Write-RestartWarning

# ---- deploy --------------------------------------------------------------------------
Write-Host "Deploying..." -ForegroundColor Cyan

# Which process is serving right now, so the restart below can be PROVEN rather
# than assumed. See the check after it.
$oldPid = (Invoke-Server "systemctl show -p MainPID --value ltw-server").Trim()

# Reset rather than pull: the checkout is a deploy target, never edited by hand, so the
# remote branch always wins. A pull would stop on a conflict nobody is there to resolve.
Invoke-Server @"
set -e
git -C $Path fetch --depth 1 origin main --quiet
git -C $Path reset --hard origin/main --quiet
chown -R ltw:ltw $Path
/opt/godot/godot --headless --path $Path/LTW_Test --import >/dev/null 2>&1 || true
systemctl restart ltw-server
"@

$newHead = (Invoke-Server "git -C $Path rev-parse HEAD").Trim()
Write-Host "Server now on $($newHead.Substring(0,8))." -ForegroundColor Green

# **The tree being on the new commit does NOT mean the new commit is RUNNING**, and
# conflating the two is exactly how an hour-old build kept serving while this
# script said everything was fine. A restart gives the service a new pid; if the
# pid has not moved, the restart did not happen, whatever else succeeded.
$newPid = (Invoke-Server "systemctl show -p MainPID --value ltw-server").Trim()
if ($newPid -eq $oldPid -or $newPid -eq "0") {
    Write-Host ""
    Write-Host "THE SERVICE DID NOT RESTART. It is still pid $oldPid, running the OLD build." `
        -ForegroundColor Red
    Write-Host "The files on the server are updated; the process serving them is not." `
        -ForegroundColor Red
    Write-Host "Clients will be refused for being on 'different code'. Retry with:" `
        -ForegroundColor Red
    Write-Host "  .\Tools\deploy_server.ps1 -Restart" -ForegroundColor Yellow
    exit 1
}
Write-Host "Restarted: pid $oldPid -> $newPid." -ForegroundColor Green

Invoke-Server "systemctl is-active ltw-server"
Write-Host ""
Write-Host "Recent log:" -ForegroundColor Cyan
Invoke-Server "journalctl -u ltw-server -n 12 --no-pager | sed -r 's/\x1B\[[0-9;]*[mK]//g'"
