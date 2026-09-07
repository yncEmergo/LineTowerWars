# Works out where the Godot editor is ON THIS MACHINE. Dot-sourced by
# build_client.ps1, run_server.ps1 and run_bench.ps1, which each ask for it the
# same way:
#
#   . (Join-Path $PSScriptRoot "godot_path.ps1")
#   $exe = Resolve-GodotExe -Explicit $Godot -ProjectRoot $projectRoot -ScriptName "build_client.ps1"
#   if ([string]::IsNullOrWhiteSpace($exe)) { exit 1 }
#
# WHY THIS EXISTS: the project is developed on more than one PC, and where the
# editor lives is the one thing that genuinely differs between them - a
# per-machine detail rather than a project setting, so it cannot simply be
# committed. The three scripts each carried their own guess at it and the
# guesses had already drifted apart: two fell back to a hard-coded
# "Desktop\Godot 4.7.1.exe" and the third fell back to nothing at all, so the
# same machine could run a server and be unable to build. Finding it is now
# written once.
#
# The order is: what the caller passed, then $env:GODOT, then the path
# remembered from a previous run, then a look in the usual places. Anything a
# person names explicitly wins over anything this file works out.

$GodotPathToolsDir = $PSScriptRoot


# The version the PROJECT is on, read from project.godot rather than written
# here - so bumping the engine moves this with it and nothing has to be
# remembered. Major.minor only: a build has to be made with the engine the
# project declares, but any patch of it will do.
function Get-RequiredGodotVersion([string] $ProjectRoot) {
    $projectFile = Join-Path $ProjectRoot "project.godot"
    if (-not (Test-Path -LiteralPath $projectFile)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $projectFile)) {
        if ($line -match '^config/features\s*=.*?"(\d+)\.(\d+)"') {
            return [pscustomobject]@{ Major = [int]$Matches[1]; Minor = [int]$Matches[2]; Patch = -1 }
        }
    }
    return $null
}


# The version of one executable, taken from its FILE NAME. Godot's own download
# is "Godot_v4.7.1-stable_win64.exe", and a renamed one normally keeps the
# number - both machines here have a hand-renamed "Godot 4.7.1.exe". Asking the
# binary itself with --version would be exact, but it is a GUI-subsystem
# executable whose output cannot be captured reliably (the long version of that
# trap is in build_client.ps1), so the name is what there is. A name carrying no
# number is not a candidate at all, which is what keeps some unrelated
# godot_*.exe in Downloads out of the running.
function Get-GodotExeVersion([string] $Path) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($name -match '(\d+)\.(\d+)(?:\.(\d+))?') {
        $patch = 0
        if ($Matches[3]) { $patch = [int]$Matches[3] }
        return [pscustomobject]@{ Major = [int]$Matches[1]; Minor = [int]$Matches[2]; Patch = $patch }
    }
    return $null
}

function Format-GodotVersion($Version) {
    if ($null -eq $Version) { return "?" }
    if ($Version.Patch -lt 0) { return "{0}.{1}" -f $Version.Major, $Version.Minor }
    return "{0}.{1}.{2}" -f $Version.Major, $Version.Minor, $Version.Patch
}

function Test-GodotVersionMatch($Version, $Required) {
    if ($null -eq $Required) { return $true }
    if ($null -eq $Version) { return $false }
    return ($Version.Major -eq $Required.Major -and $Version.Minor -eq $Required.Minor)
}


# Where to look. Not an attempt at being exhaustive - it is the handful of
# places a Windows dev machine actually keeps an unpacked Godot, and it is meant
# to be added to when a machine keeps it somewhere else. Coming up empty is
# harmless: the message then says how to name the path by hand.
function Get-GodotSearchRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    # GetFolderPath rather than "$env:USERPROFILE\Desktop", because a machine
    # with OneDrive backup switched on has its real Desktop somewhere else.
    $roots.Add([Environment]::GetFolderPath('Desktop'))
    $roots.Add((Join-Path $env:USERPROFILE "Desktop"))
    $roots.Add((Join-Path $env:USERPROFILE "Downloads"))
    $roots.Add((Join-Path $env:USERPROFILE "Godot"))
    $roots.Add((Join-Path $env:LOCALAPPDATA "Godot"))
    $roots.Add((Join-Path $env:LOCALAPPDATA "Programs\Godot"))
    if ($env:ProgramFiles) { $roots.Add((Join-Path $env:ProgramFiles "Godot")) }
    if (${env:ProgramFiles(x86)}) { $roots.Add((Join-Path ${env:ProgramFiles(x86)} "Godot")) }

    # <drive>:\Godot on every fixed disk, which is where a second PC is as
    # likely to keep it as anywhere. Fixed only - a network or removable drive
    # would make this wait on hardware that may not be there.
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -eq [System.IO.DriveType]::Fixed -and $drive.IsReady) {
            $roots.Add((Join-Path $drive.RootDirectory.FullName "Godot"))
        }
    }

    $seen = @{}
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $key = $root.ToLowerInvariant().TrimEnd('\')
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if (Test-Path -LiteralPath $root) { $result.Add($root) }
    }
    return $result
}


# Every Godot-looking executable under those roots, with what can be read off
# its name. Depth 2 because the usual shape is an archive unpacked onto the
# desktop - and note that Godot's zip unpacks into a FOLDER whose own name ends
# in ".exe", so -File matters here rather than being belt and braces.
function Find-GodotCandidates {
    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($root in (Get-GodotSearchRoots)) {
        $found = @(Get-ChildItem -LiteralPath $root -Filter "Godot*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue)
        foreach ($item in $found) {
            $key = $item.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $version = Get-GodotExeVersion $item.FullName
            if ($null -eq $version) { continue }
            $lower = $item.Name.ToLowerInvariant()
            $candidates.Add([pscustomobject]@{
                Path      = $item.FullName
                Version   = $version
                IsMono    = $lower.Contains("mono")
                IsConsole = $lower.Contains("console")
                Written   = $item.LastWriteTime
            })
        }
    }
    return $candidates
}


# Of the ones matching the project's engine version, the newest patch. Then
# plain over mono and windowed over console, so a machine holding a whole shelf
# of Godot builds - which is what a Godot machine looks like after a year -
# still picks the one a person would have picked.
function Select-GodotCandidate($Candidates, $Required) {
    $usable = @($Candidates | Where-Object { Test-GodotVersionMatch $_.Version $Required })
    if ($usable.Count -eq 0) { return $null }
    $order = @(
        @{ Expression = { $_.Version.Patch }; Descending = $true },
        @{ Expression = { [int]$_.IsMono }; Descending = $false },
        @{ Expression = { [int]$_.IsConsole }; Descending = $false },
        @{ Expression = { $_.Written }; Descending = $true }
    )
    return (@($usable | Sort-Object -Property $order)[0])
}


# The remembered answer, so the search runs once per machine rather than once
# per build. A plain path in a git-ignored file next to these scripts, editable
# by hand, and only ever a CACHE - a stale one is re-derived rather than
# believed.
function Get-GodotCacheFile {
    return (Join-Path $GodotPathToolsDir "godot_path.local.txt")
}

function Read-GodotCache {
    $file = Get-GodotCacheFile
    if (-not (Test-Path -LiteralPath $file)) { return "" }
    foreach ($line in (Get-Content -LiteralPath $file)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        return $trimmed.Trim('"')
    }
    return ""
}

function Write-GodotCache([string] $Path) {
    $lines = @(
        "# Where the Godot editor is on THIS machine, found by Tools/godot_path.ps1.",
        "# Git-ignored and per-machine. Edit or delete it freely - deleting it only",
        "# makes the next run look again.",
        $Path
    )
    # No BOM, and written through .NET rather than Set-Content, which in
    # PowerShell 5.1 would write one.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Get-GodotCacheFile), (($lines -join "`r`n") + "`r`n"), $utf8NoBom)
}


function Show-GodotVersionWarning([string] $Path, $Required) {
    $version = Get-GodotExeVersion $Path
    if ($null -eq $version) { return }
    if (Test-GodotVersionMatch $version $Required) { return }
    $leaf = Split-Path $Path -Leaf
    $message = "Warning: {0} looks like Godot {1}, but this project is on {2}." -f $leaf, (Format-GodotVersion $version), (Format-GodotVersion $Required)
    Write-Host $message -ForegroundColor Yellow
}

function Show-GodotNotFound($Candidates, $Required, [string] $ScriptName) {
    Write-Host "Godot executable not found." -ForegroundColor Red
    if ($null -ne $Required) {
        Write-Host ("  This project is on Godot {0} (project.godot)." -f (Format-GodotVersion $Required))
    }
    Write-Host ""
    if (@($Candidates).Count -gt 0) {
        Write-Host "  Found, but not a match:"
        foreach ($candidate in (@($Candidates) | Sort-Object -Property Path)) {
            Write-Host ("    {0,-8} {1}" -f (Format-GodotVersion $candidate.Version), $candidate.Path)
        }
    } else {
        Write-Host "  Nothing Godot-shaped in the usual places: Desktop, Downloads,"
        Write-Host "  Program Files\Godot, <drive>:\Godot."
    }
    Write-Host ""
    Write-Host "Name it, any of these three ways:"
    Write-Host ("  .\Tools\{0} -Godot ""C:\path\to\Godot.exe""" -f $ScriptName)
    Write-Host '  $env:GODOT = "C:\path\to\Godot.exe"'
    Write-Host ("  put the path in {0}" -f (Get-GodotCacheFile))
}


# Returns the path to use, or "" - in which case it has already printed why and
# the caller only has to exit.
function Resolve-GodotExe {
    param(
        [string] $Explicit = "",
        [string] $ProjectRoot = "",
        [string] $ScriptName = "build_client.ps1"
    )

    $required = $null
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $required = Get-RequiredGodotVersion $ProjectRoot
    }

    # Anything a person named by hand is used as given. A version that does not
    # match the project is worth saying out loud but is not an error: building
    # with a different patch, or checking whether a newer editor still opens
    # this project, are both things somebody may be doing on purpose.
    foreach ($named in @($Explicit, $env:GODOT)) {
        if ([string]::IsNullOrWhiteSpace($named)) { continue }
        if (-not (Test-Path -LiteralPath $named)) {
            Write-Host "Godot executable not found:" -ForegroundColor Red
            Write-Host "  $named"
            Write-Host ""
            Write-Host "That path came from -Godot or from `$env:GODOT. Fix it, or clear it and let"
            Write-Host "the script find the editor itself."
            return ""
        }
        Show-GodotVersionWarning $named $required
        return $named
    }

    # A remembered path is believed only while it still exists AND still
    # matches the project, so bumping the engine re-finds the editor on its own
    # instead of quietly building with the old one.
    $cached = Read-GodotCache
    $cachedExists = (-not [string]::IsNullOrWhiteSpace($cached)) -and (Test-Path -LiteralPath $cached)
    if ($cachedExists -and (Test-GodotVersionMatch (Get-GodotExeVersion $cached) $required)) {
        return $cached
    }

    $candidates = Find-GodotCandidates
    $picked = Select-GodotCandidate $candidates $required
    if ($null -ne $picked) {
        Write-Host ("Godot {0}: {1}" -f (Format-GodotVersion $picked.Version), $picked.Path) -ForegroundColor DarkGray
        Write-Host ("  remembered in {0}" -f (Get-GodotCacheFile)) -ForegroundColor DarkGray
        Write-GodotCache $picked.Path
        return $picked.Path
    }

    # Nothing matched the project's version, but a remembered path still runs.
    # A warning beats a stop here: the engine may have been bumped before the
    # new editor was unpacked on this machine.
    if ($cachedExists) {
        Show-GodotVersionWarning $cached $required
        return $cached
    }

    Show-GodotNotFound $candidates $required $ScriptName
    return ""
}
