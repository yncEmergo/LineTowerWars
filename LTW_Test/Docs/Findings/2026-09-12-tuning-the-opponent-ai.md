# Tuning the opponent AI: six things that were wrong, measured

**2026-09-12.** Written while building the first computer opponent. Everything
here came out of `Tools/run_ai_bench.ps1` playing profiles against each other;
none of it was visible in a log, and every one of the six looked correct in the
code.

The numbers are a snapshot of one afternoon against one roster. What is durable
is the CAUSES - read those and ignore the figures.

## The harness

`Scenes/Tools/ai_bench.tscn` plays a real match with every seat taken by a
profile and nobody watching, at 400 Hz instead of 20, and prints one line per
player. A thirty minute match takes about a hundred seconds.

It exists because a profile is a dozen numbers and what they add up to is a
match, not a sum. Reading them is guessing.

## 1. The cheapest rule wins every race against an empty purse

**Symptom:** an AI built a beautiful maze and, in twenty minutes, never sent a
single creep.

**Cause:** the rules were tried in priority order and the pass stopped at the
first that spent. Building costs ten gold and sending costs more, so the build
rule answered yes on every pass and the send rule was asked with nothing left.

**Fix:** a FLOOR per rule - each refuses to spend below its own - so gold filling
up switches the rules on one at a time instead of the cheapest one taking
everything.

## 2. One shared floor moves the problem one rule along

**Symptom:** with a single reserve, upgrades - cheap and constant - ate every
coin and the maze stopped growing at eight towers for the rest of the match.

**Fix:** three floors, lowest for sending, highest for upgrading.

## 3. Stopping the pass at the first rule that spent starves upgrades

**Symptom:** two difficulties that should have been a tier apart both ended a
full match with eighty-odd Basic towers, a million gold in the bank and nothing
upgraded.

**Cause:** building is limited by the BUILDER'S WALK rather than by gold - it
crosses the lane between towers, exactly as a player's does - so an AI on a
million gold still orders one or two towers a beat, and the maze rule answered
yes to every pass for twenty-five minutes.

**Fix:** every rule gets its turn each pass. The floors are what keep that
honest.

## 4. A tier cap silently disables sending for the whole endgame

**Symptom:** three matches in a row ended 100-100 at the clock with nobody having
lost a life.

**Cause:** at Sudden Death the whole of tier 4 opens and tiers 1 to 3 stop being
sendable for good (`game_rules.md`). A profile capped at tier 2 therefore has an
EMPTY CARD from that moment - the cap reads as "does not use fancy creeps" and
behaves as "stops playing after twenty-five minutes".

**Fix:** the cap does not apply to the Sudden Death sender.

## 5. Income per GOLD is the wrong metric for a sender on a beat

**Symptom:** switching the send rule from "the biggest creep I can afford" to
"the best income per gold" made every match end 100-100. Switching it to a dial
between the two made the difficulty with the HIGHER setting earn a fifth of what
the one below it earned.

**Cause:** the AI sends on a BEAT, so what it maximises is income per SEND, not
per gold. Cheap efficient creeps have the better ratio and grant less each, so an
AI buying them on a fixed clock earns less and threatens nobody.

**What this says about the design rather than the bug:** the dial is not wrong,
the beat is. A player sends whenever they can afford something worth sending, and
an AI that did the same would make efficiency the right metric. Until it does,
`send_efficiency` stays near zero and `send_seconds` is the same for every
profile - it turned out to be a stronger difficulty lever than any of the
deliberate ones, which is a good reason for it not to be one.

## 6. A plan bigger than the AI can finish is a hole, not a maze

**The one that came back five times, in five disguises.** Every single matchup
was won by the side whose maze was COMPLETE, whatever else was true:

- a 42-cell zigzag beat a 155-cell endgame blueprint built to 74
- a 63-cell plan beat an 84-cell plan built to 60
- and at every size in between, the complete one won

**Cause:** the build rate is the binding constraint - about fifty towers in a
full match - and a zigzag missing its last rows is a corridor creeps walk
straight down. Length is worth nothing until it is finished.

**Fix, in two parts.** Every profile's plan is now sized under what it can build
out, and difficulty is quality - upgrades, how often it thinks, how many towers
it orders at once - rather than length. And the plan stopped being a QUEUE: it is
a set of cells, walked for the cheapest one that can be afforded, so a single
expensive entry can no longer block every cheap cell behind it.

## 7. Elemental towers are a net loss at this AI's economy

Aiming a share of the maze at an Ultimate works - the AI takes the technology,
builds Elemental Cores and morphs them up the right branch - and it LOSES.

A 200g Core is twenty Basic towers. An AI buying them stops sending, so its
income never grows, so it never affords more, and it ends a thirty minute match
with ten towers and no income at all. Two different starvation bugs were fixed
along the way (the send rule draining the gold the maze was saving, and then the
maze saving so hard it never sent) and it still lost.

**So `elemental_share` ships at zero.** The mechanism is built and is one number
away; what has to come first is an economy strong enough to pay for it, which
means an AI that sends properly rather than on a clock. This is the single most
valuable thing to do next - `game_rules.md` is clear that Basic towers do not win
matches, and a hard opponent that never leaves them is a hard opponent that
loses late to anybody who does.

## 8. An ORDER IS NOT A TOWER - and this one invalidates some of the above

**The last bug found and by far the worst**, because it was underneath most of
the others.

**Symptom:** the profile that chained THREE build orders a beat finished a thirty
minute match with twelve towers and almost no income. The one that ordered a
single tower finished with twenty-seven. More orders produced fewer towers.

**Cause:** the AI crossed a cell off its plan when it ORDERED one. But a build is
paid for when the builder REACHES the spot, not when the button is pressed - so a
chain longer than the gold in hand has its tail dropped there, by design and
exactly as it is for a player (`Builder._start_pending_build`). Every cell the AI
could not afford on arrival was lost from its maze for the rest of the match, and
the loss scaled with how many it ordered at once.

**Fix:** nothing is struck off for having been ordered. What is STANDING is the
only honest record, so the plan asks the area instead and skips a cell something
is already on.

**With it fixed the ladder is monotonic on two seeds**: Normal beats Easy 200-0,
Hard beats Normal 127-73, Insane beats Hard 122-78, Insane beats Easy 200-0.

### What that means for findings 5 and 6

**They were measured with this bug present and should be re-tested.** Every one of
those matches was between two AIs with holes in their mazes that neither of them
had put there, so:

- "a plan bigger than the AI can finish is a hole" is still true as a statement
  about build rate, but the build rate it was measured against was wrong - the
  plans may safely be much longer than the current profiles use
- "income per gold is the wrong metric" may have been an artifact: an AI whose
  maze is full of holes leaks whatever it is sent, so nothing it bought could
  have looked good
- the same goes for elemental towers in finding 7. A 200g Core is still twenty
  Basic towers, but it was competing against a maze that was losing cells for
  free

So the sensible next step is not a new feature - it is to run the matrix again,
one variable at a time, now that the thing being measured is the thing that was
meant to be measured. That is what the bench is for.

## Where it ended up

A monotonic ladder on two seeds, decisive against Easy, with every profile on a
maze it completes, no elemental towers, and a send rule on a fixed clock.

Re-run it with `.\Tools\run_ai_bench.ps1 -A Hard -B Normal -Minutes 30 -Seed 11`.
Pass the same seed to compare two tunings; pass different ones before believing
either. **And re-read section 8 before trusting anything in 5, 6 or 7.**
