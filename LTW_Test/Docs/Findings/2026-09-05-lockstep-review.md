# Reviewing the lockstep build against how lockstep is actually done — 2026-09-05

**A READ, not a run.** Every claim below is traceable to a file and a line, or to a primary
source. Nothing was booted, no match was played, and no number here was measured today - the
performance figures are quoted from
[2026-09-03-server-tick-overrun.md](2026-09-03-server-tick-overrun.md) with its date attached,
and the arithmetic built on them is DERIVED and says so.

That is worth stating at the top because it is the limit of the finding: a code review can
prove a code path exists, and can prove a claim in a comment is false. It cannot prove a match
desyncs. Four of the items below are reachable by inspection; one is only suspicious, and each
says which it is.

**Corrected the same day, after review.** Three claims in the first version were wrong and are
fixed in place rather than left standing - the date at the top is still true, and a
known-false claim in a document is worse than an edit. What they were:

1. **A desync DOES stop the match** - `DesyncNotice` has been there since `c7bc6d9` and does
   the right thing. The original Finding 6 said nothing listened. Rewritten below, and the
   reason it was got wrong is now the best example in the Traps section.
2. **The forced-stall worry was tested and is not real.** It was the largest open item; it has
   been answered and moved out of *What is still open*.
3. **Making the server a relay does not shorten the input path.** It cuts stall probability.
   Corrected in Finding 1.

## What was asked

Review the whole multiplayer system as unbiasedly as possible, after two days of work that
went server-authoritative first and cut over to deterministic lockstep on 2026-09-04. Research
the topic first, so the review is against what the field actually does rather than against
this codebase's own reasoning.

## How it was checked

- **Primary sources, first.** The Age of Empires post-mortem, SnapNet's lockstep write-up,
  Gaffer's float-determinism piece, the Gamasutra cross-platform indeterminism article, and two
  open lockstep implementations. Listed in full at the bottom.
- **The code**, in this order: `LockstepService`, `CommandService`, `Command`, `WorldChecksum`,
  `MatchSession`, `NetworkConfig`, `NetworkService`, `MatchStartService`, `StartingTech`,
  `PlayerManager` - then greps for the determinism hazards the research named: transcendental
  maths, unseeded randomness, wall-clock reads, `Engine.time_scale`, and iteration order over
  dictionaries and `get_children()`.
- **The docs**, `multiplayer.md` and `server.md`, read against the code rather than trusted.
- **One probe, after the review was reviewed** - a pauser and a worker with explicit
  `process_physics_priority`, to settle whether `SceneTree.paused` applies within the physics
  frame it is set in. Written, run, recorded below, deleted. It is the only thing here that was
  executed rather than read.

---

## What the field does, and where this build sits

| What the field does | This build |
| --- | --- |
| Send inputs only, N turns ahead; every peer runs the same turn | yes, exactly this |
| Turn length adapts to ping; frames-per-turn adapt to the slowest CPU | delay adapts to ping; the CPU half is handled by stalls instead |
| Bitwise determinism is the contract - fixed point, or a very tight float discipline | float, disciplined, with three live leaks |
| Redundancy: every packet re-sends the last N turns, so one lost packet cannot stall | not done - one reliable send per turn |
| Checksum the world AND the RNG; out of sync stops the game | a desync does stop the game, properly (`DesyncNotice`); the RNG state is missing from the checksum |
| Show a "waiting for players" panel with a drop option | not built - a stall is a silent hard freeze |
| The server is a pure relay, or the game is peer to peer | **the server still simulates the whole world** |

Two numbers from the AoE paper are worth keeping, because they are the counterweight to any
instinct to chase latency further: 250 ms of command latency *"was not even noticed"* in their
own 1997 playtesting, and a consistent slower response beat one that varied. Against that, the
131 ms at 26 ms ping measured in [2026-09-04-input-delay.md](2026-09-04-input-delay.md) is
already better than Warcraft III on Battle.net was for a decade. **The latency work is done.**
Everything below is correctness and scale.

## What is right, and worth not undoing

`LockstepService` is the best-reasoned file in the project, and it is right about things that
have bitten real shipped engines:

- turns are closed as a RANGE rather than one per tick, which is what makes a moving delay safe
- a peer records its own word locally instead of waiting for the relay's echo
- the network clock (`_frames`) is kept separate from the match clock, so a gameplay pause
  cannot deadlock the turns that would end it
- the relay stamps the sender's slot, which is the one thing a checksum cannot catch
- `commands_for` sorts by peer, so two peers cannot apply one turn in two orders

The randomness discipline holds under grep: simulation goes through `MatchSession.match_rng()`
and presentation uses the global `randf()`, with `BountyPopup` and `LightningBolt3D` on the
right side of that line. The registries sort where order feeds a roll - `TechRegistry.all()`,
`path_techs()`, `PlayerTech.owned_ids()`, `MatchSession.unit_ids()` - so a filesystem scan
order that differs between Windows and Linux cannot change which Ultimate is drawn. The lane
shuffle is rolled once on the server and the result sent, rather than re-rolled. Projectile
arcs move `y` only and the hit test is flat, so the `sin` in them really is visual as the
docstring claims.

None of that is luck, and none of it should be given back.

---

## Finding 1 - the cutover did not move the CPU off the server

**Reachable by inspection. This is the big one.**

`multiplayer.md` 4.1 gives the reason D2 changed: *"what lockstep really saves is the SERVER
SIMULATING AT ALL - a lockstep server is a relay that runs no game loop."*

That is not what was built.

- `MatchSession.is_authority()` returns `true` unconditionally when `_lockstep` is set,
  **including on the dedicated server**.
- `Scenes/Server/server_match.tscn` still loads a full `Main.gd` scene, with `PlayerManager`,
  `MatchSession`, `TechManager`, `StartingTech`, areas and builders.
- `LockstepService._expected_peers()` always includes `SERVER_PEER_ID`, so every client waits
  on the server's word for every turn - a word that is always empty, sent every tick.
- `LockstepService._maybe_report_checksum` builds a full `WorldChecksum` on the server too.

So the server carries the same per-creep cost it carried on 2026-09-03, and it is now **on the
critical path of every client's tick**. That changes the failure mode for the worse: under
replication an overloaded server sent late snapshots, which is ugly and non-blocking; under
lockstep an overloaded server produces a hard freeze on every client.

`server.md` still says *"The server is the only machine that simulates."* Which is the
stale-doc failure `multiplayer.md`'s own preamble warns about, arrived at from the other
direction - the doc is accidentally describing the code.

**The decision to make** is which of the two it is meant to be. A real relay drops the server
from `_expected_peers`, loads no match scene, and compares peer against peer. A referee peer is
a defensible choice - it gives a 1v1 a third world to compare against - but then the CPU claim
has to come out of `multiplayer.md` 4.1, because it is not true.

**What relaying does and does not buy, corrected.** It does NOT shorten the input path. An
order still travels client to server to client either way, and `delay_turns()` is sized from
`mine + theirs + margin` whether or not the server is an expected peer - so the latency is
unchanged. What it buys is two other things:

- **Fewer stalls.** A turn waits on every expected peer, and the server is a second independent
  thing that can be late. Its word travels one leg where a client's travels two, so it is
  usually not the binding constraint - which makes this a tail risk rather than a median
  saving, but a tail risk that Finding 1 makes worse, because a CPU-loaded server is exactly a
  server whose word is late.
- **The server stops being a pacemaker.** Its `_frames` clock is independent and offset by
  whenever it entered the match scene. If it lags, every client's clock is dragged down to it
  by the stall-converge mechanism - so today the match runs at the pace of the machine that is
  carrying the most load and has the least reason to.

It also removes the Linux-server-against-Windows-client pairing that Finding 5 is about, which
is the third reason to want it.

### The scaling arithmetic - DERIVED, not measured

From [2026-09-03-server-tick-overrun.md](2026-09-03-server-tick-overrun.md), measured on the
rented Hetzner CX23 on that date: roughly 0.1 ms per creep per tick and 0.15-0.20 ms per tower
per tick, against a 50 ms budget.

Extrapolating those constants to twelve lanes at 200 creeps and 100 towers each:

```
2400 creeps x 0.10 ms  = 240 ms
1200 towers x 0.17 ms  = 204 ms
                        ------
                         444 ms   against 50 ms  ->  about 9x over
```

**That is an extrapolation of somebody else's measurement, onto hardware nobody has run twelve
lanes on.** Trust the shape, not the digits. A gaming PC is perhaps 3-5x a shared vCPU on
single-thread work, which leaves it 2-3x over - and under lockstep every client pays it, not
one server.

The honest reading: **the remaining problem is not networking, it is the per-unit simulation
cost, and lockstep has made minimum spec the binding constraint instead of the server.** AoE
ran 1500 units because a unit cost microseconds of C. The levers, in rough order of payoff:

1. **Stop dispatching `_physics_process` per node.** Thousands of GDScript virtual calls a
   tick, plus `Node3D` transform propagation, is a large share of the budget before any game
   logic runs. One manager iterating flat arrays - creeps as data, `MultiMesh` for the visuals
   - is the change that could buy an order of magnitude. Everything else buys percentages.
2. The spatial hash already recorded as a known weakness in `CLAUDE.md`: `TargetFinder` and
   `Creep._refresh_aura` are the two naive linear scans, and one hash fixes both.
3. GDExtension or C# for the creep tick, if 1 and 2 are not enough.

None of that is lockstep's fault, and none of it is undone by lockstep. It simply has to happen
before twelve players is a real target.

## Finding 2 - a mid-match disconnect desyncs the match

**Reachable by inspection.**

`MatchStartService._on_peer_left` returns immediately unless `multiplayer.is_server()`. It is
the only emitter of `player_dropped`, and no `@rpc` in that file forwards the event - the whole
rpc surface there is readiness, checksum, match start and desync.

`PlayerManager._ready` connects `player_dropped -> erase_player` on **every** machine, but the
signal only ever fires on the server. `erase_player` unregisters and frees every unit the
leaver owned. Its docstring still reads *"a client sees it all vanish through replication like
any other change"* - a replication-era assumption the cutover deleted.

So when a player drops under D14, the server erases their maze and the surviving clients do
not. Divergence, immediately and permanently - and D14 says the match CONTINUES, so the
survivor plays out a match against a world the server no longer shares.

The same root cause reaches the draft. `StartingTech._ready` connects `player_dropped ->
_on_player_dropped`, whose stated job is to stop waiting on a player who crashed. On a client
it never fires, so **one client crashing during a draft holds the remaining clients in a paused
world for the rest of the match** - the exact failure that connection was written to prevent.

**A drop is a world event, so it has to ride a turn.** Broadcasting it as a plain rpc is not
enough: it would be applied on a different tick on each peer, which is the same divergence
arriving more slowly. The shape that works is a synthetic order injected by the server into the
turn stream - a `Command.PlayerAction` the relay writes - so every peer erases the maze on the
same turn.

## Finding 3 - two owners of `set_paused`, and no reference counting

**Reachable by inspection. Latent today, not theoretical.**

`MatchSession.set_paused` is a plain boolean toggle with an early out on no change. It has two
independent callers: `StartingTech._settle` for the technology draft, and
`LockstepService._set_held` for a lockstep stall.

`LockstepService._set_held`'s own comment claims *"a stall and the technology draft cannot
fight over the tree - whoever wants it held has it held."* The code does not do that:

1. draft opens, `set_paused(true)`
2. a stall occurs, `_set_held(true)` - already paused, no-op
3. the stall clears, `_set_held(false)` - **unpauses a match that is still drafting**

That peer's world then advances ticks nobody else runs: income accrues, `elapsed_seconds()`
advances, creep unlocks serve their time. Gold is in the checksum, so this is a desync as well
as a visibly wrong screen.

**And a stall at match start is close to guaranteed**, because peers finish loading at
different wall-clock moments and whichever is ahead stalls until the last one arrives. This is
latent only because `MatchSettings.tech_mode` is authored to `PICK` today. The day a lobby
turns DRAFT on, it fires.

The fix is a set of named holders rather than a bool - `hold(&"draft", true)`,
`hold(&"lockstep", true)`, held while the set is non-empty - which is what the comment already
describes.

## Finding 4 - a stall is invisible, and the player cannot escape it

**Reachable by inspection.**

`turn_stalled` is emitted and **nothing in the shipping build listens to it**; the only
subscriber is `Scripts/Dev/LockstepProbe.gd`, which is scaffolding.

`_set_held(true)` pauses the tree. `RTSCamera` and `CommandController` are both default process
mode, so during a stall the camera stops, the HUD stops, and `GameMenu` - which opens off
`CommandController.escape_unused` - cannot be opened at all. A hard-killed peer takes about
5.6 s for ENet to notice, on top of D26's hold, and for all of it the player sees a frozen
screen with no message and no way out.

Every lockstep RTS ships a "waiting for players" panel with names and a drop button. It is
`PROCESS_MODE_ALWAYS` and it listens to exactly this signal.

**The pattern already exists twice in this project**, which makes this a small piece of work
rather than a new idea: `DraftPanel` and `DesyncNotice` are both instanced in `match_hud.tscn`
at `process_mode = 3`, both raised by a service signal, and `DesyncNotice` is the closer of the
two - a modal that comes up on a network event, says what happened, and offers the way out.
A stall panel is that, non-modal, listening to `turn_stalled` and hidden again on the next
`turn_ready`.

This is the one place `turn_stalled` having no listener is worth reading as unfinished rather
than deliberate: the sibling signal on the same layer already got its screen.

## Finding 5 - three transcendental calls on the simulation path

**Reachable by inspection; the RISK is inferred, not observed. No desync has been attributed to
any of these.**

Under lockstep as built, the peer group is Windows clients plus a Linux server. `pow`, `sin`
and `atan2` are not specified by IEEE-754 - glibc and the UCRT are each free to be a ulp out,
and the primary sources are unanimous that this is where cross-platform lockstep breaks.

- `DamageTable.armor_multiplier` uses `pow(negative_armor_base, -armor)`, and it is called from
  the live damage pipeline. **Armour is an int over a small range**, so an integer loop or a
  lookup table removes the risk entirely for nothing. This is the one worth doing whatever else
  is decided.
- `CreepDive.advance` writes a creep's real position from `sin(PI * progress()) * reach`, and
  position IS checksummed. A ulp there compounds into a range check flipping.
- `MobileUnit` and `AttackComponent._aim` use `atan2` for facing. Harmless **today**, because
  nothing gameplay-relevant reads facing and rotation is not checksummed. That is a rule worth
  writing into the docstring before somebody adds a "must be facing to fire" check.

Making the server a pure relay (Finding 1) removes the Linux-against-Windows pairing outright,
which is a second reason to want it. It does not remove the hazard entirely - two Windows
machines can carry different UCRT versions - but it collapses it a long way.

## Finding 6 - WITHDRAWN. A desync already stops the match

**The first version of this finding said `desync_detected` has no listeners and that a
desynced match carries on silently. That is false, and it was the worst error in the review** -
not an imprecision but the opposite of the truth.

`Scripts/UI/Menus/DesyncNotice.gd` connects to it, and `Scenes/UI/match_hud.tscn` instances the
notice at `process_mode = 3` (ALWAYS), so it survives the hold. It is modal in the strongest
sense the project has: it dims the world, eats every key and mouse event including the ones
that would open the game menu or send a creep, offers no Resume, and leaves the match. That is
precisely what the primary sources prescribe - a desync is unrecoverable, so the game stops.
It has been there since `c7bc6d9`.

**What IS still true, and it is a code fix rather than a finding.** The signal's own docstring
in `MatchStartService` still reads *"Nothing listens yet, and that is deliberate rather than an
oversight: WHAT a desync should do to a running match - end it, keep playing and say so, offer
to quit - is a design decision nobody has made."* That decision has been made, and
`DesyncNotice` is it. The docstring is stale and should be rewritten to point at it - which is
worth doing for its own sake, and worth doing because it is what made this review wrong. See
Traps.

## Finding 7 - `Scripts/Dev/LockstepProbe.gd` is still autoloaded

It is in `project.godot`'s `[autoload]` block and ships in every build. `CLAUDE.md` says
`Scripts/Dev` is scaffolding to delete when the work is done, and the work is done. It also
sits inside the surface `NetworkService.rpc_signature()` scans for D31.

---

## Improvements, ranked by payoff

**1. Redundant turn words.** The single best robustness change available. Every peer sends one
reliable packet per turn, so one lost packet means an ENet retransmit and a visible freeze on
every peer. The standard fix, and what the open implementations do, is to carry the last few
turns' words in every packet, unreliable - and since the payload is EMPTY on the overwhelming
majority of turns, four turns of redundancy costs close to nothing and removes single-loss
stalls outright.

**2. Put the RNG state in the checksum.** `WorldChecksum` hashes positions, health, gold,
income and lives. It does not hash the match generator's state, and a divergent draw COUNT is
the most likely desync there is - it is what happens the instant any presentation path touches
`match_rng()`. It also catches the divergence at the draw, rather than waiting for it to
surface as half a millimetre of position. One line, and it will find the next bug on its own.

Also absent, and worth adding once that is in: mana, cooldowns, status-effect durations, and
build or morph progress. And note that quantising position to a millimetre is HIDING
divergence - under lockstep two peers should agree bit for bit, so the tolerance buys nothing
and costs the early warning.

**3. Flush ENet immediately after `_emit`.** `CLAUDE.md` already records that an rpc is not
sent when it is called; it is flushed at the end of the frame, on both hops.
`ENetMultiplayerPeer.host` is an `ENetConnection`, which has `flush()` - *"Sends any queued
packets on the host specified to its designated peers."* Calling it after `_emit`, and after
the relay in `submit_turn`, is a plausible saving of tens of milliseconds off the measured
figure. **Paired runs, same commit, per `CLAUDE.md` - this is exactly the kind of claim a
single before-and-after cannot support.**

**4. Make the checksum cheap.** `WorldChecksum.of` builds a `PackedStringArray` with a format
call per unit, joins it and hashes the string, and `unit_ids()` sorts the whole registry on
every call. A rolling integer hash over ints is orders of magnitude cheaper and a better hash.
It matters more the closer twelve lanes gets.

**5. Batch the relay.** The server sends one `receive_turn` per sender per turn to every peer,
which is O(N^2) messages at twelve players. ENet coalesces them into one datagram per peer, so
it is affordable, but one batched message per client per turn is cheaper and simpler to reason
about.

**6. Degrade gracefully rather than freezing.** AoE's answer to a slow machine was to lengthen
the turn and cut frames per turn. This build's answer is to freeze and resume, which is the
same throughput and reads far worse. Godot's own physics catch-up already slows a loaded peer's
`_frames`, so the AoE behaviour is half there without its smoothness. The panel in Finding 4 is
the cheap half of the answer.

**7. Smaller things.**

- `Command.tick` crosses the wire and is read by nothing. Documented as reserved; noted only
  because it is per order.
- `_measure_and_announce` gates on `_frames`, which freezes during a stall - so the server
  stops re-measuring the connections exactly when the measurement matters most.
- `NetworkService.rpc_signature()` walks `tree.root.get_children()`, which includes the current
  scene. It works only because no scene root declares an `@rpc`. Worth a line saying so.
- The server contributes no orders, so its own `delay_turns()` is pure overhead. Even kept as a
  peer, it could close through `current_turn + max_delay` unconditionally.

---

## Answered after the review: the stall hold is sound - MEASURED

The review's largest open worry was that `LockstepService._set_held` sets `SceneTree.paused`
from inside `_physics_process`, and that whether Godot applies that within the same physics
frame or on the next one is an implementation detail - because if it were the next one, a peer
that stalls would advance its world a different number of ticks from one that does not, which
is a desync on every hiccup.

**Tested rather than reasoned about, and it is fine.** A two-node probe with explicit
`process_physics_priority`, a pauser and a worker, logging which frames the worker actually
ran:

```
PAUSER: setting tree.paused = true  on frame 3
PAUSER: setting tree.paused = false on frame 6
WORKER RAN ON FRAMES: [1, 2, 6, 7, 8, 9]
```

Frames 3, 4 and 5 are absent, and 6 is present. **Both the pause and the unpause take effect
within the same physics frame they are set in.** So a stalling peer advances exactly zero world
ticks during the stall and resumes on the tick it clears, which is what the design assumes.
The item comes off the list; the probe was deleted, per the `Scripts/Dev` rule in `CLAUDE.md`.

This supersedes the incidental evidence the review was leaning on - the zero desyncs across
7-8 stalls per run in [2026-09-04-input-delay.md](2026-09-04-input-delay.md). That was
consistent with the mechanism being sound and would also have been consistent with it being
broken in a way those runs did not reach. This is not.

## What is still open

- **A lockstep client's tick budget under load**, still, and still the largest open risk in the
  model. Unchanged from `multiplayer.md` 4.1 and from 2026-09-04.
- **Whether the server is a relay or a referee** (Finding 1). Nothing else about the server can
  be sized until that is answered.
- **The per-unit simulation cost.** Everything above is a day of work; this is the one that
  decides whether twelve players is reachable.

## Traps

**A comment that asserts an invariant is not the invariant.** Two of the findings above are
cases where the docstring is right about what SHOULD be true and the code does not do it -
`_set_held`'s "whoever wants it held has it held", and `erase_player`'s "a client sees it all
vanish through replication". Both read as settled when skimmed, which is why they survived the
cutover. This is the same failure `multiplayer.md`'s own preamble records about that file
outliving the code by a day, one level further down: **after a model change, the comments that
assert a property are exactly the ones to re-read, because they are the ones that stop anybody
checking.**

**And then the review fell into its own trap, in the same file.** Finding 6 originally claimed
`desync_detected` had no listeners. The source of that claim was the signal's own docstring -
*"Nothing listens yet, and that is deliberate rather than an oversight"* - which was read,
believed, and never checked with a grep, in a review whose entire method was to grep rather
than believe. `DesyncNotice` had been listening since `c7bc6d9`.

The lesson is not "be more careful". It is that the trap is **stronger than knowing about it**:
the paragraph above was written in the same sitting as the mistake it describes. What actually
prevents it is mechanical, and cheap - **a signal is checked by grepping for its name, never by
reading what it says about itself**, and a docstring asserting that nothing uses a thing is the
single highest-value line in a file to distrust, because it is the only kind of comment that
tells a reader not to look.

**Two of the three corrections came from testing what the review only reasoned about.** The
stall hold above is the clear case: the review reached "this is an engine implementation detail
and I cannot resolve it by reading", which was true, and then filed it as an open risk instead
of spending twenty lines on a probe that answers it outright. **A question a code review cannot
answer is not automatically an open question - it is usually the cheapest thing in the review
to actually measure**, and the boundary of the method is not the boundary of what is knowable
that afternoon.

## Sources

- [1500 Archers on a 28.8 - Bettner and Terrano](https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond)
- [Netcode Architectures Part 1: Lockstep - SnapNet](https://www.snapnet.dev/blog/netcode-architectures-part-1-lockstep/)
- [Floating Point Determinism - Gaffer On Games](https://gafferongames.com/post/floating_point_determinism/)
- [Cross platform RTS synchronization and floating point indeterminism](https://www.gamedeveloper.com/programming/cross-platform-rts-synchronization-and-floating-point-indeterminism)
- [Corrade/netcode-lockstep](https://github.com/Corrade/netcode-lockstep) - the redundancy pattern
- [Klotho](https://github.com/xpTURN/Klotho) - a fixed-point deterministic framework for Godot and Unity
- [Preparing your game for deterministic netcode](https://yal.cc/preparing-your-game-for-deterministic-netcode/)
- [Godot ENetConnection](https://docs.godotengine.org/en/stable/classes/class_enetconnection.html) - `flush()`
