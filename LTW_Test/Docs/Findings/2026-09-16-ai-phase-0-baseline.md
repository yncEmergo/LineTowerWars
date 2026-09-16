# AI phase 0: the baseline the rework is measured against

**2026-09-16.** Phase 0 of `ai-rework.md` landed: the brain got its own random stream, a draft
rule, half-cell zigzag corridors, a bench that prints a machine-readable result, a matrix runner
that swaps seats, and two exploiter profiles. This is what the ladder looks like after it, so
that every later phase has something to beat.

Everything here is one afternoon on the Windows dev PC, headless, engine driven at 240 Hz. A
match is 25 minutes of play unless it says otherwise.

## Why a baseline at all

`Findings/2026-09-12-tuning-the-opponent-ai.md` ended with a ladder that was ordered but not
trustworthy: it was measured with a bug that silently lost towers, and only some of it was
re-run afterwards. Worse, **the AI was rolling on the match RNG**, so two profiles that skip a
different number of passes consumed the shared stream differently and the same seed did not mean
the same match. Phase 0 fixed that, which means every number from before it is measured on a
different game.

The RNG fix can now be seen working: the twelve-match matrix was played twice, hours apart, and
the first three matches came back **byte-identical in every field**. A seed is a match again.

## What was measured

- `Tools/run_ai_matrix.ps1 -Seeds 1 -FirstSeed 101 -Minutes 25`, which plays every pair of the
  four selectable difficulties **both ways round** - the seat swap is the point, because a
  profile that only wins from seat 1 has beaten nothing.
- The same three top difficulties again at **35 minutes**, which is the first length that
  reaches the game's own tie-breaker. See "The clock ends before the tie-breaker does".
- Single matches for the exploiter profiles, which are not part of the ladder.

Two things to know when reading the numbers: `income` in a pair line is **peak** income, not
income at the end, and `towers` is towers **built** over the whole match rather than towers
standing at the end of it.

### The ladder at 25 minutes

```
AI MATRIX  12 matches, 1 seeds, seats swapped, 25 minutes each

  DECIDED: somebody was eliminated
  beat >          Easy    Normal      Hard    Insane
  Easy               -         0         0         0
  Normal             2         -         0         0
  Hard               2         0         -         0
  Insane             2         0         0         -
  undecided at the clock: 6

  AND ON LIVES: every draw broken by who was closer to death
  beat >          Easy    Normal      Hard    Insane
  Easy               -         0         0         0
  Normal             2         -         0         1
  Hard               2         0         -         0
  Insane             2         0         2         -
  dead even: 3

  LADDER (each against the one below it)
    Normal   over Easy     decided 2-0, on lives 2-0  holds
    Hard     over Normal   decided 0-0, on lives 0-0  BROKEN
    Insane   over Hard     decided 0-0, on lives 2-0  holds on lives only

  TRANSITIVE: no cycle runs through this ladder.
```

**Easy is the only difficulty this ladder separates**, and it loses all six of its matches 0-200
from both seats. The other three never resolve: three of their six matches end *exactly* 100-100,
which is not one creep leaking in either direction for twenty-five minutes. The research the plan
was built on predicted this - two bots dribbling cheap creeps at each other ran 33 minutes
without a leak (`ai-rework.md` 2, finding 4).

Two more readings, both of which say the same thing about what the brain is missing:

- **Easy builds two to six times as many towers as anything else and loses every match.** 225
  towers against Hard's 35 in one of them.
- **Insane's economy buys nothing.** In one match its peak income was 33.6k against Hard's 6.4k -
  five times - and it finished 107-93. Gold that cannot be turned into pressure is not an
  advantage, and the send rule spends by price rather than by what would get through.

### Past Sudden Death, at 35 minutes

Same three profiles, same seed, long enough to reach the tie-breaker. Every match here reports
`sudden_death=1`.

```
AI MATRIX  6 matches, 1 seeds, seats swapped, 35 minutes each

  DECIDED: somebody was eliminated
  beat >        Normal      Hard    Insane
  Normal             -         0         0
  Hard               0         -         0
  Insane             1         2         -
  undecided at the clock: 3

  AND ON LIVES: every draw broken by who was closer to death
  beat >        Normal      Hard    Insane
  Normal             -         1         0
  Hard               1         -         0
  Insane             2         2         -
  dead even: 0

  LADDER (each against the one below it)
    Hard     over Normal   decided 0-0, on lives 1-1  BROKEN
    Insane   over Hard     decided 2-0, on lives 2-0  holds
```

**Insane is genuinely the top of this ladder, and only past 25:20 can anything say so.** It
eliminated Normal and Hard outright three times and took the fourth 172-28, winning from both
seats, which is what the seat swap is for.

**Hard and Normal are the same difficulty.** They split 1-1 with margins of 194-6 and 142-58 -
the same two profiles, the same seed, opposite chairs, opposite thrashings. That is variance, not
a ladder, and the two profiles differ by numbers too small to survive it.

**Sudden Death flattens the economy completely.** Every peak income above is between 1.66M and
1.87M, because `sudden_death_income_floor` raises everybody to a million the moment it starts. So
whatever economic lead a profile built before 25:20 is erased at it, and the last ten minutes are
decided by the maze and the sends alone. For the rework that cuts both ways: an economy model
cannot be measured after Sudden Death, and a maze model cannot be measured before it.

## What actually separates the difficulties: upgrading, and nothing else

Counted out of the match logs, per match, placements against upgrades:

| Match | Towers placed | Upgraded to Archer | Climbed the Watch Tower line |
| --- | --- | --- | --- |
| Easy 156 + Normal 35 | 191 | 35 | 35 |
| Hard 35 + Easy 225 | 260 | 33 | 22 |
| Normal 35 + Hard 35 | 70 | 68 | 57 |

The upgrade count in the first two rows is **the other player's tower count**, near enough. Easy
never upgrades a single tower in any match: `upgrades_towers = false` on its profile, which is
authored rather than accidental. So the ladder's only real separation is height against width,
and it is not close - **35 towers that climbed the chain beat 225 that did not, from both
seats, every time.**

Everything builds the same line, incidentally: Lesser Archer into Archer into the Watch Tower
chain, with a handful of Elemental Cores. That is review finding G2 - the menu order chooses the
tower line, so "which towers" is not yet a difference between difficulties at all.

## The clock ends before the tie-breaker does

`sudden_death_seconds` is 1500, and `GameConfig.unlock_clock` adds the 20 second start delay, so
**Sudden Death begins at 25:20** - twenty seconds after a 25-minute bench match is cut off. Every
pair line above reads `sudden_death=0`. The three top difficulties were being measured only over
the stretch of the game in which neither of them can force anything, which is why three of their
six matches ended exactly level.

That is a property of the harness, not of the AI, and the plan now says so: a bench match has to
run past 25:20 to be decided by the rule the game provides for deciding it.

## Single matches worth recording

| Match | Result |
| --- | --- |
| All-in vs Turtle, seed 7, 8 min | undecided at the clock, All-in 108 lives to 92. All-in: 7 towers, 123 creeps sent, 1.5k peak income. Turtle: 133 towers, nothing sent, 20 income |

The Easy vs Insane single match this file carried before is gone: the matrix plays the same pair
on the same seed and disagrees with it, 18:39 rather than 13:08. The same seed now reproduces the
same match exactly, so a different result means different code rather than a different roll - that
run was made by hand while phase 0 was still being assembled, and was not measuring this.

## Three things the exploiters found immediately

1. **A build floor high enough to stop building also stops SENDING.** The first All-in profile
   never sent a creep in six minutes. The send rule may not spend what the maze is saving for
   (`AiPlayer._saving_for`), and a plan that can never be afforded saves for ever. So "never
   builds" is not expressible by starving the build rule - the profile builds one row instead.
2. **A turtle's income does not move at all.** 133 towers and an income that never left its
   starting value, because income comes only from sending. It is the clearest statement of why
   `strategy.md` 1 says income is the whole game.
3. **An all-in with seven towers was still AHEAD on lives** against it at eight minutes. Neither
   is an opponent; both are a measuring stick.

## The harness reported that nothing had run, while everything ran

The first twelve-match matrix printed `NOTHING RAN. No match printed a result line.` after most
of an hour. Every one of the twelve matches had finished and printed its result; the runner
could not see any of them.

`run_ai_bench.ps1` starts Godot with `Start-Process -NoNewWindow`, which hands the child THIS
console - so its output goes to the terminal and never enters the calling script's pipeline.
`$output = & $bench ... 2>&1 | Out-String` captured an empty string while the run printed
perfectly on screen. It is the third face of the `& $godot` trap already in `CLAUDE.md`, where it
now lives, and it has the same shape as the positive-control rule: **"no output" and "output I
cannot see" are indistinguishable from the caller.**

What changed, so it cannot happen quietly again:

- `run_ai_bench.ps1 -LogFile <path>` redirects the run to a file, and the matrix reads the FILE.
- **The first match is the harness's own positive control.** If it produces no readable result
  the runner stops there, rather than proving the same thing eleven more times over an hour.
- Each run keeps its match logs in a folder of their own, and `-FromLogs <folder>` re-reads a
  finished run and prints the tables again without playing anything. The 25-minute matrix above
  was printed that way, from the logs of the run that could not report itself.
- A replay checks that `match_N.txt` holds the pairing that iteration expects, since reading logs
  by position would otherwise file every result under the wrong pair.
- The matrix now prints a **second table broken by lives**, because `winner=none` is not the same
  as a tie: a 194-6 draw is a thrashing, and the ladder was blind to it.

## What this baseline is for

- **Phase 2's acceptance test** is that the new economy beats today's brain at every tier with
  the maze behaviour unchanged. Measure it BEFORE 25:20, because the income floor erases the
  difference afterwards.
- **Phase 5's** is that the new Normal beats today's Insane. Measure it PAST 25:20, because
  nothing below that length decides anything between two profiles that both hold their lane.
- **No difficulty may lose to an exploiter it should handle.** Today's ladder has never been
  asked that question; the profiles now exist to ask it.
- **Hard and Normal have to become different difficulties.** Today they are two spellings of one
  profile, and the bench says so from both chairs.

## What is still open

- **One seed decides nothing between Normal and Hard.** Their two matches went 194-6 and 142-58
  to opposite seats. Either profile can thrash the other; a run with several seeds is the only
  way to find out whether anything separates them, and the honest reading today is that nothing
  does.
- **Whether a seat is worth anything.** In the Normal-Hard pair the player in seat b won both
  times, but Insane won from both seats, so this is most likely each seat's own RNG stream rather
  than a bias in the world. `AiPlayer._rng` is seeded from `hash([seed, slot])`, so the two seats
  genuinely play different games. Several seeds would answer it; one cannot.
- **Nothing here says what an AI is worth against a PERSON.** Every number is an AI against an AI,
  and the ladder being ordered does not make any rung the right difficulty for a human at it.

## How to re-run it

```
.\Tools\run_ai_matrix.ps1 -Seeds 2 -Minutes 25
.\Tools\run_ai_matrix.ps1 -Names Normal,Hard,Insane -Seeds 2 -Minutes 35
.\Tools\run_ai_bench.ps1 -A Insane -B "All-in" -Minutes 25 -Seed 101
.\Tools\run_ai_matrix.ps1 -FromLogs <folder>      re-print a finished run, playing nothing
```

**A match at 240 Hz is not instant.** A 25-minute one takes a couple of minutes of real time and
a 35-minute one takes longer than the extra ten minutes suggest, because both sides flood the
field once Sudden Death unlocks tier 4. A twelve-match matrix is most of an hour. Run it in the
background, and if it needs reading again afterwards, use `-FromLogs` rather than replaying it.
