# Plays every pair of difficulties against each other, both ways round, over
# several seeds, and says whether the ladder is really a ladder.
#
#   .\Tools\run_ai_matrix.ps1                                 every selectable difficulty, 2 seeds
#   .\Tools\run_ai_matrix.ps1 -Names Easy,Normal -Seeds 3     a smaller matrix
#   .\Tools\run_ai_matrix.ps1 -Minutes 12 -Seeds 1            a quick shape check
#
# **A single match is not evidence.** One seat may be luckier than the other, and
# one seed may suit one profile, so every pair is played with the seats SWAPPED
# on each seed - the fishtest shape (Findings/2026-09-15-rts-ai-research.md §5).
# A profile that only wins from one seat has not beaten anything.
#
# It prints a win matrix, the lives either side, and a TRANSITIVITY verdict: a
# ladder is only a ladder if every difficulty beats the one below it and no cycle
# runs through the middle of it.
#
# Each match is one `run_ai_bench.ps1` run, so nothing here knows how a match is
# played; it reads the `AI BENCH PAIR` line that bench prints.

param(
	[string[]]$Names = @("Easy", "Normal", "Hard", "Insane"),
	[int]$Seeds = 2,
	[int]$FirstSeed = 101,
	[double]$Minutes = 25,
	[int]$Speed = 240,
	# Re-read a FINISHED run's match logs and print the tables again, playing
	# nothing. The same -Names, -Seeds and -FirstSeed have to be given, because
	# the loop below is what says which pairing each match_N.txt was.
	[string]$FromLogs = "",
	[string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$bench = Join-Path $PSScriptRoot "run_ai_bench.ps1"

# One folder per run, so a match that went wrong can still be read afterwards.
$replay = -not [string]::IsNullOrWhiteSpace($FromLogs)
if ($replay) {
	$logDir = $FromLogs
	Write-Host "Re-reading a finished run: $logDir"
} else {
	$logDir = Join-Path $env:TEMP ("ai_matrix_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
	New-Item -ItemType Directory -Path $logDir -Force | Out-Null
	Write-Host "Match logs: $logDir"
}

# Every unordered pair, played both ways round on every seed.
$results = @()
$total = 0
foreach ($seedStep in 0..($Seeds - 1)) {
	$seed = $FirstSeed + $seedStep
	for ($i = 0; $i -lt $Names.Count; $i++) {
		for ($j = $i + 1; $j -lt $Names.Count; $j++) {
			foreach ($swap in @($false, $true)) {
				$a = if ($swap) { $Names[$j] } else { $Names[$i] }
				$b = if ($swap) { $Names[$i] } else { $Names[$j] }
				$total++
				Write-Host ("[{0}] {1} vs {2}  seed {3}" -f $total, $a, $b, $seed)

				# READ THE MATCH OFF A FILE, never off the pipeline. The bench
				# runs Godot through Start-Process -NoNewWindow, which hands the
				# child THIS console - so its output goes to the terminal and
				# `$x = & $bench` captures an empty string however it is piped.
				# That cost a full twelve-match run: every match finished and
				# printed its line, and this script reported that none had.
				$log = Join-Path $logDir ("match_{0}.txt" -f $total)
				if (-not $replay) {
					& $bench -A $a -B $b -Seed $seed -Minutes $Minutes `
						-Speed $Speed -Godot $Godot -LogFile $log
				}
				$line = ""
				if (Test-Path $log) {
					$found = Select-String -Path $log -Pattern "AI BENCH PAIR" -SimpleMatch
					if ($found) { $line = $found[-1].Line }
				}
				if (-not $line) {
					Write-Warning "no result line: that match did not finish ($log)"
					# **The first match is the positive control for the harness
					# itself.** If THAT one cannot be read, nothing downstream
					# can be either, and eleven more matches is most of an hour
					# spent proving it again.
					if ($total -eq 1) {
						Write-Host "The first match produced no readable result. Stopping."
						exit 1
					}
					continue
				}

				$fields = @{}
				foreach ($pair in ([regex]::Matches($line, '(\w+)=([^\s]+)'))) {
					$fields[$pair.Groups[1].Value] = $pair.Groups[2].Value
				}
				# **The log has to BE the match this iteration means.** A replay
				# reads match_N.txt by position, so a different -Names or -Seeds
				# would silently file every result under the wrong pair.
				if ($fields["a"] -ne $a -or $fields["b"] -ne $b) {
					Write-Warning ("{0} holds {1} vs {2}, not {3} vs {4} - skipped" -f `
						$log, $fields["a"], $fields["b"], $a, $b)
					continue
				}
				$results += [pscustomobject]@{
					A = $a; B = $b; Seed = $seed
					Winner = $fields["winner"]
					LivesA = [int]$fields["lives_a"]; LivesB = [int]$fields["lives_b"]
					IncomeA = [int]$fields["income_a"]; IncomeB = [int]$fields["income_b"]
					TowersA = [int]$fields["towers_a"]; TowersB = [int]$fields["towers_b"]
				}
				$last = $results[-1]
				Write-Host ("     winner {0}   lives {1}-{2}   towers {3}-{4}" -f `
					$last.Winner, $last.LivesA, $last.LivesB, $last.TowersA, $last.TowersB)
			}
		}
	}
}

if ($results.Count -eq 0) {
	Write-Host ""
	Write-Host "NOTHING RAN. No match printed a result line."
	exit 1
}

# --- two tables, because a decisive win and a lives margin are not the same
# claim. wins[x][y] counts the matches x DECIDED against y, meaning a player was
# actually eliminated. edge[x][y] adds the draws broken by who was closer to
# death at the clock - which is the only thing that separates two profiles that
# both hold their lane for the whole match, and a 194-6 draw is not a tie.
$wins = @{}
$edge = @{}
foreach ($name in $Names) {
	$wins[$name] = @{}
	$edge[$name] = @{}
	foreach ($other in $Names) { $wins[$name][$other] = 0; $edge[$name][$other] = 0 }
}
$draws = 0
$deadEven = 0
foreach ($row in $results) {
	switch ($row.Winner) {
		"a" { $wins[$row.A][$row.B]++; $edge[$row.A][$row.B]++ }
		"b" { $wins[$row.B][$row.A]++; $edge[$row.B][$row.A]++ }
		default {
			$draws++
			if ($row.LivesA -gt $row.LivesB) { $edge[$row.A][$row.B]++ }
			elseif ($row.LivesB -gt $row.LivesA) { $edge[$row.B][$row.A]++ }
			else { $deadEven++ }
		}
	}
}

# -f binds tighter than -join, so the header row has to be built first or the
# whole line prints as System.Object[].
function Write-WinMatrix($table, $caption) {
	Write-Host ""
	Write-Host $caption
	$header = ($Names | ForEach-Object { "{0,10}" -f $_ }) -join ""
	Write-Host ("  {0,-10}{1}" -f "beat >", $header)
	foreach ($name in $Names) {
		$cells = foreach ($other in $Names) {
			if ($name -eq $other) { "{0,10}" -f "-" } else { "{0,10}" -f $table[$name][$other] }
		}
		Write-Host ("  {0,-10}{1}" -f $name, ($cells -join ""))
	}
}

Write-Host ""
Write-Host ("AI MATRIX  {0} matches, {1} seeds, seats swapped, {2} minutes each" -f `
	$results.Count, $Seeds, $Minutes)
Write-WinMatrix $wins "  DECIDED: somebody was eliminated"
Write-Host ("  undecided at the clock: {0}" -f $draws)
Write-WinMatrix $edge "  AND ON LIVES: every draw broken by who was closer to death"
Write-Host ("  dead even: {0}" -f $deadEven)

# --- the ladder, in the order the names were given: does each beat the one below?
Write-Host ""
Write-Host "  LADDER (each against the one below it)"
$ladderHolds = $true
for ($i = 1; $i -lt $Names.Count; $i++) {
	$upper = $Names[$i]
	$lower = $Names[$i - 1]
	$for = $wins[$upper][$lower]
	$against = $wins[$lower][$upper]
	$forLives = $edge[$upper][$lower]
	$againstLives = $edge[$lower][$upper]
	$verdict = "BROKEN"
	if ($for -gt $against) { $verdict = "holds" }
	elseif ($forLives -gt $againstLives) { $verdict = "holds on lives only" }
	if ($verdict -eq "BROKEN") { $ladderHolds = $false }
	Write-Host ("    {0,-8} over {1,-8} decided {2}-{3}, on lives {4}-{5}  {6}" -f `
		$upper, $lower, $for, $against, $forLives, $againstLives, $verdict)
}

# --- transitivity: any x beating y, y beating z, and z beating x at all. On the
# lives table, because with two even profiles the decided one is all zeroes and
# a ladder of zeroes cannot contain a cycle to find.
$cycles = @()
foreach ($x in $Names) {
	foreach ($y in $Names) {
		foreach ($z in $Names) {
			if ($x -eq $y -or $y -eq $z -or $x -eq $z) { continue }
			if ($edge[$x][$y] -gt $edge[$y][$x] -and
				$edge[$y][$z] -gt $edge[$z][$y] -and
				$edge[$z][$x] -gt $edge[$x][$z]) {
				$cycles += ("{0} > {1} > {2} > {0}" -f $x, $y, $z)
			}
		}
	}
}
Write-Host ""
if ($cycles.Count -eq 0) {
	Write-Host "  TRANSITIVE: no cycle runs through this ladder."
} else {
	Write-Host "  NOT TRANSITIVE:"
	foreach ($cycle in ($cycles | Select-Object -Unique)) { Write-Host ("    " + $cycle) }
}
if (-not $ladderHolds) {
	Write-Host "  The ladder does not hold: a difficulty does not beat the one below it."
}
