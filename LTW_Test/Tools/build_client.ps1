# Exports the LTW Windows client, stamped with the time and commit it was built at.
#
# Usage lives in building.md. Short version:
#   .\Tools\build_client.ps1            stamp, export, restore
#   .\Tools\build_client.ps1 -Zip       and zip the result for upload
#   .\Tools\build_client.ps1 -Force     build anyway from a dirty tree
#
# The stamp is the whole reason this script exists rather than a bare
# `--export-release`. Resources/Config/build_info.tres is written immediately
# before the export and restored immediately after, so the build carries a date
# and a commit while the committed file stays empty and never shows up in a diff.

param(
    [string]$Godot = "",
    [switch]$Zip,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
# This script lives in Tools/, so the PROJECT is one level up - same as every
# other script in here.
$projectRoot = Split-Path $PSScriptRoot -Parent
$infoPath    = Join-Path $projectRoot "Resources\Config\build_info.tres"
$presetName  = "Windows Desktop"


# **`& $godot` DOES NOT WAIT, and nothing about it looks wrong.** The editor
# binary is a Windows GUI-subsystem executable, so PowerShell starts it and
# carries straight on. The call returns before the export has written a byte,
# `$LASTEXITCODE` is never set from it, and its output goes to the console
# directly rather than down the pipeline where an assignment could catch it.
#
# It cost a build on 2026-09-06, in the worst way: the stamp was written, the
# export "returned" instantly, the stamp was restored while Godot was still
# starting up, and the script then listed the PREVIOUS build's files and called
# it a success. A stale build reported as a fresh one - the same shape of lie
# the pid check in deploy_server.ps1 exists to catch.
#
# Start-Process -Wait waits for a GUI-subsystem process properly, and -PassThru
# is what makes the real exit code readable afterwards.
function Invoke-Godot([string] $Exe, [string[]] $Arguments) {
    # **Start-Process does not quote for you.** An argument holding a space
    # arrives at the program split in two, and both of the ones here hold one:
    # the project path ("LTW Standalone") and the preset name ("Windows
    # Desktop"). The call operator quoted them by itself, so this only showed up
    # once the launch moved to Start-Process - as Godot refusing a project path
    # truncated at the first space.
    $quoted = @()
    foreach ($argument in $Arguments) {
        if ($argument -match '\s') { $quoted += ('"' + $argument + '"') } else { $quoted += $argument }
    }
    $process = Start-Process -FilePath $Exe -ArgumentList $quoted -NoNewWindow -Wait -PassThru
    return $process.ExitCode
}

function Read-Git([string[]] $Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git -C $projectRoot @Arguments 2>$null
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') returned $LASTEXITCODE" }
    return $output
}


# Where Godot is: the -Godot argument, then the GODOT environment variable. Not
# a project setting - it is just where this machine keeps the editor.
$exe = $Godot
if ([string]::IsNullOrWhiteSpace($exe)) { $exe = $env:GODOT }
if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path $exe)) {
    Write-Host "Godot executable not found:" -ForegroundColor Red
    Write-Host "  $exe"
    Write-Host ""
    Write-Host 'Point this script at it:  $env:GODOT = "C:\path\to\Godot.exe"'
    exit 1
}


# A build has to be reproducible from a commit, and it has to match the server -
# which deploys from git and so can never carry an uncommitted change. A stamp
# naming a commit the build does not actually contain is worse than no stamp:
# it makes a bug report point at the wrong code with total confidence.
$dirty = @(Read-Git @("status", "--porcelain", "--untracked-files=no"))
if ($dirty.Count -gt 0 -and -not $Force) {
    Write-Host "The working tree has uncommitted changes:" -ForegroundColor Yellow
    foreach ($line in $dirty) { Write-Host "  $line" }
    Write-Host ""
    Write-Host "A build stamps the commit it was made from, and the server deploys from git."
    Write-Host "Commit and push first, or pass -Force to build an unreproducible one."
    exit 1
}

$commit  = (Read-Git @("rev-parse", "--short", "HEAD")).Trim()
$builtAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm") + " UTC"


# The stamp is INSERTED after the script line rather than substituted into
# existing ones, because the editor drops any property equal to its script
# default when it saves a .tres - so built_at and commit may not be in the file
# at all. Everything else, `stage` included, is carried through untouched.
$original = [System.IO.File]::ReadAllText($infoPath)
$kept = @(Get-Content -Path $infoPath | Where-Object { $_ -notmatch '^(built_at|commit)\s*=' })

$stampedLines = New-Object System.Collections.Generic.List[string]
$inserted = $false
foreach ($line in $kept) {
    $stampedLines.Add($line)
    if (-not $inserted -and $line -match '^script\s*=\s*ExtResource') {
        $stampedLines.Add(('built_at = "{0}"' -f $builtAt))
        $stampedLines.Add(('commit = "{0}"' -f $commit))
        $inserted = $true
    }
}
if (-not $inserted) {
    throw "No 'script = ExtResource(...)' line in $infoPath - a property above it is thrown away."
}

# No BOM: Set-Content and Out-File both write one in PowerShell 5.1, and a .tres
# is read by Godot rather than by PowerShell.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Host "Building $presetName" -ForegroundColor Cyan
Write-Host "  stamp   $builtAt"
Write-Host "  commit  $commit"
Write-Host ""

$startedAt = Get-Date
$exportCode = 1
try {
    [System.IO.File]::WriteAllText($infoPath, ($stampedLines -join "`n") + "`n", $utf8NoBom)
    $exportCode = Invoke-Godot $exe @("--path", $projectRoot, "--headless", "--export-release", $presetName)
} finally {
    # Verbatim, byte for byte, whatever happened above. The working tree must
    # look untouched afterwards or the next `git status` reads as a change
    # somebody made.
    [System.IO.File]::WriteAllText($infoPath, $original, $utf8NoBom)
}

if ($exportCode -ne 0) {
    Write-Host ""
    Write-Host "Export failed (Godot returned $exportCode)." -ForegroundColor Red
    exit 1
}

$outDir = Join-Path (Split-Path $projectRoot -Parent) "Builds\Windows"

# **Assert the EFFECT, not the command.** An exit code says Godot finished, not
# that it wrote anything - and the failure this guards against left a stale
# build sitting in the output folder looking exactly like a new one. A pack
# older than the moment the export started is the tell, and it is checked rather
# than assumed for the same reason the server deploy compares pids.
$pack = Join-Path $outDir "LTW_Test.pck"
if (-not (Test-Path $pack)) {
    Write-Host "No pack at $pack - the export wrote nothing." -ForegroundColor Red
    exit 1
}
if ((Get-Item $pack).LastWriteTime -lt $startedAt) {
    Write-Host "The pack at $pack is OLDER than this build." -ForegroundColor Red
    Write-Host "Godot did not rewrite it, so what is in that folder is a previous build."
    exit 1
}
Write-Host ""
Write-Host "Built to $outDir" -ForegroundColor Green
Get-ChildItem $outDir | ForEach-Object { "  {0,-26} {1,12:N0}" -f $_.Name, $_.Length }

if ($Zip) {
    $zipName = "LineTowerWars-{0}-win64-{1}.zip" -f ($builtAt -replace '[^0-9]', '').Substring(0, 8), $commit
    $zipPath = Join-Path (Split-Path $outDir -Parent) $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $zipItem = Get-Item $zipPath
    Write-Host ""
    Write-Host ("Zipped to {0} ({1:N1} MB)" -f $zipItem.FullName, ($zipItem.Length / 1MB)) -ForegroundColor Green
}
