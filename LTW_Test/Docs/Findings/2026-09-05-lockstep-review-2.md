# A second read of the lockstep build — 2026-09-05

**A READ, not a run.** Nothing was booted, no match was played, and no number below was
measured today. Every claim is traceable to a file and a line, to a primary source, or is
labelled DERIVED with its arithmetic shown. That is the limit of it: a read can prove a code
path exists and can prove a comment false. It cannot prove a match desyncs.

**Deliberately independent of [2026-09-05-lockstep-review.md](2026-09-05-lockstep-review.md)**,
which was read only at the END, to check for overlap rather than to be guided by it. All seven
of its findings are closed or withdrawn by
[2026-09-05-lockstep-hardening.md](2026-09-05-lockstep-hardening.md); everything ranked below
as a bug is new. Two of its *improvements* are re-raised with more weight, and it is said where.

## What was asked

Review the whole multiplayer system again, as unbiasedly as possible, after the hardening pass.
Research the field first so the review is against what lockstep actually is rather than against
this codebase's own reasoning.

## How it was checked

- **Primary sources first**, before any code was opened. Listed at the bottom.
- **The code**, in this order: `LockstepService`, `NetworkConfig`, `WorldChecksum`,
  `MatchSession`, `CommandService`, `Command`, `MatchStartService`, `Main`, `StartingTech`,
  `DesyncNotice`, `NetworkService`, `SessionLog` — then greps for every determinism hazard the
  research names: unseeded randomness, wall-clock reads, `_process` on a gameplay path,
  `Engine.time_scale`, `get_instance_id`, transcendental maths, and iteration and sort order.
- **Godot's own behaviour**, where a finding depends on it: `SceneMultiplayer.server_relay` was
  read in the official class reference rather than assumed, and then corroborated against two
  places in this codebase that already document the same thing.

---

## What the field does, and where this build now sits

| What the field does | This build |
| --- | --- |
| Send inputs only, N turns ahead; every peer runs the same turn | yes, exactly this |
| A central relay that runs no game logic (SC2's topology) | yes, since `ae680f4` |
| Redundancy: re-send the last N turns unreliably beside the reliable word | yes, and on the correct channel |
| The delay adapts to the measured link | yes, and it is a liveness parameter, correctly |
| Turn length ALSO adapts to the slowest CPU (AoE) | no — a slow peer is handled by stalling everyone |
| Checksum the world AND the RNG state | yes, both |
| Out of sync stops the game | yes, `DesyncNotice`, and it ends it for everyone |
| Record the input stream so a desync is reproducible | **no** |
| Hash inputs separately from state, to tell a network bug from a sim bug | **no** |
| Subsystem checksums, so a divergence can be traced to its origin | **no** — one hash of everything |

**The model itself is correctly built.** The turn/schedule/exchange/apply loop is textbook, the
relay decision matches what SC2 does, the unreliable echo beside the reliable word is Gaffer's
redundancy on the right channel, and the determinism discipline — `_physics_process` for
gameplay and `_process` for presentation, explicit `rng` arguments everywhere, `pow` unrolled
into a loop, `sin` replaced by a parabola — is tighter than most shipped RTS code.

**The gaps are not in the model. They are at its edges**: who a turn waits for, who the turn
stream is sent to, what happens when a peer leaves, and what a client is allowed to say.

---

## Finding 1 — a third connection freezes the running match, permanently

**Severity: critical. Reachable today on any server more than two people can reach.**

`LockstepService._expected_peers()` builds the set of peers a turn waits on from the transport:

```gdscript
for id: int in multiplayer.get_peers():
	if id != NetworkService.SERVER_PEER_ID:
		peers.append(id)
```

`SceneMultiplayer.server_relay` is never set to `false` anywhere in this project, and its
default is true — *"Enable or disable the server feature that notifies clients of other peers'
connection/disconnection"*. So **a client's peer list contains every other client connected to
the server, not only the ones in its match.**

The codebase already knows this in two places:

- `NetworkService._link_to`: *"A client holds exactly ONE ENet connection, to the server,
  however many other players Godot has told it about."*
- `NetworkService._on_peer_connected` has an `else` branch that logs `Peer joined <id>` on a
  CLIENT for a non-server peer. That branch only exists because clients see other clients.

D19 runs the lobby and the match in one process, and nothing refuses a connection while a match
is running — `MatchStart.is_busy()` refuses a *second match*, not a *peer*. So:

> Somebody presses **Multiplayer** while a 1v1 is in progress → both players' `_expected_peers()`
> grow to include them → `_is_complete()` never returns true again → `_set_held(true)` → **both
> worlds freeze for the rest of the match**, with the stall panel naming a peer id that is not
> in the match.

The docstring says "every connected **PLAYER**". The code says every connected peer. The roster
is already to hand: `MatchStartService._expected`, and `LockstepService._slot_of_peer` already
walks `session.setup().players`.

**Fix:** intersect `_expected_peers()` with the match roster.

## Finding 2 — the turn stream is broadcast to peers that are not in the match

Same root cause, second symptom. `LockstepService` relays with `receive_turn.rpc(...)` and
`receive_echo.rpc(...)`, and `rpc()` broadcasts to **every** connected peer.

`receive_turn` has no liveness gate. It calls `_record()` unconditionally, and `_record`'s only
guard is `turn <= _last_run_turn`, which on a peer sitting in the lobby browser is `-1` for
ever: `_reset_if_new_match` runs only inside `_physics_process`, behind `_is_live()`, which is
false without a `MatchSession`.

So an idle lobby browser receives the whole match's turn stream, records **every turn of it**
into `_incoming`, and never erases any of it. Unbounded memory growth on a machine that is not
playing, plus the match's entire bandwidth sent to everyone on the server.

Third symptom of the same cause: `_measure_and_announce` takes `worst` across every peer, so
**a person browsing lobbies on a bad connection raises the input delay for the players in the
match.**

**Fix:** `rpc_id` the turn stream to match members only, and gate `receive_turn` and
`receive_echo` on `_is_live()`.

## Finding 3 — the disconnect transition is not turn-synchronised

**Severity: real at 3+ players. 1v1 is immune.**

When a peer drops, every other peer stops expecting it at its own local moment — whenever
Godot's `REMOVE_PEER` notification happens to land. That notification travels on ENet's config
channel; the relayed turn words travel on the reliable channel. **Different ENet channels have
no mutual ordering.**

The race: peer B's last word for turn T is relayed to A and C. A's copy is delayed by a
retransmit and A's `REMOVE_PEER` arrives first, so A drops B from `_expected_peers()`, runs
turn T without B's order, and `_record` then refuses the word when it finally arrives
(`turn <= _last_run_turn`). C received both in order and applied B's order. **Two different
worlds, no stall, no error — found five turns later as an unexplained desync.**

`PLAYER_LEFT` is correctly turn-scheduled and that fix (hardening phase 1) is right. But it
only erases the maze. The **expectation set** is still driven by the local transport rather
than by the turn stream.

**Fix:** the relay decides "B is dropped as of turn T" and broadcasts that as a turn-stream
event; peers keep expecting B — empty — through T-1 and stop at T. `inject()` is already
exactly this shape.

## Finding 4 — turn numbers from a client are unvalidated

`LockstepService.submit_turn` does `_highest_seen = maxi(_highest_seen, turn)` with no sanity
check, and `submit_echo` does the same on the **unreliable** channel.

A modified client sending `submit_turn(2_000_000_000, [...])`:

- **poisons `_highest_seen`**, so `inject()` books every later server order at
  `_highest_seen + SYSTEM_LEAD_TURNS` — a turn no peer will reach. A drop then never applies,
  and **the leaver's maze never disappears for the rest of the match.**
- is **forwarded to every honest peer**, each of which creates an `_incoming[2000000000]` entry
  that `_advance_turn` will never reach and never erase. Spam it and every peer's memory grows
  without bound.

The slot-stamping on the relay is genuinely well done and its reasoning is right. This is the
one thing it does not cover: a client cannot lie about *who* it is, but it can lie about *when*.

**Fix:** reject a turn outside `[_highest_seen - k, _highest_seen + max_delay_turns + k]` at the
relay, and outside `current_turn() + max_delay_turns + k` at each peer.

## Finding 5 — `MatchSession.tick()` is a local engine clock, and is not checksummed

`MatchSession.tick()` derives the simulation tick from `Engine.get_physics_frames()` with a
pause correction, **not** from the turn number.

**It is correct today** — traced independently: `hold()`'s named holders do not clobber
`_pause_frame` on a nested hold, and `_start_frame` absorbs each peer's own stall and draft
time, so `tick()` comes out equal on every peer even though the raw frame counts differ. But
the invariant "tick == turn − turns spent in a non-stall hold" is implicit and unenforced, and
`elapsed_seconds()` drives creep unlocks and Sudden Death.

Meanwhile `WorldChecksum` hashes the RNG state, positions, health, gold, income and lives — and
**not the tick**. So a clock divergence does not report itself; it surfaces later and
indirectly, as position drift with no obvious cause.

**Fix:** put `tick` in the checksum. One line, and it makes a whole class of breakage loud on
the turn it happens. Longer term, derive `tick()` from the turn so it cannot drift at all.

## Finding 6 — no lag-out for a peer that is connected and silent

A stall has no ceiling. `_stall_frames` counts and logs every two seconds and that is all.

The 10 s grace in `MatchStartService` (D26) covers a **disconnect**. It does nothing for a peer
that is connected and simply not producing turns: a wedged game loop, a `DesyncNotice` sitting
open while the player reads it, or Finding 1. Real RTS games drop a peer that has held the
match past a threshold; this one waits for ever.

## Finding 7 — the input delay is dominated by the safety margin, not by the wire

DERIVED, from the code and from the 26 ms link measured in
[2026-09-05-lockstep-hardening.md](2026-09-05-lockstep-hardening.md).

`_one_way_to()` already adds ENet's **full RTT variance** to a **half** RTT. `_wire_budget_ms()`
adds that for both legs. Then `jitter_margin_ms: 20` sits on top of the pair:

```
13 (half RTT) + var   +   13 + var   +   20   ~=  56-66 ms   ->  ceil(/50) = 2 turns
without the flat margin:                          36-46 ms   ->               1 turn
```

That is the difference between a 100 ms scheduling delay and a 50 ms one, on a link whose felt
latency was measured at 111-144 ms. Jitter is being counted three times: once per leg through
the variance, and once flat on top.

`flush_immediately` has already removed the queued-frame wait that the flat margin was partly
paying for, so part of its justification is spent.

**This is the single largest available latency win and it is a config change.** Paired
alternating runs at `jitter_margin_ms` 20 / 8 / 0, per `CLAUDE.md` — and note the same file's
warning that a single median on this link cannot resolve anything smaller than about 35 ms, so
this needs the paired treatment, not a before-and-after. Guessing low costs a one-tick stall
that self-corrects and re-raises the delay; guessing high costs every player 50 ms for ever.

## Finding 8 — the relay's message count is O(N^2) and unbatched

DERIVED, arithmetic shown, not measured.

Per tick each client sends two messages, and the relay answers **each** with a broadcast:
`2 * N^2` packets per tick, each addressed to a different peer, so ENet cannot coalesce them
into shared datagrams.

| | N=2 | N=12 |
| --- | --- | --- |
| relay packets per tick | 8 | 288 |
| relay packets per second | 160 | 5,760 |
| relay outbound, idle match | ~18 KB/s | **~630 KB/s (5 Mbit/s)** |

The echo is roughly 70% of that: it carries four turns' payloads every tick, and the relay
re-broadcasts each peer's whole window to everybody.

**Re-raised from the previous review's improvement #5, higher.** It ranked it as affordable
because "ENet coalesces them into one datagram per peer" — it cannot, because each packet has a
different destination. It is the difference between a relay that costs nothing and one that
costs 5 Mbit/s per match on a rented box.

**Fix:** one `receive_tick(turn, [[peer, payload], ...])` per peer per tick — 12 packets per
tick instead of 288, ~60 KB/s instead of ~630. Flush the batch the moment every expected peer's
word has arrived, which is the normal case when everyone ticks at a shared 20 Hz, so no latency
is lost; a timeout covers the rest. The echo folds into the same batch for free.

Two smaller free wins in the same place: do not broadcast a peer's own word back to it (`_emit`
already recorded it locally), and `ECHO_TURNS: 4` covers three consecutive losses — two covers
one loss with a spare and halves the dominant term.

## Finding 9 — the checksum allocates per unit, four times a second

`WorldChecksum.of` builds a `PackedStringArray` with a `%`-format per unit, and `_point()`
allocates a `PackedFloat64Array` **and** a `PackedByteArray` per unit, then joins the lot into
one large string and hashes it.

At the ten-lane world the hardening pass measured (3000 units), on the default
`checksum_every_turns: 5`, that is roughly six thousand allocations and a several-hundred-KB
string, four times a second — on the machine whose tick budget is already the binding
constraint at 0.47x headroom.

A rolling integer hash over ints is orders of magnitude cheaper and a better hash.

**Re-raised from the previous review's improvement #4, higher**, because the client tick budget
has since been measured and the client is now known to be the bottleneck.

## Finding 10 — no turn-stream recording, and no way to trace a divergence

This is the field's most consistent piece of advice and none of it is here.

The checksum says **which turn** two worlds parted on. It says nothing about **why**, and a
desync reported by a tester is currently unreproducible.

Everything needed already exists: the turn stream **is** the replay format, `MatchSetup` carries
the seed, `DeterminismBench` already accepts `replay=`, and `SessionLog` already has the file
plumbing and already listens to `turn_ready`. Writing `{turn, [orders]}` into that file turns
every desync report into a deterministic repro.

Two cheap companions from the research:

- **Hash the input buffer separately from the state.** If input hashes match and state hashes
  diverge it is the simulation; if input hashes diverge it is the network. Today the two cannot
  be told apart.
- **On divergence, dump the last checksum's `parts` array.** The per-unit strings are already
  built; keeping the last two and writing them on a mismatch turns "the worlds differ" into
  "unit 4471's health differs" for nothing.

## Finding 11 — smaller notes

- **`_compare_turn` takes whoever reported first as the reference**, and one dissenter ends the
  match for everyone. Right at two players, where there is no better answer. At twelve a
  majority vote would eject the odd one out instead of cancelling the match. Ranked-play
  concern only.
- **`delay_turns()` is local and unverified.** A modified client can pick `min_delay_turns` on a
  bad link and take a reaction-time edge while stalling everybody else — indistinguishable from
  a bad connection. The relay could enforce a floor on how far ahead a peer books.
- **`_worst_one_way` is announced as 0** when no peer has a readable RTT yet: `worst` starts at
  0 and unknown peers are skipped, so the announcement is made anyway. Unlikely to bite, since
  ENet seeds RTT at 500 ms, but it errs in the wrong direction — under-estimating the budget is
  what causes a stall.
- **`Scripts/Dev/LockstepProbe.gd` is still autoloaded** in `project.godot`. The previous
  review's Finding 7, still open. `CLAUDE.md` says that folder gets deleted.
- **`Command.tick` still crosses the wire and is read by nothing.** Per order, per peer, per
  turn.
- **`MatchSession.unit_for()` erases stale entries lazily**, so `unit_count()` can transiently
  differ between peers depending on which of them happened to look. Harmless today because
  `WorldChecksum._add_units` re-walks everything, but it is an asymmetry sitting inside the
  checksum path.
- **No adaptation to the slowest CPU.** AoE adapted turn length to *both* ping and sustainable
  frame rate; only ping is measured here, and a slow client is handled by freezing everyone.
  Same throughput, far worse to look at. With twelve lanes measured at 2x over budget this is
  the case that will actually happen. The previous review's improvement #6; the stall panel is
  the cheap half of it and is built.

---

## What was checked and found CLEAN

Negative results, recorded so they are not paid for twice.

- **RNG discipline.** Every simulation path takes an explicit `rng`. The only bare `randf()`
  calls are in `BountyPopup` and `LightningBolt3D`, both presentation, both commented as such.
- **Gameplay / presentation split.** No gameplay in `_process` anywhere. `GroundHazard` is the
  worked example of getting it right: damage in `_physics_process`, flicker in `_process`, and
  it says why.
- **Wall clock.** `Time.get_ticks_msec()` appears only in `SelectionController` (input),
  `LockstepService._report_latency` (diagnostic, and correctly documented as unreachable from
  the simulation) and `SessionLog`.
- **`Engine.time_scale`** is never set. `Engine.get_physics_frames()` outside `MatchSession` is
  used once, in `CreepIndex`, as a per-frame cache stamp rather than as a gameplay input.
- **`get_instance_id`** is used nowhere. That is the classic ordering desync and it is absent.
- **Transcendentals on the simulation path.** The three the previous review found are gone. The
  remaining `atan2` and `sin` calls are turret aim, unit facing and projectile arc height, all
  presentation. `MathsUtil`'s `10.0 ** n` is not reached from gameplay.
- **Sort determinism.** Every `sort_custom` in the simulation sorts a deterministically ordered
  input, so an unstable sort still reproduces. `TargetFinder`'s own warning that
  `PlayerArea._creeps` ordering is load-bearing is correct — and its suggested `unit_id`
  tie-break is worth doing NOW rather than later, because the spatial hash listed under known
  weaknesses in `CLAUDE.md` is precisely the change that breaks it.
- **The pause and hold clock.** Traced independently. Named holders do not clobber
  `_pause_frame` on a nested hold, and `_start_frame` absorbs each peer's own stall time, so
  `tick()` comes out equal across peers. It works. Finding 5 is about making that explicit, not
  about it being broken.
- **Channel separation.** Godot maps reliable and unreliable RPCs to different ENet channels, so
  the echo really can overtake a lost reliable packet. The docstring's claim holds.
- **Checksum timing.** Taken before a turn's orders are applied, at a boundary every peer
  reaches identically. Correct.
- **Slot stamping.** A modified client genuinely cannot order as somebody else.

---

## What is still open, in the order worth doing it

1. **Filter `_expected_peers()` by the match roster, and `rpc_id` the turn stream to members
   only.** Findings 1 and 2. This is a live match-freezing bug the moment three people can reach
   the server at once.
2. **Validate turn numbers at the relay and at each peer.** Finding 4.
3. **Put `tick` in the checksum.** Finding 5. One line.
4. **Paired A/B on `jitter_margin_ms`.** Finding 7. Config only, and the biggest latency win
   available.
5. **Record the turn stream into `SessionLog`.** Finding 10.
6. **Batch the relay, and make the checksum integer.** Findings 8 and 9. Both before twelve
   players is attempted.
7. **Turn-synchronise the drop.** Finding 3. Before three players is attempted.

**The 1v1 milestone is not at risk from any of this except Finding 1**, which will bite the
first time three people are on the server at once.

## Traps

**A transport's peer list is not a match roster.** Findings 1, 2 and part of 3 are all one
mistake wearing three hats: `multiplayer.get_peers()` answers "who is connected to this
process", and every one of those call sites wanted "who is in this match". The two were the
same number in every test ever run, because every headless run was exactly one server and
exactly two clients that were both in the match. **A test topology that never differs from the
assumption cannot falsify it.**

**A docstring that names the right concept is not the code doing it.** `_expected_peers()` says
"every connected PLAYER" and the line under it says every connected peer. This is the same trap
[2026-09-05-lockstep-hardening.md](2026-09-05-lockstep-hardening.md) recorded — *a comment that
asserts an invariant is not the invariant* — hit a third time, and it is already in
`CLAUDE.md`.

**"ENet coalesces them" is only true per destination.** The previous review's improvement #5
under-ranked relay batching on the grounds that ENet would coalesce the broadcast into one
datagram per peer. It cannot: a broadcast is N packets to N different peers, and coalescing
happens within one peer's outgoing queue. Worth knowing before sizing any other broadcast.

## Sources

- [1500 Archers on a 28.8: Network Programming in Age of Empires and Beyond](https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond) — Bettner & Terrano, GDC 2001. The two-turn schedule, the 200 ms turn, speed control from ping AND frame rate, and the 250/500 ms tolerance thresholds.
- [Deterministic Lockstep](https://gafferongames.com/post/deterministic_lockstep/) — Glenn Fiedler. Playout delay buffers, and input redundancy over UDP rather than TCP retransmits.
- [Opinion: Synchronous RTS Engines And A Tale of Desyncs](https://www.gamedeveloper.com/design/opinion-synchronous-rts-engines-and-a-tale-of-desyncs) — Supreme Commander / Demigod. Hash once a second, no recovery, and the dangling-pointer war story.
- [How to Debug Desync in Deterministic Lockstep Games](https://bugnet.io/blog/how-to-debug-desync-in-deterministic-lockstep-games) — subsystem checksums, and hashing inputs separately from state.
- [Lockstep as the RTS Gold Standard](https://www.socratopia.app/library/math-for-game-devs-en/chapter-30) — the SC2 relay topology.
- [Klotho](https://github.com/xpTURN/Klotho) and [GDQuest on deterministic simulation](https://school.gdquest.com/glossary/deterministic_simulation) — why Godot's own float paths are not safe for this, and what fixed point buys.
- [SceneMultiplayer.server_relay](https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html) — the class reference behind Finding 1.
