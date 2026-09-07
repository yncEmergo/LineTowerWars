# Netcode rework: one lagging player must not stop the game for anybody else

**Written 2026-09-07 for an agent starting fresh tomorrow.** You have none of the context that
produced this. Everything you need is here or is linked from here. Read sections 0 to 4 before
touching anything; they are short and they are the difference between fixing this and making it
worse.

This is a PLAN, not a record. When a phase lands, move what it built into `multiplayer.md` and
strike it here.

---

## 0. Orientation, if you have never seen this project

A standalone 3D remake of the Warcraft III custom map **Line Tower Wars**: a PvP tower defence
for 2-12 players where each player defends their own lane and spends gold to send creeps into
everyone else's. Godot 4.7, GDScript. The only milestone that matters right now is a **1v1
prototype**.

Read, in this order:

1. `../CLAUDE.md` — the hard rules. It is loaded automatically, but read it deliberately.
   The ones that bind this work are quoted in section 9 below.
2. `multiplayer.md` — what the networked build IS, and the numbered decision log (D1, D2, …).
   Section 11.4 is input delay.
3. `Findings/2026-09-06-playtest-1-freezes.md` — the playtest that started this.
4. `server.md` — how to start, stop and aim the dedicated server.

**Three rules that will bite you in this work specifically:**

- **NO PHYSICS ENGINE.** Every gameplay result is plain maths.
- **ONLY THE AUTHORITY SIMULATES.** Under lockstep every peer is an authority for the shared
  simulation, but no peer may simulate ahead of the agreed turn.
- **An `@rpc` endpoint must be an autoload.** Godot routes rpcs by node path, and the client's
  match scene root is `/root/Main` while the server's is `/root/ServerMatch`.

---

## 1. The problem, in one paragraph

The game is deterministic lockstep. Every peer emits a "turn word" for every turn, and a peer may
only simulate turn N once it holds a word for turn N **from every other player**. When a word is
late, the peer calls `MatchSession.hold(&"lockstep")`, which pauses the entire scene tree. So a
hitch on ONE machine — a network blip, a frame that ran long, a scene loading on first use —
freezes the world for EVERY player, and it stays frozen until either the word arrives or the
relay gives up on that player eight seconds later.

**The owner's requirement, stated verbatim:** *"There should be no pause or any issue for any
player except the lagging one."*

That is achievable, it is what shipping games do, and it does not require rollback.

---

## 2. The evidence that this is architectural, not a bad connection

From `Findings/2026-09-06-playtest-1-freezes.md`, a real two-player match on the rented EU server
on 2026-09-06:

- The link was **clean**: round trip p50 31 ms (host) and 20 ms (guest), variance p90 4-5 ms.
- The input delay sat at its floor, one turn, in 96/99 and 120/124 samples.
- **There were 60 stalls on one side and 210 on the other, in a single ten-minute match.**
- Five of those were freezes of 0.65-0.9 s. In all five the host was on time to within 10 ms and
  was doing nothing but waiting; the guest's machine was loading content on first use.

The content-loading cause is fixed (D36, content is warmed on the load screen now). **The
coupling that turned one machine's hitch into everyone's freeze is not.** 270 stalls on a link
with 4 ms of jitter is not a network problem. It is the gate.

---

## 3. What the research established

Seven agents on primary sources, plus three auditing this codebase. Full per-agent output is in
the workflow transcript; what follows is the load-bearing part, with quotes.

### The central finding: three shipping codebases do not wait

**Factorio**, FFF-302, under the heading *Skipped ticks*:

> "When the server decides what Input Actions will be executed in what game tick, if it does not
> have the Input Actions of a certain player (e.g. because of a lag spike), it will not wait, but
> instead tell that client 'I did not include your Input Actions, I will try to include them in
> the next tick'. This is so when a client has connection problems (or computer problems), they
> will not slow down the map update for everyone. **Note that Input Actions are never ignored,
> they are only delayed.**"

Note the parenthetical — *"or computer problems"* — which is exactly our playtest's cause. The
shipped promise, from the Factorio 0.14.0 changelog:

> "Server doesn't stop/slow down the game when some client is too slow, stops communicating or
> saves the game longer than the server."

And the rationale, FFF-147:

> "the server can safely omit a player from the package if he has a lag spike, so the lag spike is
> isolated from the rest of the game. This is not possible in the peer to peer model."

### The client does not name the turn — the server does

This was the owner's own hypothesis and it is literally implemented in three codebases:

- **Factorio**, FFF-302: *"The server's main responsibility is proxying Input Actions and making
  sure all clients execute the same actions in the same tick."*
- **OpenTTD**, in the client source: `c.frame = 0; // The client can't tell which frame, so just
  make it 0`, with the server stamping `cp.frame = _frame_counter_max + 1;`.
- **Warcraft III**: the client's GameAction packet carries no turn number. *"The server includes
  this data in its next Tick packet, broadcast to all the clients. Clients don't perform an action
  until it shows up in the Tick packet."*
- **Spring/Recoil** goes furthest: `NETMSG_COMMAND` carries no frame field at all, and the
  server's handler is an ownership check plus `Broadcast(packet); //forward data`. The tick is
  defined purely by position in the stream.

### The peer-gated design couples everyone, and its authors said so

**Age of Empires**, GDC 2001 (Bettner & Terrano) — this is our exact measured symptom, described
twenty-five years ago:

> "If one machine's frame rate drops (or is lower than the rest) the other machines will process
> their commands, render all of the allocated time, and end up waiting for the next turn — even
> tiny stops are immediately noticeable."

and

> "the game can really only run as fast as the slowest machine can process the communications,
> render the turn, and send out new commands"

Baughman & Levine prove the general case formally: *"the game and all players will run at the
speed of the slowest player."*

### Shared worst-case latency is a known defect

Factorio FFF-147 lists among its reasons for abandoning peer-to-peer: *"Everyone needs to have the
same latency."* and *"No defence from lag spikes of individual players."* Its replacement is
per-client: *"The server tries to guess what's the roundtrip delay between the client and the
server, for each client. Every 5 seconds it will negotiate a new latency with the client."*

Photon Quantum states the resulting invariant plainly: *"if one client has a bad connection only
their own experience will be affected and everyone else's will stay smooth."*

### But per-client latency has a competitive cost, and Factorio declined to pay it

FFF-147, and this is the one place we cannot copy Factorio without thinking:

> "An implication of this would be, that the server would have 0 latency, this would be unfair in
> a competitive game, but in Factorio, there is no reason to drag everyone down just to make it
> fair."

Line Tower Wars is 1v1 PvP. See section 7.

### An empty substituted input is not automatically safe — but it is safe HERE

Photon Quantum draws the line exactly where we need it. Its `Repeatable` flag *"should be used on
direct-control-like input such as movement; it is not meant for command-like input (e.g. buy
item)"*, and its Commands channel is *"fully reliable… regardless of the time at which they are
sent"*, with the sender unable to *"predict the tick in which the command is received by the
simulation"*. Factorio has to inject a synthetic `StopMovementInTheNextTick` when substitution
fires, *"to prevent your character from running by himself (e.g. in front of a train)"*.

**Every Line Tower Wars order is command-shaped** — build, sell, upgrade, send, research. There is
no continuous per-tick input in this game at all.

**This was verified rather than assumed, on 2026-09-07.** `repeat_on_hold` is driven entirely by
the UI: `UnitPanel._begin_hold` (`Scripts/UI/UnitPanel.gd:1059`) re-submits a discrete order per
repeat, and the simulation carries no "held" state between turns. So an empty turn genuinely means
"this player did nothing", and no synthetic stop order is needed. **If anything ever adds a
continuous input, this conclusion has to be re-checked.**

### Latency hiding without rollback is a shipped, bounded thing

Factorio FFF-83:

> "Every tick this latency state is cleared and initialized from the regular game state. Then all
> the buffered local user actions that hasn't been applied yet in the game state are applied to
> the latency state."

and decisively:

> "There is no state correction or anything."

Its scope is deliberately narrow — Factorio hides selection, GUI, building and mining, and refuses
to hide combat.

### A jitter buffer beats a tight gate

Recoil's own source comments, which are the strongest statement of it found:

> "we \*NEVER\* want the queue to run completely dry (by not keeping a few messages buffered)
> because this leads to micro-stutter which is WORSE than trading latency for smoothness (by
> trailing some extra number of simframes behind the server)."

Their default buffer is 3-6 simulation frames on top of normal ping. Ensemble agree from the other
direction: *"a consistent 500 msec command latency was playable, but one that varied was
considered 'jerky' and hard to use."*

### The direct answer to "why did mixed pings feel fine in Warcraft III?"

The owner's report was: on an EU host, playing alongside players from the US, Singapore and Korea
at up to 400 ping, they felt no delay beyond their own ~30 ping — no difference between an all-EU
lobby and a worldwide one. That report is **accurate, and the mechanism is now understood.**

**Warcraft III: a distant player does NOT raise your input delay.** The turn interval is a single
fixed constant — Blizzard set it globally for all realms, a bot host sets it once per game
(GHost++ defaults to 100 ms), and **nothing in the protocol or in any implementation read computes
it from any player's ping.** There is no per-peer budget, no worst-one-way announcement, no
adaptive term. What a player experiences is *their own round trip to the host, plus the fixed turn
interval.* The 400-ping player contributes nothing to either and pays their own 400 ms alone.

What a distant player DOES cost everyone is **stall risk, not delay**. Their acknowledgements
arrive later every turn, permanently consuming part of the host's slack. While they stay inside
it, nobody notices. When they exceed it, the host raises `PlayersLagging` and everyone freezes. So
in WC3 a bad player degrades the lobby in **discrete freezes, never in continuously worse
responsiveness.**

**StarCraft: Remastered does the opposite, and it is what our system does.** Turn Rate is one
number for the whole game; Grant Davies (Blizzard) gives the formula as
`MaxLatencyPermitted = 1000 * (UserDelay + 1) / TR` evaluated against *"the latency to my
opponent"*, and Blizzard say outright that *"StarCraft uses a networking algorithm that is optimal
when all players have good connectivity to all other players"*. The worst link in the lobby sets
the turn rate, and dropping from TR24 to TR8 stretches the turn for **every** player. In SC:R the
distant player absolutely does slow your clicks down.

**Our system behaves like SC:R and the owner expected WC3.** That is the whole of the latency
complaint, and section 5 removes it: once the client stops naming the turn, there is no
`worst_one_way` term to pay.

### A correction to our own documents

**The widely-quoted Warcraft III line *"The artificial latency on all Battle.net realms has been
reduced from 250ms to 100ms"* is NOT a Blizzard statement.** The archived 1.28.4 thread was read
directly. Pete Stilwell's official note says only *"Game turn rate adjusted to match LAN settings
of 12 turns per second"*. A user asked about 250→100 and Stilwell confirmed the *mechanism*
without ever restating the numbers. The "250 ms → 100 ms" phrasing comes from wikis and the
community. Note also that 12 turns/second is 83.3 ms, not 100 ms, and the `.w3g` replay format
spec independently says *"~250 ms in battle.net, ~100 ms in LAN and single player"*. The three
figures do not reconcile and no source reconciling them was found.

**Treat "250 → 100" as approximately right in effect and unsourced as a literal quotation.**
`multiplayer.md` §11.4 has been corrected. `Findings/2026-09-04-input-delay.md` still carries the
misattribution and has deliberately NOT been edited, because a finding is a dated record and the
convention in `Findings/README.md` forbids rewriting one after the day it was written. **This
paragraph is the correction of record.**

Also not verified, and therefore not relied on anywhere in this plan: any primary description of
StarCraft II's network model; stock WC3's own sync limit (the ~5 s figure is GHost++'s
configurable default, not Blizzard's); and any Blizzard latency-hiding mechanism — none was found
in any Blizzard source.

### The formal names, so this is searchable later

What section 5 describes is a **fixed-sequencer total-order broadcast**, variant "unicast to
sequencer, broadcast from sequencer" (Défago / Schiper / Urbán). The determinism argument is
**state-machine replication** (Schneider 1990): *"Outputs of a state machine are completely
determined by the sequence of requests it processes, independent of time and any other activity in
a system"*, given *Agreement* and *Order*. Our existing `_speak_for_the_departed` is a
**Chandy/Misra/Bryant null message**.

Search terms that primary sources actually use: *skipped ticks*, *input hard tolerance*, *tick
closure*, *latency state*, *communications turn*. Terms that return nothing useful:
*server-authoritative input scheduling*, *tick arbitration*.

---

## 4. What is actually wrong in the code

Every line reference below was verified by hand on 2026-09-07. All paths are from the project
root.

### The whole bug is one predicate

`Scripts/Multiplayer/LockstepService.gd:674` — `_is_complete(turn)` walks `_expected_peers()` and
returns false unless **every** player has an entry in `_incoming[turn]`. `_expected_peers()`
(`:1384`) is the match roster and includes every other player.

So one missing word fails the test on *every* machine at once. `_advance_turn` (`:332`) sets
`_stalling` and calls `_set_held(true)` (`:693`), which calls `MatchSession.hold(&"lockstep")`,
which sets `tree.paused`. **The entire scene tree, on every machine, for one player's hitch.**

### Everything else is scaffolding around that predicate

| Where | What it does, and why it goes |
| --- | --- |
| `LockstepService.gd:299` | The **client** schedules its own orders, via `_close_through(turn + delay_turns())`. |
| `:788` | `scheduled_turn()` is `_closed_through + 1`, so the real booking is `current_turn + delay_turns + 1` — one turn more than it looks. |
| `:941` | `_close_through` emits a word for every turn, so **every peer must speak every turn**. That is what gives a turn N ways to be late. |
| `:972` | `_emit` records the peer's own word locally so the author does not wait a round trip. Correct today. **The single most dangerous line to leave in place after the change.** |
| `:1011` | `submit_turn` stamps the sender's slot and **forwards each peer's word verbatim**. The merge then happens independently on N machines (`commands_for`, `:879`), which is the only reason the sort-by-peer-id exists. |
| `:423` | `_wire_budget_ms` is where the worst-peer latency coupling lives: `own_one_way + worst_one_way + variance + margins`. |
| `:484` | `_speak_for_the_departed` exists solely to keep an absent peer's slot filled so the gate can close. |
| `:506` | The 8 s `silent_timeout_seconds` is the **only** ceiling on a stall, and it lives only on the relay. |
| `:1062` | `inject()` is an existing prototype of relay-assigned turns (for PLAYER_LEFT) and its own docstring admits it is unsound: *"SYSTEM_LEAD_TURNS is a margin, not a guarantee"*. |
| `:1327` | A word for an already-run turn is dropped by a bare `return`. Silent divergence. |
| `:1494` | `_forget_old_turns` discards checksums older than `checksum_every * 4` — at the authored value, about two seconds. **Any peer more than two seconds behind is silently never compared to anybody.** Must be widened before peers can legitimately be seconds apart. |

### The blocker that must be fixed before anything else is safe

`MatchSession.tick()` (`Scripts/Game/MatchSession.gd:221`) is `Engine.get_physics_frames() -
_start_frame`, with held time refunded. It is hashed into every checksum
(`Scripts/Game/WorldChecksum.gd:80`) and it drives creep unlocks, income, research completion and
Sudden Death.

The comment already in `WorldChecksum.gd:73` names the exposure honestly:

> "the tick equals the turn minus whatever this peer paused for is an invariant that holds by
> construction and was never checked"

**It holds today only because every peer pauses for the same turns — which is exactly what this
change stops being true.** The clock must become turn-derived first. That is phase 1.

Two smaller things, both real: `Creep.gd:1144` reads `Engine.physics_ticks_per_second` directly,
as does `MatchSession.gd:352`. And `Scripts/Dev/LockstepProbe.gd` still exists despite CLAUDE.md
saying it is gone — it is inert (not in `[autoload]`) but it hooks signals this change moves.

---

## 5. The design

Name it **the sealed turn stream**. The relay stops forwarding each peer's word and instead
*seals* one authoritative turn per tick, on its own clock, from whatever has arrived.

### The three moving parts

**1. The relay owns the clock.** It already does `_frames += 1` every physics tick (`:278`) and it
never stalls. On each tick it seals turn `_frames`: take the orders received since the last seal,
rewrite each order's `slot` from the roster (`_stamped` / `_slot_of_peer`, **unchanged**), sort by
`(slot, seq)`, append any server order due, freeze it, and broadcast one message to every peer
**including the authors**. An empty turn is sealed and sent like any other; that is the heartbeat.

> Keep the slot stamping exactly as it is. It is the only defence against a forged slot, and a
> forged slot does **not** desync — every peer would apply the same forged order and agree
> perfectly about a maze somebody else paid for. No checksum can catch it.

**2. Clients send bare orders.** `Commands.submit` rpcs the order at press time on the render
frame, with a client-local monotonic `seq` and **no turn number**. `Command.to_dict()` already
carries no turn field, so nothing on the wire changes shape. The relay dedupes on `(peer, seq)`
with a high-water mark, which is sufficient because client→relay orders go on the reliable ordered
channel only.

**3. Peers play the stream back through a jitter buffer.** Each peer targets a lead `L` measured
in **milliseconds of observed arrival time**, not in turns and not derived from anybody's ping.
When it holds `_last_run_turn + 1` it runs it; when it does not, it holds — **alone**.

`_is_complete` goes from *"do I hold a word from every peer"* to *"do I hold the relay's word"*.
**No other player ever appears in your wait condition again.** That is the entire fix.

### What this deletes for free

The 8 s silent-timeout freeze; the `SYSTEM_LEAD_TURNS` divergence hazard; the `worst_one_way`
latency tax; the client-side `_plausible_turn` look-ahead cheat surface; `_speak_for_the_departed`;
and the client-side merge sort in `commands_for`.

### Five amendments that are not optional

An adversarial correctness pass found a real flaw in the naive version. Amendments 1-3 are
load-bearing.

1. **Delete the peer-side turn plausibility ceiling.** As first specified, a peer far enough behind
   would refuse the very sealed turns it is starving for, stall permanently, and — because
   `_beat()` runs above the stall (`:292`, deliberately) — keep telling the relay it is alive, so
   it is never dropped. **That is this project's own hard-won lesson repeating: the thing that
   unblocks a queue cannot be refused at the door.** `_plausible_turn` exists to stop a *client*
   lying about a turn; under this design no client names a turn, so the only sender is the
   authority and the peer must accept anything it sends. Bound memory by buffer *size* instead,
   and treat overflow as an explicit "you are hopelessly behind" end state with a message.
2. **Make the heartbeat the lag telemetry.** `submit_alive(turn)` already reaches the relay and
   `_reported_turn` is already stored (`:1232`), read today by exactly one log line. Compute
   `lag = sealed_turn - reported_turn` per peer, warn the lagging peer **alone**, and drop past a
   threshold with a reason. This inverts today's trap — where the heartbeat *prevents* the drop
   that would have unblocked everyone — into the mechanism that ends a hopeless session cleanly.
3. **Do not gate catch-up on the peer being CPU-healthy.** The obvious design disables catch-up
   when the machine's own tick time exceeds some fraction of budget, i.e. precisely when it is
   needed. CLAUDE.md already records that twelve lanes is about 2x over the tick budget, so that
   state is reachable. A peer that cannot sustain the tick rate cannot play the match: say so and
   end it, do not wedge it.
4. **Tell the player.** `notify_lagging` so only the affected player's UI says anything,
   `notify_dropped(reason)`, and a three-state stall panel that only ever describes the local
   machine. Today a dropped player watches their own maze vanish with no explanation, and nothing
   in the project listens to `MatchStart.player_dropped`. This would be the first time a dropped
   player is told why.
5. **Do not forget the delta refactor.** The engine-rate servo in phase 6 needs roughly fourteen
   gameplay `_physics_process(delta)` loops to stop consuming the engine delta. It is deferred,
   but it must not be lost.

### Two things deliberately rejected

A variant that seals only up to the highest turn any peer has reported makes the relay's tempo
**peer-derived** — so a correlated hitch (both peers first-loading the same content on the same
turn, which is the symmetric-game shape of our measured cause) still stops the stream for
everyone. And a "seal grace" that holds every turn open briefly for a late peer lets a chronically
late opponent pace the innocent player's world. Neither is taken.

---

## 6. The determinism argument, spelled out

The world after turn N is `f(rng_seed, MatchSetup, turns[0..N])`. Five invariants close it.

**I1 — Single authorship.** Exactly one machine composes a turn's contents, exactly once. Today N
machines each merge N per-peer streams and rely on a sort to agree; that argument is sound but it
is an *argument*, and it must stay sound across every future edit. Here there is nothing to argue
about. (Schneider's *Agreement*.)

**I2 — Immutability and total order.** A sealed turn is closed forever, so "what is in turn N" has
exactly one answer for all time. `(slot, seq)` is a total key and a pure function of the member
set, so ordering does not depend on arrival races even at the relay. (Schneider's *Order*.)

**I3 — Strict sequential consumption, one turn = one world tick.** A peer runs
`_last_run_turn + 1` only, exactly once, never skipping a gap. Two peers seconds apart in wall
clock have applied an identical sequence to an identical initial state.

**I4 — No wall clock, no engine rate, no network state inside the simulation.** This is the
invariant the current code *assumes* and does not *enforce*, and it is the genuinely risky half.
`MatchSession.tick()` becomes the turn counter, which turns the unchecked invariant at
`WorldChecksum.gd:73` into an identity. Before the servo ships, `tick_seconds()`
(`MatchSession.gd:352`) and `Creep._aura_phase` (`Creep.gd:1144`) must stop reading
`Engine.physics_ticks_per_second`, or a peer that paces itself silently redefines what a second
means inside its own world. **And no gameplay path may ever branch on `is_stalled()`, buffer depth
or pacing rate** — those are the new variables and they are the new hazard.

**I5 — Identical starting state.** Unchanged; already validated at boot by
`Main._validate_content`.

Given I1-I5, the buffer, a starve and a catch-up burst change only *when* a peer computes turn N,
never *what* it computes.

### What would break it, most likely first

1. **Leaving the local self-record at `:972` in place while the gate is sealed.** No stall, no
   error, caught only at the next checksum. **It must move in the same commit as the gate flip.**
2. Missing a call site in the delta refactor — behaves identically at a fixed rate and wrongly only
   during a fast-forward.
3. The relay sending different bytes to different peers. Concretely: keeping `_queue`'s
   `skip = sender` optimisation (`:1149`), which stops being a saving and becomes a divergence.
4. A non-total sort key.
5. `randf()` where `MatchSession.match_rng()` belongs. Unchanged risk, still the likeliest desync
   in the codebase, still caught first because the RNG state is in the checksum.

---

## 7. What it costs, honestly

**The local player pays their own round trip on their own clicks, where today they pay none.**
This is the deliberate trade and it is unavoidable once the client stops naming the turn. Against
the measured links it roughly washes against today's `own + worst`; against the *best case* of the
current configuration it is a small regression. But that configuration is the one that produced
270 stalls in a match, and unlike an integer `delay_turns` the lead is continuously tunable.
**Presentation feedback is therefore a prerequisite, not a follow-up.** It is phase 2.

**A mean half-tick seal wait is added** and is irreducible at the current seal rate. An order
arriving just after a seal waits nearly a full turn.

**The relay becomes the single point of tempo.** Its physics tick is now the match's pace for
everybody, and `Findings/2026-09-03-server-tick-overrun.md` establishes it can overrun. Factorio
shipped exactly this bug ("Slow server = no input on client") and it stood for years. The
mitigation is that it is one headless machine we rent, control and can instrument — **log the seal
interval from day one.**

**Without catch-up (phases 1-4), a network-only hitch leaves that peer permanently trailing.**
Godot's accumulator recovers frame-time debt for free up to `max_physics_steps_per_frame`, but a
lost-packet gap is not frame-time debt. This is a real cost of the phasing and it is why phase 6
exists.

**Clock drift between relay and peer is unhandled without the servo.** A peer whose clock runs
fast starves periodically; one whose clock runs slow accumulates latency. Both are private to that
peer. **The magnitude must be measured** — phase 0 measures it, and if it is small the servo is
not urgent.

**Per-client latency is a competitive asymmetry.** The player nearer the relay clicks sooner.
Default it off for the prototype (the lanes are parallel; nobody dodges your click). The important
structural point is that **latency coupling and stall coupling become separable** — a common
latency floor can be restored for ranked without restoring the gate. Today they are welded
together.

**Order traffic changes shape.** Orders arrive unbatched, so a `repeat_on_hold` flood lands at
once. Needs a client-side coalescer and a relay-side cap. OpenTTD's precedent is two commands per
client per frame with a kick at sixteen queued.

---

## 8. The plan

Each phase is independently landable and independently falsifiable. **Do not skip phase 0 or 1.**

### Phase 0 — Instrument arrival time. No behaviour change.

Record, per turn per peer, how long a word actually took to arrive **relative to when the turn was
due**, and log the distribution in `lockstep.health`. Also log relay `_frames` against each peer's
`_reported_turn` over a full match, to measure clock drift.

- *Measured:* arrival-lead distribution; `stalled_seconds()` (**duration, never count**); drift.
- *Falsifies:* if arrival lead p99 is small and stalls still happen, the network-jitter story is
  wrong and so is every budget in the file.
- Worth doing on its own merits: nothing in the codebase records this today, and that is why this
  problem was misdiagnosed twice.

### Phase 1 — Turn-derived match clock, under the current gate.

`MatchSession.tick()` becomes a counter advanced once per applied turn, skipped while a
**non-lockstep** holder is active (the technology draft holds the tree, and `LockstepService` is
`PROCESS_MODE_ALWAYS` and applies turns through it — that is how draft picks travel).

- *Measured:* under the current gate every peer pauses for identical turns, so the new counter
  **must** equal the old `tick()` at every turn on every peer. Assert it directly.
- *Falsifies:* any disagreement means the draft-hold or refund reasoning is wrong, and nothing
  after this is safe.
- This is the highest-blast-radius change and **the only moment it is cheaply falsifiable.**

### Phase 2 — Presentation feedback (`multiplayer-todo.md` §1.2).

Build ghost at the clicked cell, send stock decrementing on click, tower greying on sell. Zero
desync risk; pays for the round trip phase 4 adds. Also here: widen `_forget_old_turns` (`:1494`)
to cover the lag threshold, **before** peers can legitimately be seconds apart.

### Phase 3 — Shadow the seal.

The relay seals and broadcasts `receive_seal` **alongside** the existing `receive_batch`. Peers
ignore it and instead log what they would have merged, for offline diffing against what the relay
sealed.

- *Measured:* zero disagreements over a full match.
- *Falsifies:* any ordering or dedupe difference — caught here, with both formats on the wire and
  nothing depending on the new one.
- This step is free and it is the one that de-risks the cutover.

### Phase 4 — The cutover.

Bump `protocol_version` 2→3 so a stale tester build refuses rather than deadlocks.

Flip the gate to `_sealed.has(turn)`, **delete the local self-record at `:972` in the same
commit**, and delete `_speak_for_the_departed`, `SYSTEM_LEAD_TURNS`, the
`delay_turns` / `_wire_budget_ms` / `announce_one_way` chain, and the client-side
`_plausible_turn`. Add `seq` dedupe, `(slot, seq)` sort, order caps, `notify_lagging` /
`notify_dropped`, the relay-side lag drop, and the three-state stall panel.

Rebuild the dev probe from the scenario list in
`Findings/2026-09-05-lockstep-review-2-response.md` — plain 1v1, a peer hard-killed mid-match, **a
third peer connecting mid-match** (the case no obvious test topology contains), a planted desync —
plus a new one: **one peer given a deliberate ~900 ms freeze.**

- *Measured, paired, same commit, alternating runs on the rented server:* the healthy peer's
  `stalled_seconds()` while the other is deliberately hitched. **That asymmetry IS the design.**
- *Falsifies:* if both peers improve equally, the coupling was never the cause. If the healthy peer
  still stalls, the relay is the problem.
- Then delete `Scripts/Dev` and write the finding.

### Phase 5 — Decide whether the servo is needed, from phase 0's drift data.

If drift is negligible, **stop here indefinitely.**

### Phase 6 — Delta refactor, then servo, then catch-up.

Land the ~14-file refactor **alone**: every gameplay `_physics_process` stops consuming the engine
delta and uses `MatchSession.tick_seconds()`; `tick_seconds()` and `Creep._aura_phase` move to the
authored constant.

- *Measured:* provably a no-op at the fixed rate — the determinism bench
  (`Scenes/Tools/determinism_bench.tscn`, record/replay modes) must produce a byte-identical trace
  from the same seed.
- *Falsifies:* any divergence means a call site was missed.

Then prove the rate change in single player before any netcode depends on it; then the servo
(small, symmetric corrections); then catch-up capped at **+50%, not 4x** — a tower defence
fast-forwarded 4x through a leak is unreadable, and recovery must not cost the player the ability
to react.

---

## 9. What NOT to do

**Rollback, prediction, or any speculative re-simulation.** The owner ruled this out explicitly and
the recommendation agrees for now. Factorio's latency state is the shipped precedent for local
feedback without correction and is what phase 2 imitates — but note precisely what it is: it
forward-applies your own unconfirmed orders to a **scratch copy discarded every tick**, and its
authors are explicit that *"There is no state correction or anything."* Phase 2 must stay well
inside that: **draw intent, never touch simulated state.**

**Per-lane decoupling.** Baughman & Levine's *Asynchronous Synchronisation* maps onto this game's
near-independent lanes unusually well and is the right term to search if it ever matters. But the
authors themselves say *"We do not expect AS to be used to allow players with completely different
network and client resources to play together"*, and it is a far larger change. Not now.

**Turning on a fair latency floor.** Build the knob, leave it off.

**Raising the tick rate.** Gated on the per-unit simulation work in `multiplayer-todo.md` §2.1.

**Deleting the replication path.** Keep it behind `NetworkConfig.lockstep_enabled`. It is the only
honest way to compare the two under load.

**Reconnect.** This design makes it genuinely feasible for the first time — the relay holds sealed
turns and can replay them, and a returning peer needs nothing else. Worth noting in
`multiplayer-todo.md`. **Do not build it during the cutover.**

---

## 10. How to test, and the discipline that applies

- **The multiplayer test loop that works is HEADLESS AND SCRIPTED**, not the editor. Godot
  instances driven by hand cannot be made to do the same thing twice. Start the server with
  `.\Tools\run_server.ps1`, then launch clients as
  `godot --path <project> --headless -- --probe <role>`, driven from a temporary autoload under
  `Scripts/Dev` that does nothing when `--probe` is absent. **Delete `Scripts/Dev` when done.**
- **Stop and restart the server between runs.** A lobby left over from the last one looks exactly
  like a bug in the next.
- **A performance measurement is PAIRED or it is nothing.** The rented server varies about 20% run
  to run. Same commit, flip the one variable in place, alternate runs.
- **A stall COUNT is not a stall COST.** Use `Lockstep.stalled_seconds()`.
- **A negative result only counts if the test exercised the right case.**
- **NEVER edit `[autoload]` in project.godot while the Godot editor is open.** The editor holds its
  own copy of ProjectSettings and every autoload added from outside reads as "Identifier not found"
  until it restarts. Headless runs are unaffected, which is what makes it confusing.
- **A new script in an existing folder is not imported by a `godot --path` run.** Run
  `godot --path <project> --headless --import` or its `class_name` never reaches the global class
  cache.
- Git: **commit, push and deploy are allowed**, but **say what is about to land, before pushing,
  never silently**. **Never branch and never revert** — a mistake is fixed with a new commit
  forward. A deploy hard-resets the relay to `origin/main`; check for connected players first, and
  **when the deploy script says the relay is on the new commit, check the service pid, not the
  message.**

---

## 11. Traps already paid for, that this work will walk into

**THE THING THAT UNBLOCKS A QUEUE CANNOT TRAVEL THROUGH IT.** A peer stalled waiting for a
departed player has a frozen clock, so an order in the turn stream saying "stop waiting for them
from turn T" can never be reached. Built exactly that way once and watched a survivor run 227 turns
and stop. Amendment 1 in section 5 is the same bug wearing a different hat — **check every release
mechanism against this.**

**A TEST TOPOLOGY THAT NEVER DIFFERS FROM THE ASSUMPTION CANNOT FALSIFY IT.**
`multiplayer.get_peers()` answers "who is connected to this process"; nearly every call site wants
"who is in this match". They are the same number in every test that runs one server and exactly the
players — which is every test anybody writes by default. It froze every running match the moment a
third person opened the multiplayer menu.

**AN @RPC IS NOT SENT WHEN IT IS CALLED.** Godot queues it and flushes at the end of the frame, so
anything that destroys the channel in that same frame throws the packet away.

**A SHARED SYMPTOM IS NOT SHARED CAUSATION.** Under lockstep every freeze is felt by everybody, by
design. "We both froze" is the expected shape of ANY stall and carries no information about where
it came from. Ask **who was ON TIME**, not who has a gap. `lockstep.stalled` carries a `missing`
field that names the answer.

**process_priority does NOT order `_physics_process`.** Godot 4.3 split the two:
`process_physics_priority` orders the tick. An autoload that sets only the first runs before the
whole match scene.

---

## 12. Sources

Every quote in section 3 came from one of these. They were read directly on 2026-09-07, not
recalled. Where a source is second-hand it says so.

**Factorio — the closest model to what section 5 builds.**

- [FFF-302, "The multiplayer megapacket"](https://factorio.com/blog/post/fff-302) — **the single
  most important source.** Skipped ticks, per-client round-trip negotiation, Game State vs Latency
  State.
- [FFF-147, "Multiplayer rewrite"](https://factorio.com/blog/post/fff-147) — why peer-to-peer was
  abandoned; individual latency; the fairness caveat. **This is a PLAN document for 0.14 and its
  "first waits to get the actions of all players" line was superseded by FFF-302.**
- [FFF-83, "Hide the latency"](https://factorio.com/blog/post/fff-83) — latency state, and
  *"There is no state correction or anything."* Written in the peer-to-peer era.
- [FFF-149, "Deep down in multiplayer"](https://factorio.com/blog/post/fff-149) — catching up,
  *"other clients are not bothered"*.
- [0.14.0 changelog](https://wiki.factorio.com/Version_history/0.14.0) — the exact wording and date
  of the "Server doesn't stop/slow down the game" line.
- [Wiki: Multiplayer](https://wiki.factorio.com/Multiplayer) ·
  [Wiki: Desynchronization](https://wiki.factorio.com/Desynchronization)
- [server-settings.example.json](https://raw.githubusercontent.com/wube/factorio-data/master/server-settings.example.json)
  — `minimum_latency_in_ticks`, `max_heartbeats_per_second`, auto-pause.

**Age of Empires.**

- [1500 Archers on a 28.8](https://zoo.cs.yale.edu/classes/cs538/readings/papers/terrano_1500arch.pdf)
  (Bettner & Terrano, GDC 2001). Full text was extracted locally with `pdftotext -layout`; every
  quote is from that extraction and was cross-checked against
  [the Game Developer copy](https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond).

**Blizzard — read for the owner's "mixed pings felt fine in WC3" question.**

- [WC3 1.28.4 patch notes, archived](https://web.archive.org/web/20170622070527/https://us.battle.net/forums/en/bnet/topic/20756885804)
  — Pete Stilwell (Blizzard). **Read directly; see the correction in section 3.**
- ["Turn rates, matchmaking, and you"](https://us.forums.blizzard.com/en/starcraft/t/turn-rates-matchmaking-and-you/519)
  — Grant Davies (Blizzard, Senior Software Engineer). The best primary source found on Blizzard
  netcode, and the origin of the SC:R turn-rate formula.
- [GHost++](https://github.com/uakfdotb/ghostpp/blob/master/ghost/game_base.cpp) — a headless
  **pure-relay** WC3 host, i.e. exactly our relay's job. Lag detection, action pacing, drop vote.
  Third-party reverse engineering, flagged as such.

**Open-source engines, read as source code.**

- [Recoil `GameServer.cpp`](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp)
  and [`NetCommands.cpp`](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/NetCommands.cpp)
  — the jitter-buffer comment quoted in section 3, and `NETMSG_COMMAND` carrying no frame field.
- [0 A.D. `TurnManager.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/system/TurnManager.h)
  and [`NetServerTurnManager.cpp`](https://github.com/0ad/0ad/blob/master/source/network/NetServerTurnManager.cpp)
  — a readable implementation of the readiness gate we are removing.
- [OpenRA `Server.cs`](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Game/Server/Server.cs) —
  `ReceiveOrders` stamping `frame += OrderLatency`, i.e. **the server assigning the frame.**
- [Warzone 2100 `gtime.cpp`](https://github.com/Warzone2100/warzone2100/blob/master/lib/gamelib/gtime.cpp)
  — negotiated latency.

**Photon Quantum — a modern commercial deterministic engine.**

- [Input flags](https://doc.photonengine.com/quantum/current/manual/player/input-flags) ·
  [Frames](https://doc.photonengine.com/quantum/current/manual/frames) — the `Repeatable` boundary
  between direct-control input and command-like input, which is the distinction that makes an
  empty substituted turn safe for this game.

**Theory.**

- Schneider (1990), *Implementing Fault-Tolerant Services Using the State Machine Approach* — the
  Agreement/Order framing used in section 6.
- Défago, Schiper & Urbán, *Total Order Broadcast and Multicast Algorithms* — "fixed sequencer,
  unicast to sequencer, broadcast from sequencer" is the formal name for section 5.
- Baughman & Levine, *Cheat-proof playout for centralized and distributed online games* — the
  formal statement that a lockstep group runs at the speed of its slowest member, and the
  *Asynchronous Synchronisation* idea deferred in section 9.
