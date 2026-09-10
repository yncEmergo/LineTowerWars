# Multiplayer: what is left to do

What the networked build still needs, in the order it is worth doing. Written 2026-09-05, at
the end of the lockstep hardening run.

This is a PLAN, not a record. The numbers behind it live in `Findings/` with the dates that
make them honest — this file points at them rather than repeating them, and it should be
edited freely as things land or turn out differently.

`multiplayer.md` is what IS built and why. This is what is not.

---

> **The largest item is no longer in this file.** One lagging player currently freezes every
> other player, which is an architectural defect rather than a tuning problem, and the research,
> the code audit, the design and the phased plan for it are all in
> [netcode-rework.md](netcode-rework.md). Start there. **§1.1 and §1.2 below are both
> prerequisites for its phase 4** — §1.1 because the cutover is the change that makes
> cross-machine determinism hardest to test afterwards — and §2.3 and §3 are explicitly deferred
> by it. That plan was revised 2026-09-08 after an implementation audit; read its header note.
>
> **Status 2026-09-08, end of day.** Phase 0 (instrumentation) and phase 1 (turn-derived match
> clock) are BUILT AND COMMITTED, locally — `main` is two commits ahead of `origin/main` and
> nothing is pushed. Phase 1 is proven offline and online-without-a-draft and is **unproven in a
> draft match**, which is the one case its ordering decision turns on. The plan's §8 carries the
> evidence for each and a numbered "What to do next"; start there rather than here.

## 1. Near term

### 1.0 Warm content before it is first used  — DONE 2026-09-06

Playtest 1 froze both players for about a second, five times, and every one was a first
instantiation. The full diagnosis, including the wrong answer that was published first, is in
`Findings/2026-09-06-playtest-1-freezes.md`.

Built: `ContentWarmer`, run by `MatchLoading` before it reports itself loaded. It walks the unit
stats folder and `ContentConfig.shared_config_folder` reflectively, loads every scene and sound
they name on Godot's worker threads while the main thread reflects, and holds the lot statically
for the life of the process so nothing is ever freed and reloaded.

What the paired measurement said, three alternating runs of `warm=off` against `warm=on`, placing
one never-before-seen tower or creep every few ticks with a renderer running:

| | cold | warm |
| --- | --- | --- |
| tick p50 | 0.90 ms | 0.90 ms |
| tick p99 | 11.2-11.5 ms | 7.4-7.7 ms |
| worst tick | 13.5-13.7 ms | 8.8-9.1 ms |

No overlap between the groups, and p50 unchanged - warming should not touch an ordinary tick, and
it does not. The load screen went from about 0.8 s to 1.5 s on the machine that measured it.

Three things worth keeping from doing it:

**The reachability split was designed against a cost that had not been measured, and was dropped
once it was.** Half a second for the whole graph left nothing to split. A plan that survives its
own first measurement is the exception.

**A bench that LOADS is not a bench that DRAWS.** The first version measured `ResourceLoader.load`
only, which under `gl_compatibility` cannot see shader compilation at all - that happens on first
draw. The draw test was written only because the load numbers did not add up against the reported
freeze; it turned out shaders are not a factor here, because the placeholder roster shares one
standard material. The next roster may not.

**It still is not measured on the target.** The whole graph costs half a second here and cost the
tester something like a hundred times more per asset. Warming moves that cost to the load screen
whatever it is, which is why the fix did not need the multiplier to be understood - but a load
screen that is 1.5 s here could be much longer there, and nobody has watched one yet.

### 1.0b Give the jitter margin back some head room  — DONE 2026-09-06, UNVERIFIED under load

`jitter_margin_ms` was 0, set on paired runs that were **headless** - no renderer, so almost no
frame-time variance. That measured the network term honestly and silently zeroed a term that only
exists when something is drawing.

Built: `NetworkConfig.adaptive_local_jitter` and `max_local_jitter_ms`. `LockstepService` keeps a
three-second window of how much longer than a tick each tick actually took and adds the 90th
percentile of it to the wire budget, capped. Zero on a machine that is keeping up, so it costs
nothing in the normal case; a machine in trouble books further ahead for as long as the trouble
lasts. `Lockstep.local_jitter_ms()` is in the session log's health line, which is the thing that
was missing when playtest 1 had to be diagnosed the long way round.

**What is NOT done is measuring it against a real link.** A percentile and a cap were chosen from
the shape of the problem rather than from data, because the only honest data comes from two
machines and there is one here. The next playtest measures it; the health line now carries the
number needed to say whether the cap is right.

### 1.1 Prove determinism across two machines  — DONE 2026-09-09

**The largest untested assumption in the whole system.** Every test ever run has been two
clients on ONE machine — same binary, same libm, same CPU. That is the pairing that cannot
fail, and it is exactly the pairing that proves nothing.

What to do: run a real match between the two dev PCs, with session logging on, and compare the
turn-stream logs. The checksums already carry the RNG state, the match tick and every float
exactly, so a divergence reports itself on the turn it happens.

What could go wrong, in likelihood order: a transcendental somebody adds to the simulation
later (the three that were there are gone and the rule is documented); a different CPU taking
a different path in the same binary; a Godot version mismatch. The audit in
`Findings/2026-09-05-lockstep-review-2.md` found the discipline clean, so the honest expectation
is that this passes — but "expected to pass" and "tested" are different words and only one of
them is worth anything before a public playtest.

**It passed.** Two physical machines against the rented server, twice: 128 compared checksum
turns on the legacy path and 91 on the sealed stream, zero mismatches either time. Stated as a
comparison COUNT rather than as an absence of errors, because a comparison that never ran would
also log nothing. See `Findings/2026-09-09-sealed-stream-on-two-machines.md`.

Still untested: more than two machines, and anything longer than a few minutes.

### 1.2 Instant local feedback on the actions that have it worst

Presentation may answer the player's INTENT immediately; it may never claim the RESULT
(D17, `multiplayer.md` §11.4). Selection, the build ghost, order markers and the range overlay
already do this. Three that do not, and should:

- a grey footprint at the clicked cell the instant a build order is submitted, removed when the
  real building arrives on its turn;
- the send bar's displayed stock decrementing on click rather than on confirmation;
- a tower greying out the instant sell is pressed.

None of them touch simulated state, so none can desync. **This is the cheapest felt improvement
available and it should be done before anything architectural**, because it changes what the
remaining latency actually feels like and therefore how much the rest is worth.

### 1.3 Redundancy under real packet loss  — DONE 2026-09-09

The turn word it described is gone; the sealed stream carries the same idea as
`receive_seal_echo`, which re-sends the last few seals unreliably beside the reliable
broadcast. The channel is the point: a reliable channel is ORDERED, so a re-send inside the
next reliable message could never overtake the loss it exists to cover.

**And it no longer wants a link conditioner.** `NetworkConfig.debug_seal_loss_percent` throws
away arriving seals on purpose — after ENet delivered them, so nothing else can recover them —
which is a stronger test than a conditioner and needs no tooling. At 15%: with the echo, 1148
turns and 0.8 s held, 166 of 166 recovered; without it, 10 turns, 62.2 s frozen, both peers
giving up.

What is still unmeasured is loss on a REAL link, which no injector can stand in for. The
session log's health line carries `echo` as `[recovered, dropped]` now, so the next playtest on
somebody else's connection reports it for the first time.

### 1.4 Small hardening, whenever

- ~~A relay-enforced floor on how far ahead a peer books.~~ **Gone with the cutover.** No client
  names a turn any more, so there is no local booking to game: the relay decides which turn an
  order lands in, from when it arrives. The peer's own lead is a private playback buffer that
  costs only its owner.
- **Majority-vote desync attribution.** With two peers a mismatch says they disagree and never
  which is right. Meaningless below three players.

---

### 1.5 Close phase 1's draft gap  — the immediate next task

`LockstepProbe` cannot resolve a technology draft, so the one case that distinguishes phase 1's
two candidate rules has never been run. Details and the fix in `netcode-rework.md` §8 phase 1.
Small, and it finishes a phase that is otherwise done.

### 1.6 Take phase 0's measurement  — DONE 2026-09-09

Read against a real link across playtests 3 to 5. What it produced: the coupling it was built to
find (a healthy peer losing 5.8 s to a partner that was merely slower), the asymmetry that
replaced it, and the input-delay figures on both machines. The drift half is measured but not
settled — a stable lead and a drift-free pair look the same over a minute, so the servo decision
in `netcode-rework.md` 13.4b rests on the repayment mechanism rather than on a drift number.

### 1.7 Loose ends from the 2026-09-10 audit

Everything the audit confirmed is fixed; these are what it could not reach, in the order worth
doing them. `Findings/2026-09-10-netcode-audit.md` has the reasoning for each.

- **Test the editor against an exported build in one match.** `WorldChecksum` hashes
  `stats.resource_path`, and if an exported pack reports a different path than a run from source,
  every mixed test is a false desync. Export-against-export is proven clean.
- **Retire the dead delay knobs** - `adaptive_delay`, `fixed_delay_turns`, `min_delay_turns`,
  `max_delay_turns`, `jitter_margin_ms` - together with `SessionLog`'s reads of them and the `.tres`
  line, in ONE commit. Removing the exports alone is a runtime error that no parse check catches.
- **Give the seal its own ENet channel.** Every `@rpc` rides channel 0, so a seal can queue behind a
  lobby-list broadcast. Unmeasured, and a protocol change: bump `protocol_version` with it.
- **Measure real packet loss.** The echo is proven against injected loss after delivery; the
  health line's `echo` field is the first report of the real thing, on somebody else's connection.

---

## 2. Mid term

### 2.1 The per-unit simulation cost

**This is the one that blocks everything else**, and it is not a networking problem.

Measured on client hardware in `Findings/2026-09-05-lockstep-hardening.md`: a 1v1 sits
comfortably inside the tick budget, a ten-lane world is about twice over it. Under lockstep
every client simulates every lane, so minimum spec is the binding constraint rather than the
server.

The order that matters, cheapest payoff last:

1. **Stop dispatching `_physics_process` per node.** Thousands of GDScript virtual calls plus
   `Node3D` transform propagation, before any game logic runs. One manager over flat arrays,
   with `MultiMesh` for the visuals. This is the order-of-magnitude change; everything else is
   percentages.
2. The spatial hash already named under known weaknesses in `CLAUDE.md` — `TargetFinder` and
   `Creep._refresh_aura` are two naive linear scans and one hash fixes both.
3. GDExtension or C# for the creep tick, if 1 and 2 are not enough.

**Do 1 before touching 2**, and note that the spatial hash is precisely the change that breaks
`PlayerArea._creeps` ordering — the `unit_id` tie-break that makes that safe is already in
`TargetFinder`.

### 2.2 Consume the turn log

The turn stream is recorded into the session log and nothing reads it back. `DeterminismBench`
already accepts `replay=`. Wiring the two together turns a desync report from a tester into a
deterministic repro, which is the difference between fixing it and shrugging.

### 2.3 Is 20 Hz the right simulation rate?

The tick is a hard floor under input latency: an order can only take effect on a boundary, so
20 Hz costs up to 50 ms on its own whatever the network does. Raising it is not free
(`multiplayer.md` §5.6) and it multiplies the per-unit cost in 2.1. Worth revisiting only
after 2.1, and only if the felt latency still bothers anybody.

---

## 3. The far view: getting below ping

**The ask:** players in Korea, Singapore, Europe and NA in the same match, and input latency
below the raw ping between them. This needs prediction or rollback, and it is worth writing
down properly because the answer is more encouraging than it looks and more expensive than it
sounds.

### 3.1 What rollback actually does, and what it cannot

Rollback (GGPO's model, and Photon Quantum's productised version) applies **your own input with
zero delay** and predicts everyone else's — usually "they did what they did last frame". When
the real remote input arrives and differs, it rewinds to that frame and re-simulates forward.

So the honest statement of what it buys:

- **Your own actions become instant.** That is the whole prize.
- **Other players' actions do not.** Nothing can make them: their input physically cannot reach
  you faster than the speed of light and the routing between you. Korea to Europe is what it
  is.

**For this game specifically, that split is unusually favourable.** In Line Tower Wars you do
not duel the other player in real time. They build in their lane, you build in yours, and what
crosses between you is creeps that then walk for many seconds. A quarter second of extra delay
on *their* actions changes almost nothing about how the game plays. A quarter second on *your
own* clicks is the entire complaint. Rollback fixes exactly the half that matters here, which
is not true of most RTS and is a genuinely good reason to keep it on the table.

### 3.2 The cost, with our own measured numbers

The arithmetic everyone uses: to hide `P` milliseconds of ping at a 50 ms tick you need a
rollback window of `P/50` ticks, and a misprediction costs the whole window re-simulated inside
one tick. Hiding 250 ms — roughly Korea to Europe — is a five-tick window, so a miss costs six
full world ticks inside one 50 ms budget. **Every tick would have to cost under about 8 ms.**

The client tick cost was measured in `Findings/2026-09-05-lockstep-hardening.md`. Against that
8 ms target, a 1v1 is roughly two to three times too slow today, and a ten-lane world about an
order of magnitude. **So rollback is not absurd for a 1v1 — it is one good optimisation pass
away — and it is nowhere near for twelve players.**

And that optimisation pass is **§2.1, which is already on the list for a completely different
reason.** The same work unlocks both. That is the single most useful thing in this document: it
is not a choice between "make twelve players work" and "make global play feel good", it is one
piece of work with two payoffs.

### 3.3 Two things about this game that make it cheaper than the general case

**Inputs are rare, and that is the user's own observation being right.** The published cost
models come from fighting games, where a confirmed input arrives every single frame and a
rollback happens constantly. Here a player acts maybe once every second or two. Predicting "no
input" is correct on the overwhelming majority of ticks, so no rollback happens on them at all.
The *average* cost is close to nothing; only the ticks where somebody actually acted pay, and
they pay a spike of a few ticks' work in one frame. One dropped frame every couple of seconds
is a far better trade than a quarter second of delay on everything, forever.

**Causality is lane-scoped, which the general case does not get.** A tower placement affects
only the lane it is in. A creep send affects only the lane it is sent into. Gold, lives and
income are per player. So a mispredicted input can only invalidate ONE lane's simulation, and a
rollback could re-simulate that lane alone rather than the world — cutting the spike by roughly
the number of lanes.

That is worth distinguishing from Photon's "Prediction Culling", which the research turned up as
their answer to the same cost. Theirs scopes by what is *on screen*, which is an approximation
that can be wrong. Scoping by *causality* is exact: if an input provably cannot reach a lane,
skipping it is not an approximation at all. **This is speculative and unbuilt**, but it is the
strongest structural argument this game has, and it should be the first thing checked if
rollback is ever attempted.

### 3.4 What nobody knows, and I will not pretend otherwise

- **No published performance numbers exist for rollback in a real RTS.** Exactly one has
  shipped it — Stormgate's SnowPlay — and no rollback depth, unit count or CPU cost was ever
  published. Its commercial failure is not evidence about the netcode, and I will not claim it
  is.
- **Snapshot cost is the part most likely to sink it, and it is unestimated.** Rollback needs a
  complete, exact world snapshot every tick and a restore on every miss. This world is hundreds
  of creeps, towers, projectiles, mana pools, status effects, tower buffs, the flow field and
  the RNG. Doing that in GDScript twenty times a second is plausibly a bigger project than the
  entire lockstep migration was, and every new field is a new place to get it wrong. **Estimate
  this before anything else if rollback is ever seriously considered** — it is the number most
  likely to make the decision on its own.
- Whether any rollback library has been run at a 20 Hz tick with a large simulation. Every
  published number assumes 60 Hz and two characters.

### 3.5 Cheaper things to do first, in order

1. **§1.2, instant local feedback.** Costs nothing, risks nothing, and changes what the delay
   feels like. Do this before measuring whether anything else is needed.
2. **Move the relay.** All traffic goes through one machine, so where it sits sets the worst
   path. A relay between Korea and Europe is a much shorter worst-case than one at either end.
   This is a hosting decision, not a code change, and it may be worth more than any amount of
   netcode.
3. **§2.1, the per-unit cost.** Needed anyway, and it is the gate on everything in §3.
4. Only then decide about rollback, with a measured snapshot cost in hand.

### 3.6 My opinion, since it was asked for

**The instinct is right and the reasoning behind it is right.** Rare inputs and predictable
movement genuinely do make this game a better rollback candidate than most, and the lane-scoped
causality makes it better still. It is not a fantasy.

**But it is third in line, not first**, and the order matters more than the destination:

- Most of the *felt* problem at global ping is your own clicks, and §1.2 addresses a real
  portion of that for a day's work and no risk at all.
- The rest is gated on §2.1, which has to happen regardless. There is no version of this where
  rollback is worth starting before that.
- And the honest position on the architecture itself is that **nobody has published evidence it
  works at this scale**, in either direction. That is not a reason to rule it out — it is a
  reason to estimate the snapshot cost before committing, rather than after.

The thing I would most want to avoid is building rollback to fix a latency number that turns
out to be dominated by something cheaper. That has already happened once in this project: the
input delay looked architectural, was assumed to be inherent to lockstep, and turned out to be
almost entirely a scheduling constant plus an off-by-one. It went from 300-400 ms to under
80 ms without a single architectural change. **Measure first, and be suspicious of any latency
that has not been decomposed.**
