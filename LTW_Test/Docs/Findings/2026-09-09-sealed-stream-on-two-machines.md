# The sealed stream on two real machines

**2026-09-09.** Four playtests in one morning, on a desktop and an old laptop against the rented
relay. The first two answered the question this project had never asked; the third failed for a
reason worth keeping; the fourth is the one the whole netcode rework was built to produce.

Builds `79742d9` (legacy) and `14b931a` (sealed). Both players' session logs captured every time.

## The headline

**A peer that hitches no longer freezes anybody else, and the machine that hitches pays for it
alone.** Same two PCs, same link, same afternoon, flag flipped between runs:

| | legacy (playtest 3) | sealed (playtest 5) |
| --- | --- | --- |
| desktop stalls | 7 | **1** |
| **desktop world frozen** | **5.80 s** | **1.15 s** |
| laptop stalls | 11 | 2 |
| laptop world frozen | 2.15 s | 1.35 s |

The desktop's 1.15 s is **entirely the match-start stall** — it is flat at 1.15 s from turn 0 to
turn 1000, and the log carries exactly one `lockstep.stalled` entry. After the match opens, the
healthy machine never stops again.

Under the old gate it lost 5.8 s to a partner that was merely slower than it. That is the coupling
this rework exists to remove, and it is now removed on hardware rather than in a synthetic test.

## What it costs the slow machine, which is the other half of the design

| | input delay p50 | p90 | max | samples |
| --- | --- | --- | --- | --- |
| desktop | **105 ms** | 124 ms | 160 ms | 24 |
| laptop | **300 ms** | 317 ms | 322 ms | 33 |

`order.ran waited_ms` — wall clock from the press to the world acting on it, which is the one
number that says whether any of this feels right.

**The asymmetry IS the design.** The tester's own report — "worked, but high delay on the laptop,
PC went very smooth, no noticeable lag" — matches the logs exactly, which is worth noting given
that playtest 1's report matched nothing and was diagnosed wrongly twice.

## Determinism across two machines, which had never been checked

**91 checksum turns compared between the two logs, zero mismatches** (128 in the legacy run, also
zero). Two different CPUs, a real internet link, and every compared turn agreed.

This was the largest untested assumption in the system — `DeterminismBench`'s own docstring says it
cannot catch cross-machine float divergence, because it only ever had one machine. It is now
evidence rather than hope, and everything built on lockstep rests on it.

**Stated as a comparison count rather than as an absence of errors**, deliberately: 91 comparisons
happened. "No desync was logged" would have been equally true of a comparison that never ran.

## Where the laptop's delay actually comes from, to the tick

The interesting part is not the size of the gap but its shape. The laptop's backlog:

```
turn:   0   100  200  300  400  500  600  700  800  900
held:   0    4    4    4    4    4    4    4    3    4
```

It reaches 4 and **stays there for 835 turns**, dipping to 3 once. It does not accumulate.

And the log says exactly where it came from:

- `lockstep.stalled { turn: 0 }` — match start, shared with the desktop
- `lockstep.stalled { turn: 65 }` — one hiccup, and `stalled_s` moves 1.15 → 1.35 s

**0.20 s is four turns at 20 Hz.** One 200 ms stall at turn 65 became 200 ms of input delay that
the laptop then carried for the rest of the match. The 195 ms gap between 300 ms and 105 ms is
that stall, still being paid eight hundred turns later.

That is amendment 10 caught in the act, and it reframes phase 6 — see below.

## `missing: [1]` on both machines

Amendment 11 doing its job: every stall under the sealed stream names the SERVER. Under the legacy
run the same field named the other player, which was true then and is what makes the two logs
distinguishable at a glance.

It also happens to be the field that diagnosed playtest 4, below.

## Playtest 4: the run that deadlocked, and why the guard could not see it

The first sealed attempt froze both players on turn 0 and was reported as "game was paused, not
playable". Nothing was broken.

The flag lives in a `.tres`, so it landed on the **relay** when the server was deployed and did not
land on the **clients**, which were still on the previous build. The relay therefore refused every
turn word (`submit_turn` returns early under the flag) while the clients ignored every seal, and
each peer sat waiting for the other.

Three pieces of evidence agreed and cost one command: the build stamp said `79742d9` on both
clients while the flag went in at `fd92db5`, and `missing` named the other PLAYER rather than
peer 1 — which under the sealed stream it never does.

**The handshake had two guards and neither could see it.** `protocol_version` is a number somebody
remembers to raise. `rpc_signature()` is computed from the code and exists to catch a build that
was edited and not deployed. Both passed, because the code really was identical on both sides —
**what differed was a config value that changes what the protocol MEANS without changing what it
looks like.**

Fixed in `14b931a`: the handshake now states `wire_config()` as well, kept separate from the
signature because it answers a different question and deserves its own message —

> The server and this game disagree about how the match is run (server sealed=1, game sealed=0).
> Update the game, or redeploy the server.

Proved by booting a server with the flag on, flipping the file, and connecting a client that reads
the opposite. Refused, on both sides, with that text.

## Traps

**A CONFIG VALUE CAN BE PART OF THE PROTOCOL.** The rule that used to be enough — "the code is the
same, so the wire is the same" — stops being true the moment a flag changes wire behaviour. Anything
that gates an rpc's meaning belongs in the handshake beside the version number, not in a `.tres`
that two machines can hold different copies of.

**A `.tres` DOES NOT CARRY A VALUE EQUAL TO ITS SCRIPT DEFAULT.** `sealed_stream` could not be found
in `network_config.tres` by searching for it, because Godot strips a property that matches the
script's default when it saves. The line only appears once the value differs. A reader looking for a
flag and not finding it may be looking at a file where it is simply absent, not at the wrong file.

**FLIPPING A NETCODE FLAG IS A THREE-MACHINE OPERATION.** Both clients and the relay. Deploying the
server without rebuilding the clients is the natural order to do it in and is exactly what breaks.

**PREDICTING THE FAILURE IS NOT THE SAME AS MAKING IT LOUD.** This exact deadlock was written into
the code comments in advance, described there as "loud rather than silent" because both peers stall
at turn 0 and say so. They did say so — in a session log nobody reads during a playtest. What the
player saw was a frozen game. A failure is only loud if it is loud where somebody is looking.

## What this does NOT establish

**Both machines are on one home connection.** Their round trips to the relay are real internet
figures (31-36 ms and 40-46 ms settled) rather than LAN, so the link is genuine — but the two are
correlated, and nothing here says what happens when two players' connections differ a lot or one
degrades independently. The sealed stream is what makes that matter far less than it used to, since
peers no longer wait for each other, but it is untested.

**One match, about a minute of play, two players.** Nothing here says anything about a long match,
about twelve lanes, or about what a real leak-heavy endgame does to a struggling machine.

**Clock drift is still unmeasured.** The laptop's lead was flat, which is evidence against drift on
this pair — but a minute is short, and a stable lead is also what a drift-free pair with one banked
stall looks like. A long run is what would separate them.

## What it changes

The phase 6 plan (`netcode-rework.md` section 13) was written before this run and is built around a
lead that grows without bound. **It does not grow.** Section 13.7 lists that exact outcome as an
abandon condition, and half of it is now met.

What is left is smaller and much better defined: **one machine banked 200 ms at a single hiccup and
has no way to give it back.** The plan's own note at 13.7 carries the reframing.
