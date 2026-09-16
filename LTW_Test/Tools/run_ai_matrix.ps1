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
	[string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$bench = Join-Path $PSScriptRoot "run_ai_bench.ps1"

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

				$output = & $bench -A $a -B $b -Seed $seed -Minutes $Minutes `
					-Speed $Speed -Godot $Godot 2>&1 | Out-String
				$line = ($output -split "`n" | Where-Object { $_ -match "AI BENCH PAIR" })
				if (-not $line) {
					Write-Warning "no result line: that match did not finish"
					continue
				}

				$fields = @{}
				foreach ($pair in ([regex]::Matches($line, '(\w+)=([^\s]+)'))) {
					$fields[$pair.Groups[1].Value] = $pair.Groups[2].Value
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

# --- the matrix. wins[x][y] is how many times x beat y, from either seat.
$wins = @{}
foreach ($name in $Names) {
	$wins[$name] = @{}
	foreach ($other in $Names) { $wins[$name][$other] = 0 }
}
$draws = 0
foreach ($row in $results) {
	switch ($row.Winner) {
		"a" { $wins[$row.A][$row.B]++ }
		"b" { $wins[$row.B][$row.A]++ }
		default { $draws++ }
	}
}

Write-Host ""
Write-Host ("AI MATRIX  {0} matches, {1} seeds, seats swapped, {2} minutes each" -f `
	$results.Count, $Seeds, $Minutes)
Write-Host ("  {0,-10}{1}" -f "beat >", ($Names | ForEach-Object { "{0,10}" -f $_ }) -join "")
foreach ($name in $Names) {
	$cells = foreach ($other in $Names) {
		if ($name -eq $other) { "{0,10}" -f "-" } else { "{0,10}" -f $wins[$name][$other] }
	}
	Write-Host ("  {0,-10}{1}" -f $name, ($cells -join ""))
}
Write-Host ("  undecided at the clock: {0}" -f $draws)

# --- the ladder, in the order the names were given: does each beat the one below?
Write-Host ""
Write-Host "  LADDER (each against the one below it)"
$ladderHolds = $true
for ($i = 1; $i -lt $Names.Count; $i++) {
	$upper = $Names[$i]
	$lower = $Names[$i - 1]
	$for = $wins[$upper][$lower]
	$against = $wins[$lower][$upper]
	$verdict = if ($for -gt $against) { "holds" } else { "BROKEN"; }
	if ($for -le $against) { $ladderHolds = $false }
	Write-Host ("    {0,-8} over {1,-8} {2}-{3}  {4}" -f $upper, $lower, $for, $against, $verdict)
}

# --- transitivity: any x beating y, y beating z, and z beating x at all.
$cycles = @()
foreach ($x in $Names) {
	foreach ($y in $Names) {
		foreach ($z in $Names) {
			if ($x -eq $y -or $y -eq $z -or $x -eq $z) { continue }
			if ($wins[$x][$y] -gt $wins[$y][$x] -and
				$wins[$y][$z] -gt $wins[$z][$y] -and
				$wins[$z][$x] -gt $wins[$x][$z]) {
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
