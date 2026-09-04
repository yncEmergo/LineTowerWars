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

.EXAMPLE
    .\Tools\deploy_server.ps1
    .\Tools\deploy_server.ps1 -Check
    .\Tools\deploy_server.ps1 -Log
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [switch] $Log,
    [switch] $Restart,
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

# ---- follow the log ------------------------------------------------------------------
if ($Log) {
    Write-Host "Following the server log. Ctrl+C stops watching, not the server." `
        -ForegroundColor Cyan
    & ssh -i $Key -o StrictHostKeyChecking=accept-new "root@$Server" `
        "journalctl -u ltw-server -f -n 40 --no-pager"
    exit 0
}

# ---- restart only --------------------------------------------------------------------
if ($Restart) {
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

if ($remoteHead -eq $originHead) {
    Write-Host "Server is already on origin's HEAD. Restarting it anyway to pick up nothing." `
        -ForegroundColor DarkGray
}

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
