# Netcode rework: one lagging player must not stop the game for anybody else

**Written 2026-09-07 for an agent starting fresh tomorrow.** You have none of the context that
produced this. Everything you need is here or is linked from here. Read sections 0 to 4 before
touching anything; they are short and they are the difference between fixing this and making it
worse.

This is a PLAN, not a record. When a phase lands, move what it built into `multiplayer.md` and
strike it here.

**Revised 2026-09-08 after an implementation audit.** Fourteen agents re-checked every claim in
section 4 against the code and hunted for what this document missed. Section 4's line references
all held. What did not hold was section 8: **almost every phase's stated falsification test could
not detect the failure it names**, and two blockers were found that would have broken the first
match after the cutover. Section 8 has been rewritten; sections 4, 5 and 7 have additions marked
*(audit 2026-09-08)*. Nothing in sections 1, 2, 3 or 6 changed — the diagnosis and the design
survived intact.

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


### Two blockers the first draft did not have *(audit 2026-09-08)*

**B1 — a turn-derived clock has no driver when there are no turns.** `MatchSession._lockstep`
requires `lockstep_enabled && Net.is_online()` (`MatchSession.gd:81`) and
`LockstepService._is_live()` requires the same (`:1511`). Offline, and on the replication path
section 9 insists on keeping, **no turn is ever applied**, so a purely turn-derived counter sits at
0 for ever. What that breaks, all verified: `ReplicationService` stamps its snapshot sequence with
`session.tick()` (`:382`) and discards `tick <= _applied_tick` (`:611`), so a replication client
applies exactly ONE snapshot and freezes; income never pays (`PlayerManager.gd:464`); creeps never
unlock (`SendBuilding.gd:449`); Sudden Death never arrives (`MatchSession.gd:331`); the research
undo window never closes (`TechManager.gd:58`); and both `DeterminismBench` and `PerfBench` drive
offline matches, so **phase 6's falsifier would be measuring a dead clock**. Phase 1 must keep
`Engine.get_physics_frames()` whenever `!is_lockstep()`.

**B2 — the relay is sealing before any client can receive, and the seals are destroyed.**
`MatchStartService._start_match` rpcs the go signal and opens the relay's own match scene in the
same call (`:401-418`), so the relay is live within a frame. A client needs one trip, a scene
change and a whole world build (`Main.gd:96-116`) — hundreds of milliseconds, i.e. many 20 Hz
seals. Every seal broadcast in that window hits `receive_batch`'s `if !_is_live(): return`
(`:1266`) and **is gone for ever**: under the sealed stream there is exactly one copy of turn N,
no author-side record and no echo. The peer then wants turn 0, which no longer exists, and
amendment 1 declares it hopelessly behind — at match start, every match. Today this cannot happen
because each peer authors its own stream from turn 0 whenever its clock starts (`:932-946`). The
seal clock must be gated on peers being live, or pre-live seals buffered, or the relay must
backfill on request.

### Six more things that must change, all verified *(audit 2026-09-08)*

| Where | What |
| --- | --- |
| `SessionLog.gd:302`, `:309`, `:204` | Calls `Lockstep.delay_turns()` and `local_jitter_ms()`, and reads `min/max_delay_turns`. `Lockstep` is a typed autoload, so deleting those in phase 4 is a **parse-time failure — the project stops booting**. `NetworkConfig.validate()` (`:408-420`) also still errors on the deleted knobs. |
| `LockstepService.gd:1084-1121` | The unreliable **echo is the only cheap loss recovery**, and its docstring says why: the reliable channel is ORDERED, so a re-send cannot overtake a loss. Section 5 collapses N streams into one and discusses dedupe only on the up-leg. **Nothing replaces the echo on the relay→peer leg, which is the only leg left.** |
| `LockstepService.gd:1022` vs `:1231` | `_last_heard` has two writers: `submit_turn` (**reliable**, every tick) and `submit_alive` (**unreliable**, twice a second). Section 5 deletes the per-turn word, so a peer doing nothing sends the relay nothing reliable ever again — and amendment 2 then makes ending a player's match a decision taken solely on packets with no delivery guarantee. |
| `LockstepService.gd:1226-1232` | `submit_alive` assigns `_reported_turn[sender] = turn` with **no monotonicity guard**, over UDP. Amendment 2 promotes that into a drop decision. Reordering makes it go backwards; lost heartbeats age it at the seal rate. Clamp with `maxi()` first. |
| `LockstepService.gd:716-760` | `_reset_if_new_match` is not mentioned anywhere in this plan. The relay's `(peer, seq)` high-water mark and each peer's sealed buffer **must be added to it**, or the second match on a relay process silently dedupes away every order from a client that restarted its `seq` — no error, no stall, the player clicks and nothing happens. Its own docstring records that this exact class of bug already cost a debugging cycle. |
| `LockstepService.gd:682`, `:1335` | `_missing_for` walks `_expected_peers()`, which **deliberately excludes the relay**. After the cutover the only party that can be late IS the relay, so `lockstep.stalled`'s `missing` field, the `turn_stalled` signal and `waiting_on()` would all name innocent opponents for a purely local hold — inverting the very thing section 11 tells the next investigator to trust. |

**And one thing section 4 overstated.** The `:506` row calls the 8 s timeout "the only ceiling on
a stall". It measures SILENCE via `_last_heard`, which the heartbeat refreshes — so a peer that is
late but still beating never trips it and **that stall has no ceiling at all.** Amendment 2 is
what closes this; the table row read alone is misleading.

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

### Seven more amendments *(audit 2026-09-08)*

6. **The order UI must survive a hold.** `MatchSession.hold` sets `tree.paused`, and only five
   nodes opt out with `PROCESS_MODE_ALWAYS` — GameMenu, DraftPanel, ConfirmPrompt, DesyncNotice,
   StallPanel (`match_hud.tscn:240-254`). `UnitPanel`, `SendBar`, `ActionBar`, `ResearchCenter`
   and `CommandController` do not, and Godot suppresses `_unhandled_input` under a pause. So
   today a stalled peer cannot click anything — which was harmless when everyone stalled
   together, and **defeats the whole design the moment a peer stalls alone**: it would be frozen
   AND mute. Accepting an order mid-stall is newly safe precisely because no client names a turn
   any more. This is the most player-visible half of the change and it is easy to miss.
7. **Replace the echo, or say why not.** See the table above. One dropped seal now costs a full
   ENet retransmit of held time on the only channel left, which is exactly the micro-stutter
   Recoil's comment in section 3 warns about, now unmitigated.
8. **Gate the seal clock on peers being live** (B2), and put the relay's `(peer, seq)` high-water
   mark and the peer's sealed buffer into `_reset_if_new_match`.
9. **Say which kill switch wins.** Amendment 1 ends the match locally on buffer overflow;
   amendment 2 drops the peer from the relay. Their relationship is undefined and they do
   different things — the relay's drop injects PLAYER_LEFT, which erases the leaver's maze on
   every peer (`PlayerManager.gd:62` → `:217`), while a local end says nothing on the wire at
   all. Make the local one leave through `MatchStart.leave_match()` so the existing path runs.
10. **Size amendment 2's threshold as a ceiling on ACCUMULATED trailing, not as a spike
    detector.** Without catch-up a peer runs exactly one turn per tick (I3), so every packet gap
    it recovers from is added to its lead permanently and its input delay only ever grows.
    Nothing else bounds that. The threshold is therefore "how bad is a player's input delay
    allowed to get before we end it for them", which is a different question from "is this peer
    hitching" and wants a different number.
11. **Fix the `missing` field** so a local hold cannot name an opponent (see the table above).
    The session log is the artefact a tester sends back, and section 11 tells the next
    investigator to trust that field.
12. **`_forget_old_turns` and `_plausible_turn` are call-site-scoped edits, not deletions.**
    `_plausible_turn` has three call sites: `:1317` in `_record` is the peer-side ceiling
    amendment 1 kills, while `:1016` in `submit_turn` and `:1111` are **relay-side cheat guards**
    that stay until the turn parameter itself goes.

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
This is the deliberate trade and it is unavoidable once the client stops naming the turn.

*(audit 2026-09-08)* **Against what is actually shipping it is an improvement, not a regression.**
The first draft compared against a `delay_turns` of 1. `jitter_margin_ms` was raised to 20 on
2026-09-07 to stop the oscillation described in
`Findings/2026-09-07-playtest-2-delay-cliff.md`, so the shipped configuration now books two turns
rather than one. At the round trips that playtest measured, one round trip plus half a seal
interval is materially less than two turns. Unlike an integer `delay_turns` the lead is also
continuously tunable. Phase 2 is therefore **worth doing on its own merits rather than as a debt
being paid off**, which is a weaker reason than the first draft gave it — but it is still a
prerequisite for the cutover, because the lead is the knob that will be tuned afterwards and
nobody should be tuning it against a UI that answers nothing until the round trip completes.

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

**Order traffic changes shape.** Orders arrive unbatched rather than a turn at a time.
*(audit 2026-09-08)* The "flood" framing was wrong: `repeat_on_hold` is already rate-limited by
`hold_repeat_min_interval` (`ControlsConfig.gd:126`), whose authored floor is longer than a seal
interval — so at most one order every few turns. And deleting the per-turn word and its echo makes
total wire traffic **fall**, not rise. So the client coalescer and the relay-side cap are
anti-abuse floors against a modified client, not a fix for the shipped UI. OpenTTD's precedent is
two commands per client per frame with a kick at sixteen queued.

---

## 8. The plan

**Rewritten 2026-09-08.** The first draft's phases were right about what to build and wrong about
how to know it worked: **almost every "falsifies" clause named a test that could not detect the
failure it described.** Three were run in the one topology where both candidate answers agree —
which is section 11's own trap, reached three times. Two phases have been split because they
bundled a UI change with a netcode change, and phase 4's stated action made phase 4's stated
measurement impossible.

Each phase is independently landable. **Do not skip phase 0 or 1.**

### What to do next, in order  *(2026-09-08 handoff)*

1. **Close phase 1's draft gap.** Make `LockstepProbe` resolve a draft: gate the pick on
   `References.match_session != null` rather than on `_in_match`, and check the pick is actually
   applied rather than resubmitted 386 times. Then one `--draft` run of both roles with a freshly
   restarted relay. If `_check_clock` stays quiet, phase 1 is done in all three configurations.
2. **Take phase 0's measurement.** Two machines, `jitter_margin_ms = 0`, session logging on, a
   real match. Read `arrival_ms` and `stalled_s` out of `lockstep.health` and the relay's drift
   line out of journald. **This is the number the whole rework has been reasoning without**, and
   phase 5's servo decision depends on it. Put the value back to 20 afterwards.
3. Then phase 2 as written.

**Nothing is pushed.** Phases 0 and 1 are committed locally and `main` is two commits ahead of
`origin/main`.

### Phase 0 — Instrument. No behaviour change.  — DONE 2026-09-08 (`6d18be6`)

> **Landed as specified.** Three hooks, the relay drift report, `stalled_s` and `arrival_ms` in
> `lockstep.health`, `_ordered_at` re-keyed to a client-local `seq`, the stall-clearing log
> demoted to `debug`, and the `tick_seconds()` split pulled forward from phase 6 — six wall-clock
> call sites in `LockstepService` moved to a private `_engine_tick_seconds()`, three simulation
> ones left alone.
>
> Proven with a throwaway headless check (22 assertions: percentile indices, ring wrap-around, an
> early word reading negative, `_overrun_ms` picking the index the capped reading used to). **One
> assertion failed and found a real bug** — `_sample_arrivals` used `0` as both "no due stamp" and
> a legitimate `Time.get_ticks_msec()`, the sentinel collision `UNKNOWN_RTT` is negative to avoid.
> A 68-agent adversarial review afterwards raised 25 findings and refuted all 25, which is worth
> recording mostly as evidence that the review was not where the value was.
>
> **The measurement itself has NOT been taken.** That needs two machines and
> `jitter_margin_ms = 0`, and it is the first thing to do — see "What to do next" below.


Nothing in this codebase records how long a turn word actually took to arrive, which is why this
problem was misdiagnosed twice. Everything below is local state plus log output: no wire change,
no rpc signature change, `protocol_version` untouched.

**Arrival lead** — three hooks in `LockstepService`, verified in place:

- `_advance_turn`, right after the `if turn > clock_turn` guard: write-once `_due_at[turn]`. The
  first tick that passes that guard IS the instant the turn became due on this machine.
- `_record`, after its two existing guards, beside the `_incoming` write: write-once
  `_arrived_at[turn][peer]`. `_record` is the single funnel — `_emit`, `submit_turn`,
  `submit_echo` and `_absorb` all pass through it. **Write-once is load-bearing, not tidiness:**
  the unreliable echo can beat the reliable batch, and the question is when this machine FIRST
  held the word.
- `_advance_turn` again, after `_last_run_turn = turn` and **before `turn_ready.emit`** — fold
  `arrived - due` per peer into a ring modelled on `_overruns`, then erase both entries alongside
  `_incoming.erase(turn)`. It must precede the emit or every health line reports a stale window.

Key it `(turn, from_peer)`, taken verbatim from `_record`'s own two parameters. **That survives
phase 4 unchanged**: `turn` is the local consumption index, not a client's request — today the
client authors that field and after the cutover the relay authors the same field position. Do NOT
key on `scheduled_turn()`/`_closed_through`, which phase 4 deletes, and do NOT key on the future
`seq`, which is a client→relay dedupe key while this metric measures the down-leg.

**Drift** — `_report_drift()` in the relay branch of `_physics_process`, gated on a frame count
the way `_measure_and_announce` already is. Compare `current_turn()` against `_reported_turn`, not
raw `_frames` (different units once `ticks_per_turn` moves off 1). Log **each peer's
`_frames + _stalled_total`, not `_frames` alone**, and log **the relay's own achieved seal
interval against its own wall clock** — without both, phase 5 cannot tell a drifting peer clock
(which a servo fixes) from a relay sealing slow (which it does not).

**Also in this phase, and each one is here for a reason:**

- `lockstep.health` gains `stalled_s` from the existing public `stalled_seconds()`. `stalls` is a
  COUNT, which CLAUDE.md and section 10 both forbid as a measure.
- **Split `MatchSession.tick_seconds()` into a simulation constant and a separate wall-clock
  reading.** Moved forward from phase 6, because `stalled_seconds()` and the seal-interval
  `ideal_ms` are both built on it and both are the metric every later phase is judged by. Under a
  servo they would silently stop meaning seconds.
- **Re-key `_ordered_at` from turn to a client-local monotonic `seq`.** Diagnostic-only today,
  and it introduces exactly the `seq` phase 4 needs. Without it `order.ran waited_ms` — the one
  number that says whether any of this worked — has no key after the cutover.
- **Demote the `Log.info` on the stall-clearing path to `Log.debug`**, and name it in the commit
  as a deliberate change to log output. It and the `Log.warn` above it sit **inside the interval
  being measured**, and at the stall rates of playtest 2 that is seconds of `get_stack` and
  `print_rich` inside the window.
- **No `Log.*` call at either per-tick site, at any level** — data only. The distribution goes out
  through `SessionLog.note`, which does no `get_stack`. The single new `Log.*` is the relay drift
  line and it must be `Log.debug`.
- Add both new dicts to `_reset_if_new_match`.
- `LockstepService` is one public method under gdlint's ceiling, so phase 0 may add exactly one.

**Measure it at `jitter_margin_ms = 0`, then put the value back.** The margin raised on
2026-09-07 suppresses the very oscillation this instrument exists to characterise; a clean reading
through it would be an artefact rather than a finding.

- *Measured:* arrival-lead distribution; `stalled_seconds()` (duration, never count); drift.
- *Falsifies:* if arrival-lead p99 is small and stalls still happen, the network-jitter story is
  wrong and so is every budget in this file.

### Phase 1 — Turn-derived match clock.  — DONE 2026-09-08 (`3e1f7a4`), draft case unproven

> **The draft case may not be provable yet, and not for a netcode reason.** The owner reports on
> 2026-09-08 that the technology DRAFT has never been tested and may not be fully implemented.
> What is known from a real two-client run that day: the server side works — `StartingTech` logged
> `Draft opened` with three Ultimates rolled, and held the world exactly as designed. What is NOT
> known is whether the panel renders and whether a pick travels; that run was abandoned because
> neither player could pick, and the world stayed held for the rest of it.
>
> So the phase 1 question — is the hold read on the right side of `Commands.apply_turn` — is
> blocked behind a GAMEPLAY task rather than a netcode one. Do not spend netcode time on it.
> The clock check ships enabled and will report the drift the first time a draft resolves, which
> is the correct place to leave it.
>
> **It also means a lobby option currently bricks a match.** Worth fixing or hiding before any
> tester sees it, independently of this document.

> **Landed as specified**, including the `!is_lockstep()` fallback (B1), the hold read AFTER
> `apply_turn`, and `begin()` clearing `_holds` — which was a latent bug until the clock's advance
> condition became a read of that set. `_check_clock` ships enabled and compares the turn clock
> against the retained `_legacy_tick()` by difference from a baseline, `Log.err` on a mismatch,
> capped at five.
>
> | Case | Result |
> | --- | --- |
> | Offline | Determinism-bench traces **byte-identical** across the change, same seed and ticks, 13 checksum samples. `WorldChecksum` hashes `tick()`, so any drift would have moved them. |
> | Online, no draft | Two headless peers on a local relay: 425 turns each, 44 orders, **0 desyncs, 0 clock complaints**. Genuinely exercised — the only holds in either log are `lockstep`, so `advance_clock` incremented on every turn. |
> | **Draft** | **NOT PROVEN.** See below. |
>
> **The draft case is the one that matters and it is still open.** `LockstepProbe` cannot resolve
> a draft: teaching it to submit `PICK_DRAFT_TECH` was not enough, because `_in_match` is set when
> the match STARTS and the pick fires before `References.match_session` exists, and the picks that
> do land never clear the hold. So the world stayed held all match, `advance_clock` returned early
> on every turn, and `_check_clock` never made a single comparison — a green run that measured
> nothing. **Reading the hold before or after `apply_turn` differs by exactly one tick only on the
> turn that RELEASES the draft**, so today that ordering is reasoned rather than measured. The
> check ships enabled, so the first draft match anybody plays reports the drift if it is wrong.


`MatchSession.tick()` becomes a counter advanced once per applied turn — **and keeps
`Engine.get_physics_frames()` whenever `!is_lockstep()`** (blocker B1). Skipped while a
**non-lockstep** holder is active, which needs a new cheap predicate: `is_paused()` cannot tell a
draft hold from a lockstep one and `holders()` copies and sorts an Array on every call.

**Evaluate the hold state AFTER `Commands.apply_turn`, not before.** The draft hold is released
from *inside* `apply_turn`, and the tick that releases it does simulate and is counted by the old
clock. Also note `_start_frame` is stamped in `Main._ready` while `_frames = 0` is set on
`LockstepService`'s first physics tick — different instants, nothing pinning them — and
`LockstepService` runs ahead of the whole match scene, so **assert equality of DIFFERENCES, not of
absolute values**, and decide the increment's placement deliberately.

- *Measured:* the new counter equals **`_last_run_turn` minus the turns applied while a
  non-lockstep holder was active** — not "equals the old `tick()`". Run it **offline as well as
  online**, and **in a DRAFT-mode match as well as the shipped default.**
- *Falsifies:* nothing, if run as first written. Under the current gate a lockstep stall applies
  no turn at all while a draft hold applies turns, so *"skip while held by anybody"* and *"skip
  while held by a non-lockstep holder"* give identical counters on every tick — and the wrong
  choice would stay invisible until phase 4, when a peer stalls alone. The draft-mode and offline
  runs are what make this phase falsifiable at all.
- **`ticks_per_turn > 1` silently redefines the second** if the counter advances by 1. Advance by
  `_ticks_per_turn()`, or pin the knob and refuse anything else at boot.
- Re-record the `DeterminismBench` baseline in the same commit — `WorldChecksum` hashes the clock.

### Phase 2 — Presentation feedback (`multiplayer-todo.md` §1.2).

Build ghost at the clicked cell, send stock decrementing on click, tower greying on sell.

- **Define what removes the drawn intent when the order is REFUSED**, not only when it lands.
  Nothing anywhere says this today.
- **Any `command_rejected` listener must filter on the local slot.** `_reject` runs inside
  `apply_turn` on *every* peer, so the signal fires on the opponent's machine carrying the
  ordering player's slot.
- *Falsifies:* two peers running the same seeded match, one of them drawing local intent for
  every order it issues, must report identical world checksums at every comparison turn. "Zero
  desync risk" is otherwise an assertion about code nobody has written yet — and the send bar's
  stock is real simulated state, which is exactly where drawing intent is easiest to get wrong.

### Phase 2b — Widen `_forget_old_turns`. Its own landing.  — DONE 2026-09-08

Split out of phase 2: a UI change and a change to desync-detection scope share nothing but a slot
in a list and should not be judged by one review. Must land **before** peers can legitimately be
seconds apart, and must cover amendment 10's lag threshold.

**What landed.** `NetworkConfig.max_peer_lag_turns` replaces `checksum_every_turns * 4` as the
retention window, because those were unrelated questions tied to one number — how OFTEN the world
is hashed had been setting how far apart two peers may be. The default is derived rather than
chosen: it must exceed the largest spread that can legitimately exist, and today that is bounded
by `silent_timeout_seconds`. It is marked in the config as wanting measurement.

**A second failure was found and fixed in the same place.** A report arriving for a turn already
forgotten did not just miss its comparison — `_compare_turn` re-created the entry, so the late
answer sat alone in a fresh dictionary with nothing to measure it against, and a comparison that
never happens is indistinguishable from one that passed. It is now refused with a warning
(`_pruned_through`), so the case is loud instead of silent.

**This is inert until phase 4.** Under the current gate peers can never be more than `delay_turns`
apart, so the window never binds and the guard never fires. That is the point: it is correctness
banked before the change that needs it. The one behaviour visible today is that a dropped peer's
late checksum now logs a warning instead of silently resurrecting a turn.

*Falsifies:* nothing today, by construction — which is why it must be re-checked at phase 4,
where a deliberately hitched peer should produce comparisons that still happen rather than
warnings that say they did not.

### Phase 3a — Send bare orders alongside the turn word.  — DONE 2026-09-08

Clients additionally send `(order, seq)` at press time; the relay dedupes on `(peer, seq)` and
seals from **arrival order**, not from the turn number the old word still carries. Nothing
consumes the seal yet.

Split out because the first draft's phase 3 sealed from today's batched, turn-stamped, delay-ahead
ingress — so it would have validated the sort key against an arrival pattern phase 4 replaces, and
left `seq` dedupe, press-time arrival and the order caps untested until they were load-bearing.

### Phase 3b — Shadow the seal and compare in-process.  — CODE DONE 2026-09-08, UNPROVEN

The relay broadcasts `receive_seal` alongside `receive_batch`. Peers ignore it for play and
compare it against their own `commands_for(turn)` **in the same process, with a `Log.err` on any
mismatch.** Not an offline diff: that is a human step that fails silently when nobody takes it,
and the peer already holds both answers.

- *Measured:* **the per-peer subsequence** — each peer's orders appear in the sealed stream
  exactly once, in `seq` order, none lost and none duplicated.
- *Not* per-turn equality. A peer books into `current_turn + delay_turns + 1` while the relay
  seals on arrival, so **the two disagree on every turn holding an order, by construction**, and
  no constant shift repairs it. The first draft's "zero disagreements over a full match" could
  never have passed.
- **Move the third-peer-connecting-mid-match scenario here**, where both formats are on the wire
  and a disagreement costs a log line rather than a match.
- **Phase 3 is free on the wire but not free to deploy.** `NetworkService.rpc_signature()`
  already refuses any build whose rpc surface differs, so adding `receive_seal` forces every
  tester to rebuild. The phase-4 `protocol_version` bump is a readable second check, not the
  mechanism.

**What landed, and what is deliberately not tested yet.**

`schedule()` sends the order a second time with no turn number on it (`submit_order`), the relay
files it, seals on its own tick sorted by `(slot, seq)`, and broadcasts `receive_seal`. Peers file
both roads per SLOT and `_compare_shadow` checks them prefix by prefix, dropping what matched so
neither list grows. `Log.err` once on any divergence.

Two bugs of D33's own shape were caught by reading before this landed, and both are worth
remembering because the seal is a NEW broadcast and every new broadcast meets them again:
a bare `rpc()` reaches every CONNECTED peer, including somebody sitting in the lobby browser who
would file a seal for a match they are not in — it goes to `_match_peers()` instead; and
`submit_order` now refuses a sender whose `_slot_of_peer` is 0, or a lobby browser's orders would
be filed under slot 0 and sealed.

**EMPTY SEALS ARE NOT BROADCAST.** In shadow mode they carry nothing to check and would double the
relay's upload for no measurement. **The cutover must send one every turn** — an empty seal is the
heartbeat that tells a peer the turn happened and was empty — so that path is untested and phase 4
must add and test it.

**UNPROVEN: the comparison has never run.** It needs two peers and a relay, which is exactly the
scenario phase 3b exists to be safe in. Boot is clean and the code is reviewed, but nothing has yet
observed `_compare_shadow` execute even once. **Before phase 4, run the two-peer headless match and
confirm the positive control: orders were issued, both lists were fed, and the comparison actually
compared** — a silent pass here is indistinguishable from a comparison that never ran, which is
`CLAUDE.md`'s own most-repeated trap.

### Prerequisite before phase 4 — cross-machine determinism.

`multiplayer-todo.md` §1.1: a real match between the two dev PCs, session logging on, turn streams
compared. It is called the largest untested assumption in the system, and `DeterminismBench`'s own
docstring says it cannot catch cross-machine float divergence. **Phase 4 is the change that makes
it hardest to test afterwards** — today a divergence is caught within a few tens of turns because
peers are turn-locked; after the cutover peers are legitimately seconds apart.

### Phase 4 — The cutover, behind a flag.  — DONE 2026-09-08, flag still OFF

**Measured, paired, alternating: the healthy peer went from 5.10/5.40 s held to 0.85/0.75 s while
the other machine hitched 900 ms six times, and a hard-wedged peer cost it nothing at all.** All of
the residual is one stall on turn 0. See `Findings/2026-09-08-sealed-stream-cutover.md` for the
table, the six scenarios each with its own positive control, and the three bugs an adversarial pass
over the diff found that none of the runs could see.

Landed differently from the text below in two ways, both deliberate:

- **nothing was deleted.** The `delay_turns` / `_wire_budget_ms` / `announce_one_way` chain,
  `_speak_for_the_departed`, `SYSTEM_LEAD_TURNS`, the local self-record and `_queue`'s `skip` all
  remain, because the flag has to be flippable for the paired measurement and every one of them
  belongs to the path the flag turns off. The `SessionLog` / `NetworkConfig.validate()` parse
  failure the audit warned about therefore never arose. They go in the follow-up commit that
  removes the old gate and bumps `protocol_version`
- **B2 is solved by a ready-gate rather than by buffering.** A peer sends `submit_ready` once its
  world is built and the relay's seal clock does not start until every player has, with an
  8 s backstop against a client that reports loaded and then never arrives. Measured at 9 frames
  of wait in a local match, and no seal is ever broadcast into the void

Amendment 6 landed as `Scripts/UI/StallInput.gd` rather than as `process_mode` in the scene, which
the text did not anticipate: written into `match_hud.tscn` it would also un-mute the command card
during the technology DRAFT, which is a rule change. The node releases the order UI only while
`lockstep` is the SOLE holder of the pause, and only when the flag is on.

Flip the gate to `_sealed.has(turn)`, **delete the local self-record in the same commit**, and
delete `_speak_for_the_departed`, `SYSTEM_LEAD_TURNS`, the `delay_turns` / `_wire_budget_ms` /
`announce_one_way` chain **and its callers in `SessionLog` and `NetworkConfig.validate()`**, and
the peer-side `_plausible_turn` only. Add `(slot, seq)` sort, order caps, and amendment 6's
`PROCESS_MODE_ALWAYS` on the order UI. Remove `_queue`'s `skip = sender`. Handle B2.

**Land it behind a `NetworkConfig` boolean shaped like `lockstep_enabled`, and take the paired
measurement against that flag. Bump `protocol_version` and delete the old gate in a separate
follow-up commit.** The first draft bumped the version and deleted the old path in the same phase
that demanded "paired, same commit, alternating runs" — a version bump makes the two builds
mutually refusing and the deletions make the variable un-flippable, so the measurement it asked
for was impossible to take.

Rebuild the dev probe from the scenario list in
`Findings/2026-09-05-lockstep-review-2-response.md`, plus **one peer given a deliberate ~900 ms
freeze**.

- *Measured, paired, alternating against the flag:* the healthy peer's `stalled_seconds()` while
  the other is deliberately hitched. **That asymmetry IS the design.** Add the relay's own
  seal-interval percentile read straight from `_overruns`, so "the healthy peer still stalls" can
  be attributed to a relay overrun rather than to an untuned lead.
- *Falsifies:* if both peers improve equally, the coupling was never the cause. If the healthy
  peer still stalls, the relay is the problem.
- Then delete `Scripts/Dev` and write the finding.

### Phase 4b — The relay-side lag drop.  — DEFERRED 2026-09-08, deliberately

**The clamp landed; the drop did not, and should not until there is field data.**
`_reported_turn` is now `maxi`-clamped in `submit_alive`, which was an outright bug rather than a
policy: it rides an unreliable rpc, so reordering moved it backwards and a lost heartbeat aged it
at the seal rate. Any threshold built on the raw reading was being read off a number that wanders.

The DROP itself is deferred, and the case for deferring got stronger once the cutover was measured.
The gap it fills is narrower than the plan assumed:

- a peer that is genuinely silent is already given up on by `_drop_silent_peers` at
  `silent_timeout_seconds`
- a peer that is hopelessly behind now **gives up on itself** at `max_sealed_turns`, and says so -
  see phase 4c

What is left is only the middle case: alive, talking, and never catching up. That peer terminates
itself, so the relay-side drop buys tidiness rather than liveness. **Its threshold is a judgement
about how much input delay a player should be made to tolerate before their match is ended FOR
them, and picking that from a loopback run would be guessing.** Revisit when a real session
produces a `sealed_turn - reported_turn` distribution; the clamp above is what makes that
distribution trustworthy when it arrives.

Lands only after a measured post-cutover session has produced a real
`sealed_turn - reported_turn` distribution. **Clamp `_reported_turn` monotonically first** — it is
written by an unreliable rpc that can move it backwards. Decide amendment 9's precedence here.

### Phase 4c — Tell the player.  — DONE 2026-09-08

**Smaller than the plan assumed, because `notify_lagging` turned out to be unnecessary.** The plan
had the relay telling a peer it was lagging; the peer already knows exactly, because the backlog
waiting to be played IS the lag and it is sitting in that machine's own dictionary. A round trip
could only tell it something it already knew, later and less accurately. `sealed_lag_seconds()`
reads it locally and nothing crosses the wire.

`StallPanel` now has the three states, and every one of them describes only the LOCAL machine -
which is the point of the cutover reaching the UI. Before it, a stall meant the whole match was
frozen and naming the responsible peer was the useful thing to say; now a stall is usually local,
and telling a player their opponent is at fault while that opponent plays on would be worse than
silence. A stall that is not terminal also carries the backlog in seconds, because a trailing
machine feels HEAVY rather than frozen and the two have completely different causes.

**Giving up no longer yanks the player to the menu.** It clears the backlog, holds the world and
puts up a terminal message; the player leaves by pressing the button, exactly as they do on
`DesyncNotice`. Amendment 9's concern was that a local end must not say nothing on the wire, and a
deliberate leave says it - what is added is that a dropped player is told why, which has never
happened in this project before.

`notify_dropped(reason)` as an rpc is therefore also unbuilt and unneeded for this case. It comes
back only with 4b, which is the one road out that the player did not choose.

`notify_lagging`, `notify_dropped(reason)`, the three-state stall panel. Split out because it
carries no determinism risk and shares no code with the gate flip. This would be the first time a
dropped player is told why.

### Phase 5 — Decide whether the servo is needed.  — MEASURED 2026-09-08, PROVISIONALLY NO

Threshold stated before the run, as this section demands: *a servo is needed if a healthy peer's
lead drifts by more than one turn (50 ms) per match minute in steady state.* Measured over 5900
turns of a clean sealed match: the lead held at **0** for the whole run and both peers ran at 20.0
turns per second against the relay's 20. Not under the threshold — not measurable.

**But both peers shared one machine's clock**, and drift comes from two different crystals. This
rules out Godot's own tick scheduling and says nothing about two real PCs, so the answer is
provisional and the two-PC run is what reopens it. Judge that run against the same threshold.

**From a post-cutover drift run, not from phase 0's.** Under the current gate `_frames` stops
while stalling, so what phase 0 records is dominated by accumulated stall time rather than
free-running clock drift, and a peer whose clock runs *fast* is invisible entirely because the
gate converts its drift into stall time. Phase 0's drift number is a baseline, not the decision.

**State the threshold in milliseconds of drift per match minute before the run happens**, so the
measurement can refute the no-servo position instead of being interpreted after the fact.

If drift is negligible, **stop here indefinitely.**

### Phase 6 — Delta refactor, then servo, then catch-up.  — BLOCKED, and on more than time

Re-scoped 2026-09-08 after phase 5 came back negative, because two of its three parts turned out to
rest on something this document had not named.

**The servo is not wanted**, on phase 5's evidence, and the delta refactor across 29
`_physics_process(delta)` sites exists only to serve it. Both wait for the two-PC drift run.

**Catch-up needs an architectural change this plan never priced.** The obvious reading is "run more
than one turn per tick when behind", and it cannot work as written: applying two turns' ORDERS in
one engine tick still advances the world by ONE `_physics_process`, because the simulation is
driven by Godot's per-node dispatch rather than by the turn loop. Every peer that caught up would
therefore compute a different world from every peer that did not — a silent divergence, and the
worst kind, since catching up is exactly what a struggling machine does.

Real catch-up means driving the simulation step from the turn loop instead of from
`_physics_process`, which is the per-node dispatch change `CLAUDE.md` already lists under Known
weaknesses as unstarted, and which is the same work the twelve-player budget needs. **That is a
project, not a phase.** Doing it badly desyncs every match, so it wants its own plan.

Until it lands, amendment 10 stands unmitigated and should be stated plainly to players rather than
hidden: **a peer's lead only ever grows.** Every packet gap it recovers from is added to its input
delay permanently, bounded only by `max_sealed_turns` and then by giving up. In a healthy local
match that never moved off zero in five minutes; on a real link it is what 4b and 4c exist to
notice and to explain.

Land the refactor **alone**: every gameplay `_physics_process` stops consuming the engine delta.

- *Falsifies:* **run the determinism bench at two different `physics_ticks_per_second` values
  with the authored constant pinned, and require a byte-identical trace.** At a single fixed rate
  the engine delta already equals `tick_seconds()` exactly, so substituting one for the other
  cannot change a bit and a missed call site is invisible by construction — the first draft's
  test would have passed over any refactor at all. Additionally, record the baseline **on the
  parent commit** and copy it out of `user://` before the refactor lands; two post-refactor traces
  agree trivially and prove determinism rather than the no-op being claimed.

Then prove the rate change in single player before any netcode depends on it; then the servo
(small, symmetric corrections); then catch-up capped at **+50%, not 4x** — a tower defence
fast-forwarded through a leak is unreadable, and recovery must not cost the player the ability to
react.

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

**A FALSIFICATION TEST RUN IN THE TOPOLOGY THAT CANNOT DISTINGUISH THE ANSWERS IS NOT A TEST.**
*(audit 2026-09-08)* This document's own first draft carried five of them, and three failed the
same way: phase 1 asserted a rule under the current gate, where both candidate rules give
identical answers on every tick; phase 3 asserted an equality that is false by construction; phase
6 asserted a no-op with a test that at a fixed rate cannot fail. **Every one looked rigorous.**
The check that catches it costs one sentence — *name the failure, then say what the test would
print if that failure were present* — and if the answer is "the same thing it prints now", the
test is decoration. This is the same trap as the entry below it and the one two above it, arriving
through the test rather than through the topology or the symptom.

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

---

## 13. Phase 6 in full — explicit simulation stepping, then catch-up

> **DECIDED 2026-09-09, and CORRECTED the same day. Phase 6 is needed. Take the servo road first.**
>
> The first version of this note said the measurement had half-met 13.7's abandon condition and that
> nothing was needed for the 1v1 milestone. Both halves of that were wrong, and
> `Findings/2026-09-09-sealed-stream-on-two-machines.md` carries the correction: the laptop's lead
> was flat because only one hiccup occurred in the sample, not because anything drains it. **A
> banked turn is banked for the life of the match**, so the delay accumulates at whatever rate the
> machine hiccups. Amendment 10 stands.
>
> **And the milestone argument no longer applies at all**: 1v1 and 4-player FFA matches have now
> been played end to end, so the work is optimising the netcode rather than reaching playability.
>
> What the measurement DOES settle is the drain rate needed. The debt arrives in ~200 ms lumps, so a
> peer must recover a handful of turns over seconds rather than tens of turns inside one frame.
> **Both roads reach that rate**: an engine-rate servo at 5-20% over drains 1-4 turns a second, and
> explicit multi-stepping at 1.2 turns per tick drains 4. So the choice is not about capability:
>
> - **The servo needs only the DELTA refactor** — every gameplay loop reading a fixed simulation
>   step instead of `delta`. It does not need the dispatch change this section is built around.
> - **The dispatch change buys a second thing the servo does not**: it is also the fix `CLAUDE.md`
>   names for the per-unit tick budget, which now matters, because four-player matches are real and
>   twelve is the target.
> - **The delta refactor is the shared prerequisite of both**, so it is never wasted.
>
> **So: 13.2, then the delta refactor, then choose with real information.** Do not choose now — after
> the delta refactor the servo is a small increment, and whether the dispatch change earns its risk
> is a question about the tick budget at higher player counts, which is measurable by then.
>
> **What does NOT change either way is 13.2.** A missed delta site diverges two peers under a servo
> exactly as under multi-stepping — one machine at 21 Hz and one at 20 advance that loop differently
> — so the falsifier work, and the sabotage matrix proving the falsifier can actually see a disabled
> loop, comes before either road. That is the real prerequisite and it is unchanged.

Written 2026-09-09 from a full audit of every `_physics_process` and `_process` in `Scripts/`, two
independently drafted designs and an adversarial review of each. **This supersedes the Phase 6 stub
in section 8**, which named the problem and priced none of it. It is written for an implementer who
has this document and the code and nothing else.

**The design taken is a scene-owned stepper driving a node group, not a hand-built registry of
buckets.** The runner-up mirrored the scene tree in typed lists — one per area, one per root — which
is equally deterministic and strictly more code, and it converts today's dispatch order into a
hardcoded list that a drag in the scene dock silently falsifies. `SceneTree.get_nodes_in_group()`
sorts with the same node comparator Godot's own physics dispatch uses and returns a copy, so a
custom group reproduces today's order *by the same mechanism* rather than by a list somebody has to
keep true — verified on a nested Godot 4.7.2 tree built deliberately out of insertion order, where
group order, dispatch order and tree order came back identical, and where a node added from inside
`_physics_process` was **not** stepped that frame. That second property is what makes the spawn-tick
behaviour below free instead of a rule. What is grafted from the runner-up is everything that makes
the change *checkable*: the sabotage matrix as the falsifier's positive control, the audit that
hunts a `_physics_process` nobody knew about, per-instance membership assertions instead of a boot
sweep, and pulling the step-counted clock forward into 6a — which the review showed is not optional,
because without it the only test that can catch a missed loop cannot run.

### 13.1 What phase 6 is, and why the obvious version fails

A peer that falls behind stays behind for the rest of the match. It runs at most one turn per engine
tick (`LockstepService._advance_turn`: `var turn: int = _last_run_turn + 1; if turn > clock_turn:
return`), so every packet gap and every local hitch it recovers from is added to its input delay
permanently. Nothing gives it back. That is amendment 10 restated as a lived defect: **a peer's lead
only ever grows.**

The obvious fix is "run more than one turn per tick when behind", and it cannot work. Applying two
turns' ORDERS in one engine tick still advances the world by ONE step, because the world is not
advanced by the turn loop at all — it is advanced by Godot calling `_physics_process` on every
gameplay node once per engine tick. `MatchSession.advance_clock` only increments `_turn_ticks`; it
steps nothing. So a peer that "caught up" would have a world in which less time passed than on a
peer that did not: creeps moved once instead of twice, towers fired once instead of twice, burns
ticked once instead of twice. **It diverges on empty turns too — the orders were never the
problem.** This is the silent, unrecoverable class of desync, arriving exactly when a struggling
machine tries to help itself.

Phase 6 therefore takes the simulation step away from Godot's per-node dispatch and drives it
explicitly from the turn loop, so the world can step N times inside one engine frame. `CLAUDE.md`
already lists the same change under Known weaknesses as the first half of the twelve-player tick
budget work ("the per-node `_physics_process` dispatch first, the spatial hash second"). One job,
two payoffs.

Split, and the split is not negotiable:

- **6a — explicit stepping, still exactly one step per tick, behaviour bit-identical.** No catch-up.
  The only phase in which "this changed nothing" is a provable claim.
- **6b — more than one step per frame.** Small in diff, large in consequence, and every commit in it
  changes behaviour on purpose and needs its own baseline.

### 13.2 The prerequisite — three things, none of them code

**1. The two-machine determinism run, which has still never happened.** Section 8's "Prerequisite
before phase 4" is still outstanding: a real match between the two dev PCs with session logging on
and the turn streams compared. `DeterminismBench`'s own docstring says what it cannot do — two runs
of the same binary on the same machine catch iteration order and unseeded randomness, and catch
cross-machine float divergence never. If two PCs diverge today, phase 6 is not the next piece of
work and neither is anything else; see 13.7. **Run it before writing a line of 6a**, because 6a is a
change that makes a divergence harder to attribute afterwards.

**2. The falsifier is not strong enough as it stands, and the reason is structural rather than a
coverage gap.** At one fixed rate, a loop left on `_physics_process` runs once per tick and a loop
moved onto the stepper runs once per tick. They are the same. A byte-identical trace would therefore
be produced by a correct refactor, by a refactor that missed ten loops, and by the refactor never
having happened. This is section 11's own recorded trap — *a falsification test run in the topology
that cannot distinguish the answers is not a test* — and it is the exact failure this document's
first Phase 6 draft carried.

**3. What must be added, and it goes in `DeterminismBench`, not in `WorldChecksum`.** The checksum's
docstring records that it was deliberately not widened: it is shipping code with a shipping cost,
and what it carries is a design question rather than something a harness decides. The bench's
`_deep_hash` walks `session.unit_ids()` and nothing else, so the following are invisible to every
trace this project can currently produce:

- **Projectiles, piercing projectiles, beast charges and ground hazards.** All four extend
  `VisualEffect3D`, none is a registered `Unit`, and all four deal damage on a `delta`-driven
  schedule. Four damage-dealing loops sit outside the falsifier entirely. Hash the children of
  `References.projectiles_root` in child order: class name, quantised position, elapsed.
- **`AttackComponent._cooldown`, `_windup_left`, `_scan_wait`.** `Building.checksum_state` records
  only `active_ability.cooldown()`. A missed attack step surfaces only later and indirectly, as
  creep health drifting. Reach them through new read-only accessors.
- **`SendBuilding` stock.** It overrides `checksum_state` at all — only `Unit`, `Building` and
  `Creep` do — so every `CreepStock` reserve timer is unhashed. A missed send step stops sends
  mid-match and no trace says so.
- **`PlayerArea` rubble.** `WorldChecksum._add_areas` hashes position, grid width and depth, and the
  build-zone rows. Rubble decides whether a rebuild is legal, is not replicated by design, and is in
  nothing.
- **The unhashed accumulators inside units:** `Creep._stall_elapsed` (crossing it re-plans a path —
  the highest-consequence unhashed float in the file), `Creep._march_elapsed`,
  `Building._upgrade_elapsed`, `Building._sell_elapsed`, and a digest of the `StatusEffects` timers.

**And the bench's driver only sends creeps.** `_drive_tick` issues `CHEAT_GOLD`,
`CHEAT_UNLOCK_CREEPS` and send orders. It never builds, upgrades, sells or gives a unit order — so
`Builder`, `MobileUnit`, the upgrade clock, the sell clock and the rubble timer are never exercised,
and a trace that never touched them cannot report them. Extend the driver to build, upgrade and sell
at least once, deterministically off the seed.

**Then record the baseline on the parent commit** — two seeds, byte-compared against each other
first to prove the harness itself is stable, then copied out of `user://` before anything moves.
Redirect the whole run to a file and grep the file; `| head` closes the pipe before a bench prints
its summary, and the summary is the answer.

**Then run the sabotage matrix, and watch it fail.** One bench run per gameplay loop with a new
`skip=<ClassName>` argument that calls `set_physics_process(false)` on every instance of that class.
Any loop whose omission leaves the trace byte-identical is a hole in the falsifier, not a loop that
does not matter — widen the hash until it goes red. **Until every one of them has been watched to
fail, a green 6a run means nothing**, and this is the one hour that decides whether the rest of the
phase is evidence or decoration.

### 13.3 Phase 6a — explicit stepping, commit by commit

The shape. One new file, `Scripts/Game/Simulation.gd` (`class_name Simulation extends Node`), added
as a node to `Scenes/main.tscn` and `Scenes/Server/server_match.tscn` and exported through
`Scripts/References.gd` — a scene node rather than an autoload, because the step count is per-match
state that should die with the match, and because `CLAUDE.md` forbids editing `[autoload]` while the
editor is open. Every gameplay loop renames `_physics_process(delta)` to `_sim_step(dt: float)` and
joins the group `&"sim"`; the stepper takes `get_nodes_in_group(&"sim")` and calls each entry.
Leading underscore deliberately: `Building`, `Creep`, `PlayerArea` and `MobileUnit` are already over
gdlint's public-method ceiling, `_sim_step` is exactly as public as the `_physics_process` it
replaces, and it is not an `Object` virtual so it does not walk into the `_set` trap.

Five properties of that stepper, each replacing something the change removes:

1. **The snapshot.** `get_nodes_in_group` returns a copy, so a creep added by `SendBuilding` or a
   projectile added inside `AttackComponent._fire` is not stepped on its spawn step — which is
   exactly what Godot's own copy-before-call does today, and is required for byte-identity on the
   first send.
2. **The pause.** `MatchSession.hold` sets `tree.paused`, and **that is the only reason a stall or a
   draft stops the world.** An explicitly driven loop is not suppressed by a paused tree, so the
   stepper must refuse to step while held. `hold` goes on setting `tree.paused` for presentation and
   input; the stepper adds one guard. Nothing in the sim set sets `process_mode` or calls
   `set_physics_process` itself, so one guard is a faithful replacement for all of them — record
   that constraint in the stepper's docstring, because anything added later that wants to run
   through a hold will find no place to say so.
3. **The step counter increments at the TOP of the step**, before the snapshot, never after. A
   counter incremented afterwards is constant for the whole step, and any reader running between two
   steps then stamps a cache with the number the next step will also see.
   `Engine.get_physics_frames()` is correct today precisely because it increments before the tick.
4. **`is_instance_valid` and nothing else.** No `is_queued_for_deletion` filter in 6a: today a unit
   that dies early in a tick still receives `_physics_process` later in that same tick if it sorts
   later. Reproduce it. Retirement is 6b's problem and 6b's re-baseline.
5. **One step per tick, hardcoded.** Call the step once, and `Log.err` at boot if
   `NetworkConfig.ticks_per_turn` is not 1 for the duration of 6a. Wiring the count to
   `_ticks_per_turn()` looks like generality and is 6b arriving early, with none of 6b's
   prerequisites in place — `CreepIndex` still keyed on the engine frame, the clock still counting
   frames, `WalkAnimation3D` still diffing positions.

**6a-0 — widen the bench, record the baseline, run the sabotage matrix.** All of 13.2's third item,
plus positive controls in `_finish()` that fail loudly: samples greater than zero, units seen,
projectiles seen, at least one non-zero attack cooldown, and the RNG state observed to change
between two samples. A green trace over a world that never fired a shot proves nothing about
ordering. Plus a throwaway `Scripts/Dev/StepOrderProbe.gd` that records, per tick, the ordered list
of stepped node names under the *current* dispatch — the reference the new order is diffed against,
and it can only be recorded before the change. *Positive control:* the sabotage matrix went red for
every loop.

**6a-1 — the stepper, wired, stepping nothing.** New file; run `godot --path <project> --headless
--import` or its `class_name` never reaches the global class cache. Node into both match scenes, and
into each scene's `References` `node_paths=PackedStringArray(...)` line, or the export silently
stays null. Drive it from `_advance_turn` immediately after `session.advance_clock(...)` under
lockstep, and from its own `_physics_process` otherwise. *Falsifier:* the group is empty, so the
trace must be byte-identical. *Positive control:* the stepper's own step count is non-zero in the
run — otherwise the no-op is the no-op of a node that never ran.

**6a-2 — the rename, in four commits, one per subtree.** Each commit is a **tree prefix**: the
migrated set runs inside the stepper (placed as the first child of the match root) in its own
relative order, the unmigrated remainder runs after it on Godot's dispatch in its own relative
order, and the global sequence is unchanged at every intermediate commit. That is what makes each
one individually bench-provable. The order follows the scene: `Scenes/main.tscn` runs
Areas → Units → Projectiles → … → PlayerManager → MatchSession → TechManager, and
`Scenes/Server/server_match.tscn` agrees.

  (a) **Areas subtree:** `PlayerArea`, `Building`, `AttackComponent`, `SendBuilding`, `Creep`.
  `Building` and `AttackComponent` must move in the same commit — split, every building would
  advance before any component fires, and a tower finishing an upgrade mid-step changes what its own
  component does. Join the group from `Unit._ready`, which covers `MobileUnit`, `Creep`, `Builder`,
  `Building` and `SendBuilding` at once because all of them call `super()`.
  (b) **Units subtree:** `MobileUnit`, `Builder`.
  (c) **Projectiles subtree:** `Projectile`, `PiercingProjectile`, `BeastCharge`, and
  `GroundHazard`'s `_physics_process` half only — its `_process` keeps the flicker and its own
  `_shown` clock, for the reason its docstring gives. That file is the project's own worked example
  of this split done right.
  (d) **Managers:** `PlayerManager`, `TechManager`.

  Reproduce the three hand-made answers to the `super()` question exactly. `Builder._sim_step` calls
  `super(dt)` as it does today. **`Creep._sim_step` does not**, and the comment saying why —
  MobileUnit walks towards an ordered target and a creep is driven by the area's route instead —
  must be carried onto the new method verbatim, or the next reader restores it and double-walks
  every creep. `Builder` is the regression test for the whole rule: if it stops calling `super` it
  still starts builds when in range and never walks to them, a unit that never arrives.
  *Falsifier per commit:* byte-identical trace against both 6a-0 baselines, and `StepOrderProbe`'s
  dump diffs clean against the recorded one. *Positive control:* the probe's dump is non-empty and
  contains an instance of every class migrated in that commit — an order diff that is clean because
  nothing was recorded is the same green as a pass.

**6a-3 — the delta.** The stepper passes `MatchSession.tick_seconds()`, never the engine delta. At
20 Hz the two are the same float, so the trace must not move — and that is itself a small control
that the authored constant really is the rate the engine is running. **The rename IS the delta
refactor** (amendment 5): once a loop has no `_physics_process`, nothing can hand it an engine
delta, and a site that was missed still has one and is caught by the audit rather than by hoping.

**6a-4 — the authored rate.** `MatchSession.tick_seconds()` stops reading
`Engine.physics_ticks_per_second` and reads a new authored `GameConfig` value; `Creep._aura_phase`
reads the same. Both are I4's named must-fixes. `project.godot`'s `physics_ticks_per_second` then
paces only the engine. `Main._validate_content` warns when the two disagree outside a bench run.
Byte-identical while the numbers agree.

**6a-5 — the clock counts STEPS.** `MatchSession` gains a step count, incremented by the stepper;
`tick()` returns `_turn_ticks` under lockstep and the step count otherwise; `_legacy_tick`,
`_start_frame` and `hold`'s `_pause_frame` refund all go, because a held world now takes no steps
and there is nothing to refund — two mechanisms doing that job would refund time that was never
spent. `_check_clock` stays until the last moment as the comparison and goes with `_legacy_tick`.
*Falsifier:* byte-identical, because at one step per tick a step counter equals the frame delta. If
the trace shifts by exactly one tick uniformly, that is the origin alignment between `Main._ready`
and the first step — seed the counter to close it, do not explain it away.

**This commit is a prerequisite for the next one and the review found that out the hard way.** The
two-rate falsifier cannot run while `_legacy_tick` counts engine frames: `DeterminismBench` is not
on the lockstep path, so `tick()` is the frame count, and at engine 60 / sim 20 the match clock
would run three times fast, moving creep unlocks, Sudden Death, income and `session.tick()` itself,
which is hashed directly. The trace would diverge at the first sample for reasons having nothing to
do with a missed loop, and the signal would be gone.

**6a-6 — the test that can actually fail.** Bench argument `engine_rate=<n>`. Run the bench with the
engine paced at 60 and the authored sim rate pinned at 20, same seed, same sim-step count, and
byte-compare against the run where the two agree. The bench must drive and sample off the stepper's
own step count rather than off `_physics_process` for this run, or the two traces are not sampled at
the same world time and the comparison silently stops meaning anything. **Name the failure before
running it:** a `Projectile` left on Godot's dispatch flies three times as far per sim step and lands
one to three sim ticks early, so the first sampled creep health after the first volley differs and
the trace diverges near the start rather than at the end. If it prints the same thing as the
matched-rate run, either nothing was missed or the world never fired — and 6a-0's positive controls
are what tell you which.

**6a-7 — the guards, because a test proves this commit and an audit protects the next year.**
Three, behind a debug flag:

- **The missed loop.** Walk the match scene at match start and on a slow beat; for each node read
  `get_script()` and its base chain and ask `get_script_method_list()` whether that script declares
  `_physics_process`. A script that does and is not on the presentation allowlist is a `Log.err`
  naming the file. This is the only guard that works against a site nobody has written yet.
- **Membership, asserted at the instance and not at boot.** A boot sweep is worthless here:
  `Main._validate_content` runs inside `Main._ready`, before any creep, tower, attack component,
  projectile or hazard exists, so it would inspect areas, send buildings, builders and the two
  managers and never see the classes that draw the RNG and deal the damage. Worse, it tests the
  wrong direction — the failure that exists is a class that *has* `_sim_step` and never joined the
  group, which is `CLAUDE.md`'s `super()` trap wearing a different hat, and it is live:
  `AttackComponent._ready` has two early returns before any line a join would sit on, and
  `PlayerArea` has no `_ready` at all. Assert membership in each class's own `_ready`, after
  `super()`.
- **Completeness.** Each steppable stamps the step index it was last stepped on; at the end of a
  step the stepper walks `session.unit_ids()` and errs on any registered unit whose stamp is stale.
  This is what catches `SendBuilding` — a registered `Unit` with its own loop that a hierarchy walk
  misses, since it extends `Unit` and not `Building`.

Then re-run the sabotage matrix through the new path, with `skip=` dropping a class from the group
instead, and confirm each one is caught by a guard **before** the trace goes red. A guard that only
fires after the checksum already did adds nothing.

**6a-8 — the lockstep check the bench cannot do.** The determinism bench never touches the lockstep
path, and **one part of 6a is genuinely not bit-identical there.** Today the world steps on every
engine tick whether or not a turn ran; during the opening lead ramp `_advance_turn` returns early
without setting a hold, so the world moves while `_turn_ticks` stays put. After 6a the world steps
only when a turn runs. That is invariant I3 going from nearly-true to true, it is a fix, and it is
invisible to every offline test — so it only gets checked if somebody runs the two-peer headless
harness from section 10 and `Findings/2026-09-05-lockstep-review-2-response.md`'s scenario list.
Clean 1v1, checksums agreeing at every compared boundary, plus a planted desync showing the detector
still reports. Kill any stray relay first and assert the new one listened; a lobby left from the
last run looks exactly like a bug in this one.

**6a-9 — presentation tidy, last.** `StrikeAnimation3D`, `ActionBar` and `SendBar` move to
`_process`; `SlamAnimation3D`'s exported choice of callback collapses to the render frame, because a
node that is data-driven about which clock it is on double-counts in every future audit by grep. The
trace must be unaffected by construction — a diff here means one of them was not presentation.

### 13.4 Phase 6b — catch-up

Three commits change behaviour on purpose. Each lands alone, with its own recorded baseline and a
written explanation of the first differing tick. "A harmless one-tick difference" is the sentence to
refuse.

**6b-0 — death leaves the world at once.** `Unit._die` emits and calls `queue_free()`; the registry
entry only comes back in `Unit._exit_tree`, `Building`'s grid cells only in `Building._exit_tree`,
and `PlayerArea`'s creep list only loses the creep when `child_exiting_tree` fires — all of which
Godot runs when the deletion queue flushes at the END OF THE FRAME. `PlayerArea`'s own docstring
says so: a death does not reach the creep list until the frame ends. **`queue_free` is a per-frame
boundary the simulation silently depends on, and 6b puts two steps inside one frame.** On a catch-up
frame, step 2 sees a tower that is dead, still registered, still holding its cells and still a legal
target, while a peer that did not catch up saw it gone. `PlayerManager.erase_player` already carries
the reasoning in its own comment — generalise it into a single retirement call from `_die`, with
`_exit_tree` calling the same thing idempotently. **Expect a trace diff:** `TargetFinder` filters
dead creeps, but the burn, trample and pierce paths walk `creeps_in_radius` and read
`global_position` without all going through it.

**6b-1 — per-step caches.** `CreepIndex._rebuild_if_stale` keys on `Engine.get_physics_frames()`.
Two steps in one frame share that number, so step 2 answers every targeting, splash, trample, pierce
and burn query from step 1's creep positions. It is the worst single item the audit found and the
grep for `func _physics_process` does not find it. Re-key on the stepper's step index — which is why
13.3 insists the counter increments at the top. Keep `invalidate()`; the frame key was never
sufficient alone, and the render-frame readers still need it. **Re-check `UnitPanel` against the new
key**: `CreepIndex`'s docstring records that reader crashing once on a freed creep. Same commit,
audit every other `Engine.get_physics_frames()` reader. *Positive control:* count index rebuilds and
require one per step — a re-key that never rebuilt is another green whose control never fired.

**6b-2 — the loop.** `_advance_turn` returns whether it ran, and the caller becomes a bounded loop:
run a turn, step the world, advance the clock, repeat while sealed turns remain and the budget
allows. **Never hoist the clock advance out of the loop** — advancing it N times while stepping once
is precisely the divergence this phase exists to remove, and `PlayerManager` is the site that proves
it: it ignores delta entirely and pays income from a `while now >= _next_income_at` drain against
`elapsed_seconds()`, so it is already correct for N steps *provided the clock moved with the world*,
and catastrophically wrong if it did not. It is also the shape every other loop should be measured
against. `TechManager` inherits the same correctness from `session.tick()` for free.

**The rate policy.** Budget an extra step on a fractional credit accumulator, capped at **+50%, not
4x** — section 8's existing number, and it is a FEEL decision, not an implementation one: a tower
defence fast-forwarded through a leak is unreadable, and recovery must not cost the player the
ability to react. **Do not gate catch-up on the machine being CPU-healthy** (amendment 3): that
disables it exactly when it is needed, and `CLAUDE.md` records twelve lanes running about 2x over
the tick budget, so the state is reachable. A peer that cannot sustain the rate cannot play the
match — say so and end it, do not wedge it. The rate is a local decision and peers are explicitly
allowed to differ on it, **provided nothing in the simulation ever branches on it** (I4): not on
`is_stalled()`, not on buffer depth, not on the budget.

**What the player sees, and the parts that are the owner's call rather than the implementer's.**

- **The world runs visibly fast during a burst.** Bounded by the cap. Whether +50% is the right
  number is the feel decision, and it should be judged on a real match with a real leak on screen,
  not on a bench.
- **`WalkAnimation3D` derives gait speed by diffing the unit's position between calls.** Left on the
  engine tick it sees one call covering two steps and reads double speed, so legs whir for the
  duration of a burst. Cosmetic, not a desync, and it is the visible tell that a catch-up is
  happening — which may be desirable. The honest fix is for `MobileUnit` to publish the distance it
  moved last step; whether to fix it or keep it as feedback is the owner's call.
- **`StallPanel` wants a fourth state.** It is on the render frame deliberately, because its whole
  job is to draw while the world is held. "Catching up" is the state it does not yet have.
- **A fairness coupling, and it is a fairness question rather than a correctness one.**
  `UnitPanel`'s hold-repeat runs on `_process`, at the render rate, so a player holding the send key
  during a catch-up burst produces fewer sends per unit of GAME time than a healthy player does. The
  orders still go through `Commands` and are still sealed by the relay, so nothing desyncs. It is
  the same trade FFF-147 records Factorio declining to pay, arriving from the other direction.
- **`notify_lagging` should now be able to clear**, which today it structurally cannot, and
  amendment 10's threshold changes meaning: it stops being a ceiling on permanently accumulated lead
  and becomes a ceiling on lead a peer cannot recover from. Re-derive the number rather than
  inheriting it.

**How it is measured.** First offline, with no relay and no second machine: a bench argument that
makes the stepper deliberately run zero steps on some frames and two on others, seeded from the
bench seed. **The trace must be byte-identical to the plain one-step-per-frame run at the same
seed.** That is the strongest test 6b has and it is available before any network is involved. Then
the two-peer harness with the deliberate 900 ms hitch, judged against
`Findings/2026-09-08-sealed-stream-cutover.md`'s table — same commit, flip the one variable in
place, alternating runs. **The positive control is that the hitching peer's lead comes back down**,
which today it cannot; a run where the lead only grows never exercised catch-up and proves nothing.
And measure the DURATION with `Lockstep.stalled_seconds()`, never the stall count.

### 13.5 The complete site list

This is the checklist. Missing one is a silent desync. The audit behind it has the per-site
reasoning; this is the grouping the work splits along. Nothing here may be skipped because it
"looks like presentation" — four of the loops below are `VisualEffect3D` and all four deal damage.

**Group A — the sim loops that rename to `_sim_step` and join the group.** Areas subtree:
`Scripts/Game/PlayerArea.gd` (rubble), `Scripts/Units/Building.gd`,
`Scripts/Combat/AttackComponent.gd`, `Scripts/Units/SendBuilding.gd`, `Scripts/Units/Creep.gd`.
Units subtree: `Scripts/Units/MobileUnit.gd`, `Scripts/Units/Builder.gd`. Projectiles subtree:
`Scripts/Combat/Projectile.gd`, `Scripts/Combat/PiercingProjectile.gd`,
`Scripts/Combat/BeastCharge.gd`, `Scripts/Combat/GroundHazard.gd` (`_physics_process` half only).
Managers: `Scripts/Game/PlayerManager.gd`, `Scripts/Tech/TechManager.gd`.

**Group B — the driver and the clock.** `Scripts/Game/Simulation.gd` (new).
`Scripts/Game/MatchSession.gd`: the step count, `tick()`, `tick_seconds()` off the config, delete
`_legacy_tick` / `_start_frame` / `_pause_frame` / the `hold` refund / `_check_clock`; `hold` keeps
setting `tree.paused`. `Scripts/Multiplayer/LockstepService.gd`: `_advance_turn` calls the step; 6b
turns it into a bounded loop; `_sample_tick_interval`'s docstring must say whether its percentile is
now per frame or per step, because the numbers in `Findings/2026-09-08-sealed-stream-cutover.md` are
per tick and comparability is the point. `Scripts/References.gd` plus the `node_paths` line of the
`References` node in `Scenes/main.tscn` AND `Scenes/Server/server_match.tscn`.
`Scripts/Multiplayer/CommandService.gd`: no code change in 6a — under lockstep orders arrive through
`apply_turn` and never through the pending queue, and the stepper is a scene node so autoloads still
precede it — but its docstring's claim that the ordering is "free rather than arranged" is now half
the story and must say what actually arranges it.

**Group C — rate and cache readers.** `Scripts/Units/Creep.gd` `_aura_phase` (reads
`Engine.physics_ticks_per_second` to spread aura sweeps, so two machines at different engine rates
sweep on different ticks — a divergence that heals and reopens). `Scripts/Game/CreepIndex.gd`
`_rebuild_if_stale`. Every remaining `Engine.get_physics_frames()` reader.

**Group D — the falsifier.** `Scripts/Tools/DeterminismBench.gd`: the four blind spots, the widened
driver, the positive controls, `skip=`, `engine_rate=`, driving and sampling off the step count. A
new `checksum_state` on `SendBuilding`; `AttackComponent` accessors folded into `Building` and
`Creep`; the unhashed accumulators. `Scripts/Tools/PerfBench.gd` samples around the stepper's call
rather than by `process_physics_priority`, which stops ordering anything the stepper drives.
`Scripts/Dev/StepOrderProbe.gd` (new, and **delete it with the rest of `Scripts/Dev` when done**).

**Group E — 6b only, each its own commit.** Retirement in `Scripts/Units/Unit.gd` `_die` /
`_exit_tree`, `Scripts/Units/Building.gd` `_exit_tree`, `Scripts/Game/PlayerArea.gd`'s creep list.
`Scripts/Components/WalkAnimation3D.gd` and `Scripts/Units/MobileUnit.gd` publishing step distance.
`Scripts/UI/StallPanel.gd`'s fourth state.

**Group F — presentation, moved for hygiene and nothing else, last.**
`Scripts/Components/StrikeAnimation3D.gd`, `Scripts/Components/SlamAnimation3D.gd`,
`Scripts/UI/ActionBar.gd`, `Scripts/UI/SendBar.gd` to `_process`. Everything else on `_process`
stays exactly where it is: camera, input, the build ghost, order markers, the range overlay, impact
and lightning visuals, the whole HUD, and `NetworkService` / `LobbyService` / `MatchStartService`,
whose wall clocks are deliberate and say so in place. `ReplicationService` stays on Godot's dispatch
behind `NetworkConfig.lockstep_enabled`; its `process_physics_priority` stops guaranteeing that it
runs last, so on the replication path the snapshot must be taken after the stepper's call by
arrangement rather than by a priority number. Its own comment records that getting this wrong once
built the snapshot from the previous tick.

### 13.6 Traps

**The ones this change walks straight into.**

- **A green trace whose positive control never fired.** Said three ways in this document already and
  it is still the likeliest way phase 6 goes wrong, because every gate here reads as a pass. One
  question, spent per run: *what in this output proves the thing I am testing executed?* A step
  count, a sample count, a sabotage run that went red. "No errors" is not an answer.
- **`tree.paused` is doing load-bearing work that nothing in the code names.** It is the entire
  mechanism by which a stall and the technology draft stop the world. Explicit stepping deletes it
  for everything the stepper drives, and the network autoloads are all `PROCESS_MODE_ALWAYS`, so a
  stepper written as "step the world N times" simulates straight through a stall — diverging by
  exactly the length of the stall, the one state the phase exists to recover from.
- **An override must call `super()`, and this change makes the trap easier to hit, not harder.**
  Godot calls only the most derived `_physics_process`, which is why `OrderQueue.advance` is called
  from each unit rather than being a loop of its own — and that reasoning stops being true the
  moment a driver *can* call a base-class method. Rewrite the docstring; do not leave it to mislead.
  `Creep` deliberately does not call `super`; `Builder` deliberately does.
- **A node added mid-tick does not step that tick, and the simulation spawns nodes mid-tick
  constantly** — sends, projectiles, hazards, upgraded towers, new buildings. The group snapshot
  preserves it. Any future iteration over a live list breaks it, and the symptom is every send and
  every shot gaining a tick of head start, which is exactly the size of difference that gets
  explained away.
- **`Creep._recycle_into` reparents a leaking creep into the next player's area mid-step and draws
  the shared match RNG doing it.** An area-by-area walk would meet that creep twice in one step and
  draw the RNG in a different order — not a small position error, a desync of the shared stream and
  every damage roll after it. One flat snapshot cannot; that is a positive reason for the group, not
  a convenience.
- **The RNG is drawn from far more places than the attack path.** `AttackHit`, `HitPattern`,
  `TowerBuffs`, six passives including a death passive that draws from inside the loop iterating the
  dead, `TechManager.roll_random_ultimate`, `StartingTech`'s draft roll, and `PlayerArea`'s spawn
  points. Every one rides the step order, and `WorldChecksum._add_rng` hashes the generator state, so
  a reordering is caught on the turn it happens rather than as position drift a minute later. That
  is also why 6a must not reorder anything: an id-ordered walk is the stronger invariant and the
  right eventual destination, but it changes the draw order, so it cannot be the phase whose only
  proof is a byte-identical trace. Half the sim set has no `unit_id` anyway.
- **`process_priority` does not order `_physics_process`,** and two nodes rely on
  `process_physics_priority` today. Both guarantees dissolve when the world is stepped explicitly.
- **A new script in an existing folder is not imported by a `godot --path` run**, and after changing
  a function signature the editor keeps the old parse and reports a bogus "Too many arguments" at
  the call site. Both apply to every commit in 6a-2.
- **`| head` in a bench pipeline discards the answer**, because the summary comes last.

**What the reviews found and the design does not fully solve.**

- **`AttackComponent` is both halves in one loop and 6a leaves it whole.** Its cooldown, scan
  counter, windup and the RNG draw are simulation; `_aim` is barrel rotation and is presentation.
  Splitting it changes behaviour and forfeits byte-identity, so 6a moves it entire — which means
  under 6b a client's barrels are aimed by the sim step and turn N times per frame during a burst.
  Cosmetic, and named as a follow-on rather than fixed. `_advance_windup` writes the windup point
  from the target's position and that write is simulation; it must not be dragged onto the render
  frame when the split finally happens.
- **`AttackComponent` has no authority gate.** Only `Engine.is_editor_hint()`. Under lockstep every
  peer is an authority so it is currently harmless, but the stepper must not assume the gate is
  there, and the replication path still needs it.
- **`PlayerManager` and `TechManager` are outside the two-rate falsifier.** Both ignore delta and
  drain idempotent `while` loops off the clock, so running them three times too often changes
  nothing and no trace can see whether they were migrated. They are covered by the audit and the
  membership assertion, not by evidence. Say so rather than counting them as tested.
- **`get_nodes_in_group`'s ordering is an engine implementation detail, not a documented guarantee.**
  It was verified empirically on 4.7.2 and it matches because no sim node sets
  `process_physics_priority`. If it ever drifts, the fallback is the stepper sorting the snapshot
  itself with the same comparator — same design, one more function — and 6a-2's four prefix commits
  each go red the moment it is wrong.
- **The stepper's position as the first child of the match root is load-bearing and lives in a
  `.tscn`,** where a drag in the scene dock silently undoes it. Assert its index at boot.
- **6b-0's retirement diff will be small, per-unit and easy to wave through.** It must be explained
  unit by unit or it is not landed.

### 13.7 What would make us abandon this

**The two-machine determinism run shows a divergence.** Then lockstep itself is unsound on real
hardware and phase 6 is not the problem to solve — nothing built on top of a simulation that two PCs
compute differently is worth building, and the correct next move is the replication path behind
`NetworkConfig.lockstep_enabled`, which is why it was kept.

**The two-machine run shows the lead never grows.** This is the honest one. Phase 6b exists to give
back input delay that a peer accumulated, and section 8 records that in a healthy local match the
lead never moved off zero in five minutes. If a real match between two real PCs on a real link shows
the same — the lead recovering on its own, or never accumulating past a turn or two — then **6b is
solving a problem this game does not have**, and amendment 10's threshold plus 4c's message are a
complete answer. State the threshold in turns of accumulated lead per match minute **before** the
run, so the measurement can refute the case for catch-up rather than being interpreted afterwards.
6a would still be worth doing on the twelve-player budget alone, but it stops being urgent and
should be scheduled against the spatial hash rather than against the netcode.

> **MEASURED 2026-09-09, and this condition is now half-met.** Playtest 5, two real PCs against the
> rented relay with `sealed_stream` on: the struggling laptop's lead went to 4 turns and **stayed
> there** across 900 turns, dipping to 3 once. It does not accumulate. So the runaway this phase was
> written against does not happen on real hardware, and 6b's stated purpose - giving back delay a
> peer banked - is the wrong description of the problem.
>
> **What the same run also shows is that the 4 turns are worth having back.** Measured input delay
> was 105 ms on the desktop and 300 ms on the laptop, and 4 turns is 200 ms of that 195 ms gap. The
> case for 6b is therefore not "the delay grows" but "one machine carries 200 ms of standing buffer
> it banked at match start and can never drain". That is a smaller and much better defined problem,
> and it may be answerable by the engine-rate servo alone - which needs the delta refactor but NOT
> the dispatch change 13.3 is built around. **Judge 6a and 6b against that reframing before
> starting either.** See `Findings/2026-09-09-sealed-stream-on-two-machines.md`.

**The sabotage matrix cannot be made to go red for a loop.** If a gameplay loop can be disabled
entirely and the trace does not move, the falsifier cannot see that part of the world, and no amount
of care in the refactor substitutes. Either widen the hash until it can, or land that loop's
migration with it written down in the commit message as unproven. Do not proceed on the assumption
that a green run covers it.

**6a cannot be made byte-identical after a fair attempt.** If a commit's trace moves and the reason
cannot be explained to the tick, stop. The claim "this changed nothing" is the only thing standing
between the refactor and every future desync being blamed on it, and a phase that has to be argued
for rather than demonstrated has already lost the property it was built to have.

**The measured cost is worse on the target.** `get_nodes_in_group` allocates and re-sorts whenever
membership changed, which under a full lane is every step. The claim is that this is what the engine
already pays every tick; the claim is untested. Measure it with `Tools/run_bench.ps1` on the server,
paired and alternating on the same commit — a dev PC's answer here is a profile of the platform.

**Catch-up at the cap is unreadable.** If a real leak fast-forwarded at the cap costs the player the
ability to react, the cap comes down until it does not, and if there is no cap at which recovery is
both useful and readable, 6b is the wrong answer and the right one is ending the session cleanly
with amendment 2's drop and 4c's message.
