# Acting on the second review: a match-freezer, a deadlock I built, and the margin measured

**2026-09-05.** Windows dev PC and the rented Hetzner server. Commits `d447d01` through
`82ccfb4`.

## What was asked

Verify [2026-09-05-lockstep-review-2.md](2026-09-05-lockstep-review-2.md) rather than trust
it, then close everything it found.

## Verifying it first

**Every claim checked out.** Unlike the first review, nothing in it was wrong. It is explicit
about what is derived rather than measured, it lists negative results, and it corrected the
first review on a point that mattered - "ENet coalesces the broadcast" is false, because
coalescing happens per destination and a broadcast to N peers is N separate packets.

Its most valuable line is not a finding but the diagnosis behind three of them:

> A test topology that never differs from the assumption cannot falsify it.

Every headless run ever done here was one server and two clients who were both playing.
`multiplayer.get_peers()` and "the match roster" were the same number in all of them.

## Finding 1, and why it was reachable in a real game

`_expected_peers()` built the set of peers a turn waits on from the transport.
`SceneMultiplayer.server_relay` defaults to true - verified, it is set false nowhere - so Godot
announces every client to every other client, and D20 connects a player the moment they press
Multiplayer. Nothing refuses a connection while a match runs.

So anyone opening the multiplayer menu during a 1v1 joined both players' expectation sets,
`_is_complete` never returned true again, and **both worlds froze for the rest of the match**,
with the stall panel naming a peer id that was not in the match.

Reproduced with a genuine third process before fixing, and confirmed after: the lurker
connects, sits in the lobby browser, never enters a match, and the two players run 961 turns
with 96 orders, 0 desyncs, and 0.85 s of hold - all of it the ordinary match-start stall.

Two more symptoms of the same root, both fixed: the turn stream was BROADCAST, so a machine in
the lobby browser received the whole match's traffic and recorded every turn of it for ever
(`_reset_if_new_match` is behind `_is_live()`, so `_last_run_turn` stayed -1 and nothing was
erased); and `_measure_and_announce` took the worst RTT across every connected peer, so
somebody browsing lobbies on a bad connection raised the input delay for the players.

## The deadlock I built, which is the most useful thing here

Finding 3 said a departure is not turn-synchronised, and suggested: the relay decides "B is
dropped as of turn T" and broadcasts that as a turn-stream event.

**Built it exactly that way and it deadlocks.** A peer waiting for B is STALLED. Its clock is
frozen - that is what a stall IS - so it can never reach turn T to be released by it. Measured:
the survivor ran 227 turns and stopped.

> The order that unblocks the turn stream cannot ride the turn stream.

The version that works is the relay **speaking for** the departed: an empty word every turn,
for as long as the match lasts, which is the truth about a player who has gone. Nothing has to
agree on a cut-off turn because there is not one, and the expectation set never changes, so the
two ENet channels that used to race cannot. Survivor: 1002 turns, 0 desyncs, erase applied.

That fix then needed a second one, and finding out why is the same lesson twice: a peer that is
connected but WEDGED stays in `multiplayer.get_peers()` for ever, so the relay would never have
started speaking for it. The new lag-out would have ended one freeze by starting a permanent
one.

## The jitter margin, measured properly

Finding 7 said the delay was dominated by its own padding: ENet's full round-trip variance
added to a half round trip, doubled across both legs, then a flat 20 ms on top - jitter counted
three times.

Counting it once changed almost nothing (137/125/117 ms against 117/131), **which is the useful
result**: the flat margin was not the dominant term, the variance is.

So the margin was measured rather than guessed - and that needed a number nobody had. A stall
COUNT cannot tell six invisible hitches from six visible freezes, and every earlier attempt to
tune this traded latency against a count without knowing what the count cost. `LockstepService`
now tracks total held time.

Paired alternating runs, rented server, 26 ms ping, ~50 s played per run:

| `jitter_margin_ms` | median latency | total held, both peers |
| --- | --- | --- |
| 0 | **85 ms** | 2.10 s |
| 20 | 131 ms | 1.25 s |

Twenty bought 0.85 s less holding per match - half a dozen stalls of one or two ticks each,
well under the 0.6 s the stall panel waits before it appears - and charged 46 ms on every
single order. Invisible benefit, felt cost. So zero.

**Honest limit:** the within-config spread is large - 62 to 102 ms for the SAME config - so
only the extremes are resolvable here. That is why the answer is 0 or 20 rather than 8 or 12,
and it is consistent with [2026-09-04-input-delay.md](2026-09-04-input-delay.md)'s finding that
a single median on this link cannot resolve under about 35 ms.

## Everything else closed

- **Turn numbers are validated** at the relay and at each peer. A client cannot lie about WHO
  it is - the slot is stamped - but it could lie about WHEN, and one word claiming turn two
  billion poisoned `_highest_seen` so drops never applied, and gave every honest peer an
  `_incoming` entry nothing could erase.
- **The match tick is in the checksum.** It is derived from the engine frame with held time
  subtracted rather than from the turn, so the invariant held by construction and was checked
  by nothing while driving creep unlocks and Sudden Death. It holds - verified with stalls on
  both peers so the pause correction was exercised.
- **The relay is batched**: one message per peer per channel instead of `2*N^2` packets a tick.
  Reliable and unreliable stay separate, because the channel is the entire point of the
  redundancy. Flushed on the render frame, so nothing waits a 50 ms tick.
- **The checksum accumulates numbers, not strings** (`WorldDigest`), which also removes the
  last of the quantisation - health, cooldowns, construction progress, aura fields and mana
  were all still rounded to a thousandth. Verified both ways: worlds agree EXACTLY across 457
  turns with no rounding, and a planted divergence is still caught.
- **The turn stream is recorded** into the session log, with input hashes kept separately from
  state hashes. Inputs matching while states diverge is a simulation bug; inputs diverging is a
  network one, and those were previously indistinguishable.
- **A stall has a ceiling.** The relay gives up on a player who is connected and silent.
- `TargetFinder` ties break on `unit_id`, which its own docstring asked for BEFORE anything
  reorders `PlayerArea._creeps` - and the spatial hash under known weaknesses is exactly that.
- `Command.tick` no longer crosses the wire.

## Regression, all four scenarios

| Scenario | Result |
| --- | --- |
| plain 1v1 | 461 turns both, 46 orders, 0 desyncs, 0.85 s held |
| a peer hard-killed mid-match | survivor 1002 turns, 0 desyncs, 23 units erased |
| a third peer connects mid-match | 961 turns both, identical, 0 desyncs, 0.85 s held |
| a planted desync | caught, both players told |

## What is still open

- **Cross-machine determinism is still untested.** Both clients in every run share a binary and
  a libm. This is the largest untested assumption in the system and needs a second machine.
- **Redundancy under real packet loss.** Proven to carry the data by running a match with the
  reliable path disabled; never tested against actual loss.
- **`inject()`'s lead is a margin, not a guarantee.** Nobody waits for the relay, so a system
  order could in principle be applied by one peer and refused by another. A second of lead on
  an in-flight reliable packet is ~20x over, and the checksum catches a miss.
- **Majority-vote desync attribution** at 12 players. Meaningless at two and the twelve-player
  case is blocked on the per-unit cost anyway.
- **The relay could enforce a floor on how far ahead a peer books**, so a modified client cannot
  take a reaction-time edge by choosing `min_delay_turns` on a bad link.
- **`Scripts/Dev/LockstepProbe.gd` is still autoloaded.** Left in place deliberately: removing
  it edits `[autoload]` in `project.godot`, which `CLAUDE.md` forbids while the editor is open,
  and the editor was open.
- **The per-unit simulation cost**, unchanged and still what limits player count.

## Traps

**A transport's peer list is not a match roster.** Three findings were one mistake wearing
three hats. `multiplayer.get_peers()` answers "who is connected to this process" and every call
site wanted "who is in this match".

**The thing that unblocks a queue cannot travel through it.** Worth holding onto beyond
lockstep: any release mechanism carried by the channel it releases will deadlock.

**A stall count is not a stall cost.** Two configurations with the same count can differ by an
order of magnitude in held time, and every tuning decision made against the count alone was
made blind.

**PowerShell's `Set-Content -Encoding utf8` writes a BOM** into a `.tres`, which shows as an
invisible one-line diff. Already recorded on 2026-09-04 and hit again; `git checkout` restores
it rather than rewriting.
