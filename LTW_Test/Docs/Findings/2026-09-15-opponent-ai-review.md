# The opponent AI, reviewed: a sound body with no model of the game

**2026-09-15.** A read of every file the computer opponent is made of, done at commit
`9c4354b` as a starting point for the redesign in `ai-rework.md`. Nothing here was
measured. Where a claim rests on a number, the number comes from `unit_data.md` or from a
`.tres` on that day, and it says so.

Files read: `Scripts/Game/Ai/` (AiDirector, AiPlayer, AiMazePlan, AiHand),
`Scripts/Config/AiProfile.gd`, `AiConfig.gd`, every profile in `Resources/Config/Ai/`,
`Scripts/Tools/AiBench.gd`, and the parts of `CommandService`, `StartingTech`,
`MatchRecorder` and `MatchSession` that the AI touches.

## Verdict

**Keep the body, replace the brain.**

The parts that connect an opponent to the match are well built and should survive any
rewrite: how a seat becomes a brain, how an order reaches the world, how a difficulty is
authored, and the bench that plays one against another. The part that decides what to do has
no model of the game at all. It knows gold, a clock and a list of cells. It does not know how
strong its own maze is, what is coming at it, what its opponent's maze is weak against, or
what a point of income is worth. So no amount of retuning can make it good: every knob moves
numbers around a strategy that cannot beat a person who sends constantly.

That is not a criticism of the first version. It was built to get a match playable, and it
did that. The earlier tuning findings (`2026-09-12-tuning-the-opponent-ai.md`) are a record
of exactly this ceiling being reached from six directions.

## What to keep

1. **Every order goes through `Commands`**, via `AiHand`. The AI pays the same gold, is refused
   the same placements and waits the same build time as a player. It cannot cheat because it
   has no other way in. This is the single best decision in the feature and a rewrite must not
   give it up. It also means the AI's orders appear in a recording exactly like a player's.
2. **Walking the card instead of a table.** `AiHand.build_ability` and `branch_reaches` answer
   "can I press this" the way the server checks it. Resolving a plan's TARGET tower down to
   the tower that can be placed today is the right idea and is reusable as it stands.
3. **The plan asks the area what is standing** rather than remembering what it ordered. That is
   finding 8 of the tuning findings, and it holds for any future planner too.
4. **Difficulty as a `.tres`**, validated at boot, with `selectable` keeping the tutorial's
   sparring partner out of the menu.
5. **The authority guard and the simulation-seconds clock.** Both are correct and both are what
   a networked AI seat would need.
6. **`AiBench`.** Headless, faster than real time, the real match scene. It is the only honest
   way to compare two opponents and it is the harness any learning or tuning will run on.

## Why it plays badly: five gaps

### G1. The economy cannot keep up with a person

**It sends one pack per beat, and the beat is the same twenty seconds for every profile.**
Before `min_towers_before_sending` towers stand it sends nothing at all. Then it buys roughly
the most expensive creep it can afford (`send_efficiency` is 0.1 on every selectable profile,
which in `_pick_send` means "nearly the biggest"), once, and waits for the next beat.

Line Tower Wars is won on income, and income comes from sending. From `unit_data.md` 6.2: a
Sheep costs 10 and grants 2 income, paid every income interval (10 s by default). It pays for
itself in 50 s and then keeps paying for the whole match. A player who spends each payout on
sends grows income by a large fraction every interval until stock or population stops them.
An AI that buys one pack every twenty seconds is not on the same curve. The three gold floors
decide *which rule* may spend, not *how much defence is enough*, so the AI has no way to
notice that it could send far more without leaking.

### G2. Every generated maze is one tower line

With no layout named, and no layout is named on any profile today, `_placeable_for` returns
`offered[0]`, the first tower on the build menu: the Lesser Archer. `cheapest_upgrade` then
picks the cheapest upgrade with a strict `<`. At the 150g tier the Archer's two branches cost
the same, so the tie always goes to the first on the card, the Watch Tower.

So Easy and Normal build a maze made entirely of one Piercing, single-target line. Hard and
Insane are the same apart from the cells aimed at their Ultimate. From the armour matrix in
`unit_data.md` 1.1, Piercing does 80% against Heavy and 66% against Fortified and Hero. That
covers the Mud Golem, the Corrupted Treant and the Rot Golem, three of the last four creeps in
tier 1.
The AI builds no splash, no slows, no armour reduction and no damage type chosen for what
is walking. That is a choice nobody made. It falls out of a menu order and a tie-break.

### G3. The maze stops at the top of the lane

The zigzag lays `zigzag_rows` rows (4 to 6 on the profiles), two player cells apart, so the
maze fills roughly the top third of a 30-row building area and then stops for good. After it
is finished, gold only goes to upgrades and sends. The size came from finding 6, "about fifty
towers in a full match". That number describes the AI's *own* economy, which is G1, and it
was measured before finding 8's bug was fixed.

### G4. It reads nothing

Everything a person uses to decide is public in this game: every player's lives, income and
value are in the table, every maze can be inspected, and a player can see what is walking
down their own lane. The AI reads none of it:

- not the **opponent's maze**, so it cannot send flyers at a lane with no anti-air, or
  Fortified creeps at a lane of Piercing towers
- not **what is in its own lane**, so it cannot build an answer to what it is being sent
- not **leaks or lives**, so it does not react when it is losing
- not the **income column**, so it cannot tell a threat is building before it arrives

### G5. Missing verbs

It never sells, never places a technology disc, never morphs a tower back to its Core, never
sets Prioritize, never steers an attacker creep or aims a Phoenix, never researches after the
opening, and never picks in a draft (see B2).

## Bugs and latent faults

### B1. The AI rolls on the MATCH RNG, which every damage roll also uses

`AiPlayer._physics_process` rolls `distraction_chance` with `MatchSession.match_rng()`. That
stream is shared with damage rolls (`AttackComponent`), crits, spawn-on-death, the draft's
auto-pick and more, and `WorldChecksum` hashes its state. So every skipped-or-not roll moves
every later random number in the match. Three consequences:

- **Bench comparisons are not paired.** Two profiles with different `distraction_chance`
  (Easy 0.35, Normal 0.12, Hard and Insane 0) consume the stream differently. The same seed
  then gives a different sequence of damage rolls, so "pass the same seed to compare two
  tunings" does not control for luck when distraction differs. It still does between two
  profiles that both have zero.
- **A replay that injects the recorded AI orders will desync.** `MatchRecorder`'s own notes
  offer injecting AI orders as one of two ways to replay an AI seat. That way skips the AI's
  rolls, so the stream diverges at the first pass that rolled.
- **A networked AI seat would desync lockstep** for the same reason if only one peer runs the
  brain. That is the obvious design, and `singleplayer.md` §8 names it.

**Fix:** the brain owns a `RandomNumberGenerator` seeded from the match seed and its slot, and
never touches the match stream. This is cheap and should land before anything else.

### B2. A draft waits for the AI, which never picks

`StartingTech._begin_draft` puts every slot in `_pending`, AI seats included, and the AI has
no draft rule. So a skirmish on the Draft technology mode holds the human for the whole draft
timer, and then `_force_remaining_picks` gives the AI a random option. The AI does not get its
profile's Ultimate. The match does not hang, but it waits for no reason.

### B3. Two difficulty descriptions promise what the data does not do

`ai_hard.tres`: *"Builds a maze somebody actually played"*. `ai_insane.tres`: *"The endgame
maze from the first tower"*. Both have an empty `maze_layout_path`. The layouts were removed
in `a251a99` when the bench showed unfinished plans losing, and the descriptions were not
updated. A player reads these on the setup screen.

### B4. Comments and docs that contradict the code

- `AiPlayer`'s class docstring lists the rules as OPENING, MAZE, UPGRADE, SEND and says the
  pass stops at the first rule that spends. `_think` runs SEND, MAZE, UPGRADE, and every one
  gets its turn.
- `_think`'s own docstring still says "stopping at the first one that spent anything".
- `_consider_send`'s docstring says it buys the best income for the gold. The profiles set
  `send_efficiency` so that it buys nearly the biggest.
- `AiProfile.elemental_after_towers` explains itself with "the build rule stops at the entry it
  cannot afford". That stopped being true when the plan became a set.
- `CHAIN_BUILDS` is described as a distance that nothing measures.
- `singleplayer.md` §3 repeats "the pass stops at the first one that spends gold".
- The end of `2026-09-12-tuning-the-opponent-ai.md` has a duplicated, truncated command line.

### B5. The ladder has no human anchor

Every result behind today's difficulties is AI against AI. "Insane beats Hard" shows the
ladder is *ordered*. It says nothing about where any rung sits against a person, and the
user's first impression is that all of them are weak. Nothing in the repository measures an
AI against a human, and the recordings that could do it do not exist yet.

### B6. Two tunings still rest on unverified findings

The tuning findings say that 5 (income per gold is the wrong metric) and 6 (plans must be
short) were measured with the order-is-not-a-tower bug present and were never re-run. The
profiles still set `send_seconds` equal for everybody, `send_efficiency` near zero and short
zigzags because of them.

### B7. Upgrades ignore what is in range

`_consider_upgrade` takes the front-most tower it can afford on every pass, with no check
for creeps in its range. An upgrading tower stops shooting (`game_rules.md`, Upgrading a
tower). The build time is short, so this costs little today. It is still exactly the kind of
thing a model of the lane should know.

### B8. Minor: repeated whole-plan scans (not measured)

`_order_cheapest_affordable` calls `_floor`, and so `_towers_standing` (a walk over the area's
children), once per plan entry. `_saving_for` resolves every entry through the builder's whole
card and upgrade tree. Both repeat on every pass. At today's plan sizes and think rates this
is unlikely to matter. It would matter for a planner that scores many candidate placements,
which is why the rework caches per maze change instead.

## What this means for the redesign

The gaps are not independent. G1 caps the income that would pay for G2's better towers and
G3's longer maze, and G4 is why none of them can react. They share one root: **there is no
model of defence strength, threat or income value to decide with.** So the redesign starts
there, with evaluators the brain can ask, before any new rule is written. See `ai-rework.md`.
