# Playtest 2: the lockstep clock oscillated, and the ping statistic could not see why

**Rewritten the day it was written.** The first version of this finding blamed the office ping
for crossing a threshold in the delay formula, on a correlation that turns out to be an artefact
of pooling two different networks. The fix it prescribed is unchanged and works; the reason given
for it was wrong. How that happened is in "The wrong answer, and how it was reached" below,
because it is the more useful half.

Four players, then two, on 2026-09-07 against the rented server, all in one office behind one
uplink. Both sessions were reported as "really really laggy". The day before, two players on two
separate home connections against the same server were fine. The suspicion was a regression in
one of the multiplayer commits made between them.

**It was not a regression, and it was not the mean latency either.** Under lockstep, when the
true time for a turn word to arrive approaches one whole turn, the delay stops being a tight fit
and becomes an oscillator: peers take turns being late and hand a one-tick stall back and forth
for the length of the match.

## What was asked

Find the source of the lag in the playtest 2 journals, and say which commit caused it.

## How it was measured

Only the journals: `ReferenceFilesFromOtherProjects/PlaytestLogs/Playtest{1,2}/`.

`SessionLog` already writes what is needed. Once per hundred turns:

    lockstep.health { "turn", "delay_turns", "rtt_ms", "rtt_var_ms", "local_jitter_ms", "stalls" }

and once per stall event:

    lockstep.stalled { "turn", "missing", "stalls_so_far" }

`stalls` is `_stalled_total`, which counts stalled TICKS rather than events, so differencing two
health lines gives turns elapsed and ticks held over the same interval. The `lockstep.stalled`
lines give the turn each stall happened on, which is what makes the spacing between them
measurable - and the spacing is where the answer turned out to be.

Nothing was run and nothing was instrumented.

## What was found: the pace, measured

| session | turns | stalled ticks | stall % | mean RTT | ms/turn |
| --- | --- | --- | --- | --- | --- |
| playtest 1, 2p, home links | 9,700 | 59 | 0.6% | 31.4 | **50.7** |
| playtest 1, 2p, home links | 12,200 | 206 | 1.7% | 20.2 | **51.1** |
| playtest 2, 4p, one office link | 21,300 | 5,772 | 27.1% | 37.4 | **70.9** |
| playtest 2, 4p, one office link | 21,200 | 5,264 | 24.8% | 38.4 | 63.6 |
| playtest 2, 4p, one office link | 20,100 | 4,888 | 24.3% | 40.3 | 63.5 |
| playtest 2, 4p, one office link | 18,700 | 4,686 | 25.1% | 39.6 | 63.8 |
| playtest 2, 2p, one office link | 1,200 | 224 | 18.7% | 35.8 | 59.5 |

A turn is 50 ms. Playtest 2 ran at 63-71, so **the world advanced at 70-79% of real time with a
hold every third or fourth tick, all session.** That is the report: not an occasional hitch, a
permanent limp. Subtracting held time leaves 51.2 ms per RUNNING tick, so the clients were
keeping up with everything except the waiting. The stall rate was already 24 stalls by turn 100,
five seconds in with nothing in the world, so simulation load is not involved.

## What was found: the stalls are periodic, not random

This is the measurement that matters, and the one the first version of this finding never took.
Gaps between consecutive stall events, against what independent per-turn stalling at the same
observed rate would give:

**playtest 2, 4 players, p = 0.249 per turn**

| gap in turns | observed | if random |
| --- | --- | --- |
| 1 | **2.5%** | 24.9% |
| 2 | 30.2% | 18.7% |
| 3 | 20.9% | 14.0% |
| 4 | 31.8% | 10.5% |
| 5 | 4.2% | 7.9% |
| 6 | 1.8% | 6.0% |
| 7+ | 8.5% | 18.0% |

**playtest 2, 2 players, p = 0.184 per turn**

| gap in turns | observed | if random |
| --- | --- | --- |
| 1 | **2.5%** | 18.4% |
| 4 | **50.4%** | 10.0% |

Stalling twice in a row is ten times RARER than chance, and gaps of two to four carry 83% of all
events. A lossy link cannot do that. A refractory period followed by a fixed recurrence is a
signature of a system oscillating, and in the 2-player case it is nearly a pure 4-turn beat.

It is also visible by eye. From a two-client editor session:

    turn 738  missing A      turn 740  missing B
    turn 742  missing A      turn 744  missing B

The peers alternate. A peer that stalls loses a tick, which over-corrects its phase and makes its
neighbour the late one on the next round.

## What it means

Under lockstep a peer emits its word for turn N one delay ahead, and needs its neighbour's word
for turn N before running turn N. Writing `skew` for how much later one peer reaches a given turn
than the other, both peers are satisfied only when

    |skew| <= delay * turn_ms - wire

With `delay` 1 that is 50 ms minus the true wire time. As the wire time approaches 50 ms the
tolerance approaches zero, so the equilibrium becomes unstable: any perturbation makes one peer
late, it stalls, the stall shifts it by a whole tick, and the other peer is now the late one.
That is the limit cycle above, and it costs a quarter of every tick budget indefinitely.

**So the question is not "what is the ping", it is "what is the true wire time", and the two are
not the same number.** `_wire_budget_ms` estimates from ENet's mean round trip plus its smoothed
variance. That estimate cannot see the relay flushing only on its render frame, a receiver only
seeing a packet when its main loop next polls, or any tail the smoothing removes.

## What was ruled out

- **The config is byte-identical** between the two playtests, and **playtest 1 already contained**
  the heartbeat (`acec4e8`) and the relay flush guard (`b14db0a`). The only lockstep change made
  after it is the local-jitter term (`68277f5`), which can only RAISE the delay and read 0-1 ms.
- **The mean ping is not the discriminator.** Playtest 1 stalled on 0.6% of ticks at the same
  35-39 ms estimated budget where playtest 2 stalled on 27.5%. Eight milliseconds of ping cannot
  produce a 45x difference in stall rate.
- **Simulation load is not involved.** Playtest 2 was already stalling at turn 100.
- **No peer waits on itself.** In the 4-player match each client's `missing` lists exactly three
  distinct peers and never its own id, so `_emit`'s local record is doing its job. A `godot.log`
  read from a two-client test on one machine appears to show otherwise, because both instances
  write into the same file.
- **The stall log storm is not the cause.** A stall costs five `get_stack()`, four `print_rich`
  and a `push_warning` across `LockstepService` and `MatchSession.hold`, times 5,800 stalls - but
  `local_jitter_ms` stayed at 0-1 and running ticks came in at 51.2 ms, so the clients were not
  pushed off their tick budget by it. Worth fixing on its own terms; it did not cause this.

## What is NOT explained

**What actually pushed the office path to around one turn.** The candidates are the relay's
render-frame flush, each client's poll granularity, and four clients sharing one uplink and one
NAT with the relay unicasting a copy of every word to each of them - but none of them is
measured, because **nothing in this codebase records how long a turn word actually took to
arrive.** The system logs the estimate and never the truth, which is precisely why this was
diagnosed twice.

Also unexplained and possibly unrelated: playtest 1's build was exported with Godot 4.7.2 and
playtest 2's with 4.7.1, following `15fffbd`.

## What was changed

`jitter_margin_ms` 0 -> 20 in `network_config.tres`. Nothing else; the formula is untouched.

It buys a second turn from about 30 ms of estimate upward, so a link measuring 39 ms gets 100 ms
of budget and a LAN at 20 ms still gets 50. It is a blunt fix and deliberately so: two turns of
tolerance breaks the cycle whatever the unmeasured term turns out to be. The cost is one turn -
50 ms - of input delay on anything past 30 ms of estimate.

Confirmed the same day on the office PC, two clients, same rented server:

    7 stalls over ~1,800 turns (0.4%), every one a single tick, no gap under 35 turns
    order.ran waited_ms 99-134 at delay_turns 2

`waited_ms` clustering on 100 is the load-bearing number: two turns of delay costing two turns of
wall clock means the turn clock is running at real time. The oscillation is gone, not damped.

## The wrong answer, and how it was reached

The first version of this finding bucketed every `lockstep.health` sample from BOTH playtests by
estimated budget and found what looked like a clean threshold - 1.7% of ticks stalled at 20-24 ms
of budget, 27% at 40-44. It concluded the formula had no safety factor and the office ping had
crossed the edge.

Every number in that table was correct and the conclusion drawn from it was wrong, because the
buckets pooled two different networks and the budget was standing in for which playtest a sample
came from. Splitting the same data by session destroys it: **within** playtest 1 the stall rate is
flat at 0.6-2% from 20 through 39 ms of budget, and **within** playtest 2 it is flat at 28-30%
from 30 through 54. The correlation existed only between the sessions, never inside one.

What made it plausible was a wrong belief about the topology - that both playtests came from the
same office link, so the RTT difference had to be that link degrading. Being told playtest 1 was
two home connections is what broke it, and the tell was already in the data: a curve that only
appears when two populations are pooled is a curve about the populations.

**A correlation over pooled sessions is a hypothesis about the sessions until it survives being
computed inside one.** That check costs one more group-by and it is the whole difference between
this finding and the one it replaces.

## What is still open

- **There is no measurement of actual word arrival time**, and the second wrong diagnosis in a
  row is the cost of that. The turn word already carries a turn number; recording when each
  peer's word for turn N arrives relative to when turn N was due would have answered this in one
  pass, and would say which of the unmeasured terms above is the real one.
- **The delay flaps** between 1 and 2 through both playtests. The margin moved the boundary below
  the office's whole range so it no longer flaps there, but hysteresis is still the right fix.
- **The quantum is coarse.** At `ticks_per_turn` 1 and 20 Hz the delay can only be 50, 100 or
  150 ms, which is what makes the instability a cliff rather than a slope.
- **The stall log storm**, above. `Waiting on a turn` throttles on `_stall_frames % 40 == 1`,
  which never throttles a one-tick stall, and each one costs a `push_warning` with a full GDScript
  backtrace - so a handful of harmless single-tick holds read as an alarming console.
- **`godot.log` is unreliable when two clients run on one machine.** Use the per-run session logs.

## A second bug, found on the way

Every client in every match logged
`match.warmed { "stats": 0, "scenes": 0, "other": 0, "ms": 0.0 }` and
`ContentWarmer found nothing to warm`. Written up separately in
`2026-09-07-content-warmer-never-ran-in-a-build.md`.
