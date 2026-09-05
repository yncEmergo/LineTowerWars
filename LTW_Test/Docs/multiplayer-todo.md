# Multiplayer: what is left to do

What the networked build still needs, in the order it is worth doing. Written 2026-09-05, at
the end of the lockstep hardening run.

This is a PLAN, not a record. The numbers behind it live in `Findings/` with the dates that
make them honest — this file points at them rather than repeating them, and it should be
edited freely as things land or turn out differently.

`multiplayer.md` is what IS built and why. This is what is not.

---

## 1. Near term

### 1.1 Prove determinism across two machines

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

### 1.3 Redundancy under real packet loss

Every turn word is echoed unreliably beside the reliable one. It is proven to CARRY the data —
a whole match was run with the reliable path disabled — but never tested against actual loss,
because loopback drops nothing. Wants a link conditioner (*clumsy* on Windows) and one run with
a few percent loss injected.

### 1.4 Small hardening, whenever

- **A relay-enforced floor on how far ahead a peer books.** `delay_turns()` is decided locally,
  so a modified client could pick the minimum on a bad link and take a reaction-time edge while
  stalling everybody else — indistinguishable from a bad connection. Nothing to do until
  somebody has a reason to cheat.
- **Majority-vote desync attribution.** With two peers a mismatch says they disagree and never
  which is right. Meaningless below three players.

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
