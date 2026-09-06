# Playtest 1: the ~1 second freezes are content loading on ONE machine

**2026-09-06.** First real playtest: two players, two machines, against the rented server.
Build `a88eaa1`. Both players' session logs captured.

**This document was rewritten the same day it was written.** The first version said both machines
were doing the same expensive work at the same turn. That was wrong, and the section below marked
*The correction* says how the wrong answer was reached, because the method that produced it looked
sound and would produce it again.

## What was reported

> Occasional lag spikes of ~1 s each, where we both at the same time had a game freeze and then
> it continued. Random, roughly every 30-60 s, and NOT during high input — sending 100 creeps
> each went smoothly.

Also a short pause right after the load screen where input did not go through.

## The answer

**One machine (the guest's) stalled for 0.65-0.9 s the first time each kind of content was
spawned, and lockstep passed the freeze to the other player, who was doing nothing wrong.**

Both players therefore saw the same freeze at the same moment, which is why it read as a shared
problem. It was not: the host was idle in every one of them.

## How it was decided

Both session logs, aligned **by turn number rather than by wall clock**. That alignment is still
the right first move - it is what proves the freeze belongs to the simulation rather than to the
network - but on its own it does not say WHOSE simulation.

What settles that is a second question, asked per peer and per freeze:

> How long did THIS peer take to reach the turn it stalled on, and how long should that many
> turns have taken?

A peer that arrives on time and then stalls was WAITING. A peer that takes three times as long to
cover the same turns was WORKING. At 20 Hz the expected time is simply `turns / 20`, so this is
arithmetic on two numbers both logs already carry.

| freeze | host: turns / took / expected | guest: turns / took / expected |
| --- | --- | --- |
| 780 | 7 / 0.35 s / 0.35 s — waiting | 7 / **1.04 s** / 0.35 s — working |
| 790 | 9 / 0.45 s / 0.45 s — waiting | 8 / **1.07 s** / 0.40 s — working |
| 2370 | 6 / 0.31 s / 0.30 s — waiting | 6 / **0.95 s** / 0.30 s — working |
| 2470 | 10 / 0.49 s / 0.50 s — waiting | 9 / **1.10 s** / 0.45 s — working |
| 9040 | 3 / 0.15 s / 0.15 s — waiting | 3 / **0.80 s** / 0.15 s — working |

Five out of five, with no ambiguous case. The host is on time to within 10 ms every time.

## Every freeze is a first instantiation

This part of the original finding stands. Cross-referencing the turn stream against the first
appearance of each ability:

| turn | trigger |
| --- | --- |
| 780, 790 | the first towers FINISH CONSTRUCTION. `build_lesser_archer` was ordered around turn 520; the model is instantiated when the build completes, roughly thirteen seconds later |
| 2370 | the first sheep spawn (`send_sheep` ordered at turn 2324) |
| 2470 | the first tower shot — projectile and impact scenes |
| 9040 | `upgrade_fire_pit_to_magma_well`, one turn after the order |

`UnitStats.scene()` loads its `PackedScene` **synchronously, on the game thread, the first time
something spawns one**. `MatchLoading` thread-loads only `Main.tscn`; everything that scene names
by `res://` path is left until first use.

That is the deliberate design recorded in `CLAUDE.md` — a resource names a scene by PATH so that
loading a tower's stats does not drag in its model. It keeps memory and load time down and moves
the cost to first use.

It explains the shape of the report exactly. Random, because it follows content rather than the
clock. Not during heavy input, because sending a hundred of an already-loaded creep costs nothing
— it is the FIRST one that loads. And turns 780/790 look unrelated to any order because the load
happens at build COMPLETION, not when the build is ordered.

## Why a stall on one machine is a freeze on both

**A stalled peer emits nothing, so its partner stalls too.** While stalling, `_frames` does not
advance, so `current_turn()` does not move, so there is no new turn to close and no word goes out.
The host reached turn 787 on time, found no word from the guest, and stalled; the guest, having
finally got there, then found no word from the *host* for the turns beyond. Both logs show a stall
on turn 787 naming the other peer.

So a 0.7 s hitch on one machine costs both players closer to a second, and the logs of the two look
symmetrical afterwards. That symmetry is an artefact of the recovery, not evidence about the cause.

This is the same shape as the heartbeat problem fixed on 2026-09-05 - a peer that is merely waiting
looks identical to one that has stopped - and it is worth knowing that the *liveness* fix does not
address it. The heartbeat says "I am alive". It does not, and cannot, supply the turn word that is
missing.

## The size of the number is the interesting part

**Loading this content is not slow.** Measured on the dev machine with a renderer, cold, four runs
inside 1%:

- the entire content graph - every unit, model, disc, projectile and impact - loads in about
  half a second;
- a single creep prefab is 3-4 ms, the most expensive single scene in the build is 8 ms;
- first DRAW costs about the same again over the whole roster, and the worst single model is
  21 ms. Deleting the project shader cache and repeating it changed nothing (516 ms vs 524 ms),
  so shader compilation is not a factor: the placeholder roster shares one standard material
  shader.

So the work that took the guest 700-900 ms takes single-digit milliseconds here. **That is a
factor of about a hundred, and it is the part still unexplained by the mechanism.** The leading
hypothesis is the FIRST READ of a freshly downloaded build - Windows Defender scanning each file
as it is first touched, on top of a cold filesystem cache - which fits every symptom: it is
per-file, it is paid once, it does not recur, and it is invisible on the machine that built the
game because those files have been read a thousand times.

What would confirm it: the same tester playing a second match in the same session with no freezes
at all, or the same build re-run after an exclusion is added. Neither has been done.

**This does not change the fix.** Warming the content on the load screen moves the cost to a moment
the player expects to wait, whatever the multiplier turns out to be, and the multiplier is exactly
why it cannot be judged from the dev machine's half a second.

## The separate thing the logs also show

Time held, per minute, from turn progress against wall clock (guest's side):

```
  0- 60s :  4.3%      300-360s :  1.0%
 60-120s :  0.1%      360-420s :  1.2%
120-180s :  2.5%      420-480s :  1.3%
180-240s :  0.2%      480-540s :  3.0%
240-300s :  0.0%      600-660s : 14.8%   <- last minute, 125 stalls
```

Overall: the host lost 7.6 s of 497 s (1.5%), the guest 14.5 s of 630 s (2.3%). The two logs cover
different spans because the host's match ended first, at turn 9810 against the guest's 12310.

**The last minute is not the network either** — it is the tick cost approaching the budget as the
world fills, which is the per-unit cost already recorded as the thing that limits player count.

**And the margin that would have absorbed it was removed on a measurement that did not transfer.**
`jitter_margin_ms` was set to 0 on paired runs in `2026-09-05-lockstep-review-2-response.md` — runs
that were HEADLESS, with no renderer and therefore almost no frame-time variance. On a real client
the margin absorbs frame-time jitter as well as network jitter, and at `delay_turns: 1` there is
only about 30 ms of slack before a tick overrun makes a peer's word late. That is `CLAUDE.md`'s own
"measure on the target" rule, broken by the person who wrote the paired-measurement rule into it.

## The connection

Steady on both sides for the whole match, and different between them, which is worth stating
carefully because the first version of this document quoted one player's figures as if they were
the match's:

| | host | guest |
| --- | --- | --- |
| round trip, p50 | 31 ms | 20 ms |
| round trip, p90 | 32 ms | 20 ms |
| variance, p90 | 5 ms | 4 ms |
| `delay_turns` = 1 | 96 of 99 samples | 120 of 124 samples |

The maxima (143 ms and 183 ms) are the match-start readings, which are ENet's seeded estimate
before it has measured anything. A one-second network outage would show as a large spike in the
following sample. There is none.

## Answers to the two direct questions

- **The game PAUSED; it did not fast-forward.** A stalled peer's clock stops - `_frames` does not
  advance - so the match simply loses that second.
- **The connection was fine.** One of the cleanest links in any log this project has produced.

## The correction

The first version of this document concluded that both machines were doing the same expensive work
at the same turn. The argument was:

> network lateness would hit different turns on each side; one machine hitching would produce a gap
> on the OTHER machine only, as it waited.

The second clause is false, and it is false in a way that is easy to miss: **a peer waiting for a
late partner records its gap at the same turn the partner was late on.** That is what waiting IS.
So "the same turn on both machines" does not distinguish "both worked" from "one worked and one
waited" - it is equally the signature of both - and every piece of evidence assembled was equally
consistent with either.

Worse, the log contains the field that decides it. `lockstep.stalled` carries `missing`, naming
the peer that had not spoken, and it named the guest in every one of the host's stalls. It was
never read.

Three things to carry forward:

**A shared symptom is not shared causation.** Under lockstep every freeze is felt by everybody, by
design. "We both froze" is the expected shape of ANY stall and carries no information about where
it came from.

**Ask who was ON TIME, not who has a gap.** Both peers have a gap. Only one of them failed to
cover its turns in the time those turns should take, and that arithmetic is two subtractions.

**Read the field that names the answer.** `missing` exists precisely to say who was late.

## Traps

**ALIGN TWO PEERS' LOGS BY TURN, NOT BY WALL CLOCK.** Same turn means the simulation; same
wall-clock instant means the network or one machine. The two logs started eight seconds apart and
no amount of staring at timestamps would have shown it. This is still the right first step - it is
just not the last one.

**A stall log records a start, not a duration**, so a count of stalls says nothing about time lost.
The gaps between periodic entries recover it, and this is the third time in three days that a stall
COUNT has proved to be the wrong measurement - it is already in `CLAUDE.md`.

**Both sides' logs, or the answer is a guess.** An even earlier pass on this had only one side and
concluded the host was hitching. One log cannot distinguish "the other peer is slow" from "we are
both slow together", because the only thing either records is waiting for the other.

**A BENCH THAT LOADS IS NOT A BENCH THAT DRAWS.** Under `gl_compatibility` a shader is compiled the
first time something is drawn with it, not when it is loaded, so the first measurement here - which
only ever called `ResourceLoader.load` - could not have seen a shader cost had there been one. The
draw test was written only because the load numbers did not add up against the reported freeze, and
that mismatch is the thing worth noticing.

## What is still open

- The fix: warm content before it is first needed. See `multiplayer-todo.md`.
- Whether the guest's factor-of-a-hundred is antivirus, a cold cache, or something else. It does
  not block the fix, and it is worth one question to that tester.
- The late-match escalation, which is the per-unit simulation cost and not this.
