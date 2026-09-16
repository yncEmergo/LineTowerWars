# AI phase 0: the baseline the rework is measured against

**2026-09-16.** Phase 0 of `ai-rework.md` landed: the brain got its own random stream, a draft
rule, half-cell zigzag corridors, a bench that prints a machine-readable result, a matrix runner
that swaps seats, and two exploiter profiles. This is what the ladder looks like after it, so
that every later phase has something to beat.

Everything here is one afternoon on the Windows dev PC, headless, engine driven at 240 Hz. A
match is 25 minutes of play unless it ends earlier.

## Why a baseline at all

`Findings/2026-09-12-tuning-the-opponent-ai.md` ended with a ladder that was ordered but not
trustworthy: it was measured with a bug that silently lost towers, and only some of it was
re-run afterwards. Worse, **the AI was rolling on the match RNG**, so two profiles that skip a
different number of passes consumed the shared stream differently and the same seed did not mean
the same match. Phase 0 fixed that, which means every number from before it is measured on a
different game.

## What was measured

- `Tools/run_ai_matrix.ps1 -Seeds 1 -FirstSeed 101 -Minutes 25`, which plays every pair of the
  four selectable difficulties **both ways round** - the seat swap is the point, because a
  profile that only wins from seat 1 has beaten nothing.
- Single matches for the exploiter profiles, which are not part of the ladder.

### The ladder

*(To be filled in from the matrix run started on 2026-09-16; it was still running when this file
was written. The run prints the win matrix, the ladder check and the transitivity verdict.)*

### Single matches worth recording

| Match | Result |
| --- | --- |
| Easy vs Insane, seed 101, 25 min | Insane won at 13:08, 200 lives to 0. Easy peaked at 1.7k income against Insane's 1.1k and built more towers (81 to 54), and still lost - it sent 74 packs to Insane's 98 |
| All-in vs Turtle, seed 7, 8 min | undecided at the clock, All-in 108 lives to 92. All-in: 7 towers, 123 sends, 1,472 income. Turtle: 133 towers, no sends, 20 income |

**The Easy vs Insane line is the interesting one.** The loser had the better economy and the
bigger maze. Insane won on what it built rather than how much: its plan turns elemental, and
Easy's is a wall of the same 10g tower climbing one Piercing line. That is review finding G2
showing up as a result rather than as a reading of the code.

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

## What this baseline is for

- **Phase 2's acceptance test** is that the new economy beats today's brain at every tier with
  the maze behaviour unchanged.
- **Phase 5's** is that the new Normal beats today's Insane.
- **No difficulty may lose to an exploiter it should handle.** Today's ladder has never been
  asked that question; the profiles now exist to ask it.

## How to re-run it

```
.\Tools\run_ai_matrix.ps1 -Seeds 2 -Minutes 25
.\Tools\run_ai_bench.ps1 -A Insane -B "All-in" -Minutes 25 -Seed 101
```

**A match at 240 Hz is not instant.** A full-length one takes a couple of minutes of real time,
and a twelve-match matrix is most of an hour. Run it in the background and read the summary at
the end, rather than watching it.
