# AI rework: an opponent that understands the game

**Written 2026-09-15 for whoever builds the next computer opponent**, possibly an agent with
no memory of the conversation that produced it. Everything needed is here or linked from
here. Read sections 0 to 3 before touching code.

This is a PLAN, not a record. When a phase lands, move what it built into `singleplayer.md`
and strike it here, the way `netcode-rework.md` is handled. It carries no tuning values: where
it names a number it is either a research figure (with the finding it came from) or a default
for something not built yet.

---

## 0. Orientation

A standalone remake of the Warcraft III map **Line Tower Wars**: a free-for-all PvP tower
defence. Each player mazes their own lane and spends gold sending creeps to the next player in a
ring. Sending raises income permanently, so the whole game is the balance between offence and
defence.

Read, in this order:

1. `../CLAUDE.md`: the hard rules. The ones this work touches most:
   - only the authority simulates
   - every order goes through `Commands`
   - no physics
   - `Log.debug` on per-tick paths
   - resources reference scenes by path
   - measure on the target, and pair every measurement
2. `game_rules.md`, sections Core concept, Send topology, Mazing, Creeps, Sending creeps,
   Economy, Life steal and recycling, and Win condition. That is what the AI has to understand.
3. **`strategy.md`: how the game is played WELL.** The expert knowledge (economy balance,
   sending, the maze's evolution and endgame shape, tower roles) that this design turns into
   models, templates and counter tables. Without it the design below is a shape with nothing
   to know.
4. `singleplayer.md`: what the opponent is today and why it is shaped that way.
5. `Findings/2026-09-15-opponent-ai-review.md`: what is wrong with it, file by file.
6. `Findings/2026-09-15-rts-ai-research.md`: how good opponents elsewhere are built, with
   sources.
7. `Findings/2026-09-12-tuning-the-opponent-ai.md`: six things already measured the hard way.

---

## 1. The problem, in one paragraph

The current AI is a rule list with gold floors. It has **no model of the game**. It does not
know how strong its maze is, what is coming at it, what its opponent's maze is weak against, or
what a point of income is worth. So it sends on a fixed clock while a person sends constantly,
builds one tower line because that is first on the menu, stops the maze a third of the way down
the lane, and never reacts to anything. Retuning cannot fix this: every knob moves numbers
around a strategy that cannot win. The parts that connect a brain to a match (the seat, the
order road, the profile, the bench) are sound and stay.

---

## 2. What the research established

Each point below is sourced in the research finding.

1. **Good opponents are hand-written rules on top of a few solid models**, not learned
   policies. AoE2 DE's author rejected machine learning chiefly because nobody can make small
   edits to a learned AI.
2. **A cheap prediction before committing** is what separates the good bots. Brood War bots
   simulate a fight before taking it. The one open LTW-like bot runs a *flood model* of its
   maze: tower damage times time-in-range along the route, against the creeps' health.
3. **Income is the game, and "just enough defence" is the rule good players follow.** Legion TD
   2's official guide: spend just enough to clear your waves and put the rest into income.
4. **Sending in bursts beats sending on a beat.** A burst beat model-picked sends 0-4 in the
   LTW-like bot, and two bots dribbling cheap creeps ran 33 minutes without a single leak.
   **When nothing affordable can leak, a send is an investment**, so buy the best earner.
5. **Answer the defender with SENDS, not by rebuilding your own defence around what is walking
   in your lane.** The LTW-like bot's reactive-defence variant lost 0-12: it answers the wave
   that is already dying.
6. **Mazes come from templates, not runtime optimisation.** Maximising path length is NP-hard,
   and greedy placement stalls well short of a serpentine. Local search belongs offline, to
   improve the templates.
7. **Budgets as shares of income (AoE2's escrow)**, not fixed floors. 0 A.D.'s AI and this
   project hit the same starvation failure.
8. **Difficulty from knowledge, attention and judgement noise**, with the best behaviours kept
   for the top. No hidden bonuses. AoE2 DE, Forza 2023 and Killer Instinct all avoid them.
   Where bonuses exist they are labelled: StarCraft II's "Cheater", Legion TD 2's top tiers.
9. **Mistakes in judgement look human; mistakes in action look broken.** Warcraft III's AMAI
   adds noise to its strength *estimates* below Insane. Weakened chess engines play inhumanly
   and a human-trained one does not.
10. **Learning that works at this scale is offline and statistical**: self-play tuning on a
    fast simulator against a pool of opponents, tables mined from replays, and at most a bandit
    over a small strategy pool.
11. **Validate against people.** AI-vs-AI strength is not human-facing quality.

---

## 3. The design

### 3.1 The shape

Five layers. Each asks only the one below it, and only the bottom one touches the world.

```
   SENSES        AiView           a snapshot of what a PLAYER could see, taken on the beat
      |
   MODELS        LaneModel        how much of creep X does maze M kill, and where it leaks
                 ThreatModel      what is my attacker likely to send at me, and when
                 EconomyModel     what is a point of income worth, given the clock
      |
   STANCE        AiStance         ECO / DEFEND / BURST / LETHAL / PRE_SUDDEN_DEATH / EMERGENCY
   & BUDGET      AiBudget         escrow: each payout split into buckets by the stance
      |
   PLANNERS      opening, send, maze, tower, tech, emergency, micro: each PROPOSES orders, scored
      |          in gold-comparable value; the budget decides which are affordable
   HANDS         AiPacer          human limits: perception delay, decision cycle, order cap
                 AiHand           finds the button and presses it, through Commands (kept)
```

**This is AoE2's two layers made explicit.** The stance and planners are the "script": intent
and priorities. The models are the part AoE2 hard-codes in its engine and this project writes
in GDScript, because nothing in Godot provides them. The planners are small enough that a new
behaviour is still a new rule, which was the point of the rule list and stays the point.

### 3.2 One think pass, narrated

This is what "how does it work at its core" means in practice. Take a Hard AI at minute
eight of a 1v1.

1. **Look.** `AiView` is rebuilt, but only the parts whose source changed:
   - its own gold, income, stock and population
   - its lane's towers and route (rebuilt only when a building went up or came down, which the
     area already signals)
   - what is walking in its lane
   - the table row for each neighbour: lives, income, value
   - the neighbour's maze
   - the match clock
2. **Understand.**
   - `LaneModel` answers from cache: its own maze kills every creep unlocked so far with a
     margin, except that a stream of the newest Fortified creep would leak.
   - `ThreatModel` says its attacker's income has jumped, so a burst is likely within two
     payouts.
   - `LaneModel`, run on the *opponent's* maze, says a flyer send there would leak, because
     the anti-air sits at the bottom where flyers pass it quickly.
3. **Choose a stance.** DEFEND is scored against ECO and BURST, and the current stance gets a
   persistence bonus so it does not flip every pass. The threat margin is thin, so DEFEND wins
   narrowly and moves the escrow toward the defence bucket.
4. **Propose.**
   - The tower planner proposes upgrading the front Archer-line tower into the Cannon branch,
     because splash where the route doubles back is the cheapest fix the lane model found for
     leaks per gold.
   - The send planner proposes banking for a flyer burst.
   - The maze planner proposes the next template cell.
5. **Decide.** The budget pays for the upgrade now from the defence bucket. The flyer burst
   waits in the send bucket until stock and gold cover the pack size the lane model says will
   leak. The template cell waits for the next payout.
6. **Act.** The chosen orders go to `AiPacer`, which releases them after this difficulty's
   decision latency and within its order cap, and `AiHand` presses the buttons exactly as it
   does today.

**Nothing in that pass is a number typed into a difficulty file except the margins, the
latencies and which knowledge a level may use.** That is the whole of section 5.

### 3.3 Senses: `AiView`, and the fairness line

**The AI may read what a player could read from their own screen, and nothing else.** That is
the line AoE2 DE draws (it must see a unit to counter it), and here it is generous, because
this game hides very little:

| May read | May not read |
| --- | --- |
| its own everything | another player's GOLD (the table does not show it) |
| every player's lives, income and value (the table) | another player's STOCK or queued orders |
| every maze in the match (the minimap inspects them) | the match RNG, or any roll before it happens |
| what is walking in any lane | what another player has ordered but not yet placed |
| the match clock and every unlock time | |
| another player's technology, but only as INFERRED from the towers it can see, or as known to everybody in the Random technology mode | another player's research itself (decided 2026-09-15) |

- **Built as a snapshot on the brain's beat,** never by reaching into nodes from inside a
  planner. That keeps the fairness line in one reviewable file and lets a perception delay be
  applied in one place (3.8).
- **Read-only.** The view never writes to the world, draws no random number, and reserves no
  unit id. It is the same contract `MatchRecorder` already follows.
- **Cached by version.** A lane's route and per-tower exposure only change when a building goes
  up or comes down, so the view keeps a maze version per area and recomputes only what it
  invalidated.

### 3.4 Models: the understanding

**These are the heart of the rework and the first thing to build**, because every planner is
only as good as the model it asks. Each model is a pure function of an `AiView`: testable
headless, deterministic, and never touching live state.

#### LaneModel: will this maze kill this send?

For one maze, one creep type and one arrival pattern (a single pack, or a stream):

1. **The route.** Walked from the area's flow field, the same one creeps use. Flyers take the
   straight line from spawn to end instead, because they ignore the maze (`game_rules.md`,
   Creeps).
2. **Exposure per tower.** The length of the route inside the tower's range, divided by the
   creep's speed, is how long the tower can fire at it. It is cached per maze version, so the
   expensive part is done once per build or sale.
3. **Damage per tower against that creep.** Average attack damage times attacks per second,
   through the real `DamageTable` for the armour type, reduced by the armour value. Splash is
   applied against the pack's spread. Towers that cannot hit air contribute nothing to flyers.
4. **Kill capacity.** The sum over towers, turned into "creeps killed" against pack health and
   arrival rate. A stream is limited by damage *per second*, a single pack by damage in
   total, and the model has to tell those apart because **burst sending exploits exactly that
   difference**.
5. **The long tail as corrections, not code.**
   - First version: slows, armour reduction, percentage damage, shields, revives, auras, dodge
     and spell resistance each get a multiplier from a data table keyed by trait.
   - Calibrated by a bench harness (phase 1) that streams a creep type at a saved maze and
     compares the leaks it counts with the model's prediction.
   - **Pin the model's SHAPE, not its digits**, as the LTW-like bot does. Its one fitted
     constant carries the date and the harness it was fitted with.
6. **Where along the route creeps die, and how long they live.** The model does not stop at
   "killed or leaked". It also reports the damage DISTRIBUTION along the route (front-loaded or
   back-loaded) and the expected lifetime of a creep.
   - **This is the single most important reading of a target's maze** (`strategy.md` 3.2 and
     3.3). A front-loaded maze kills cheap creeps fast, frees the sender's population and
     rewards spam. A back-loaded one clogs population and invites attackers followed by a
     flood.
   - Lifetime times pack size is the population a send will occupy, which is what limits
     greedy sending long before gold does.
7. **Key positions: how much each tower is worth to the ROUTE.** For each tower, how far the
   route would shrink if it were destroyed.
   - These are the holes a Phoenix pokes (`strategy.md` 5.3). The worst are the closing wall at
     the bottom, the ends of vertical tower columns, and the horizontal separator.
   - The same number serves both sides: an attacker aims at the biggest, and a defender protects
     and repairs it first.
   - It costs one route search per tower, so it is computed when a maze version changes, spread
     over ticks, and never per pass. `Tools/MazeView --holes` is the offline version of exactly
     this measure.

It reads the tower and creep `.tres` files for stats, so it follows balance changes on its
own. **It is an estimate by design.** A full forward simulation of the lane is ruled out:
per-unit simulation cost is this project's limiting weakness, and 11 AIs doing it would take a
12-lane skirmish down.

#### ThreatModel: what is coming at me?

**Two players matter directly in a ring:** the left neighbour who attacks and the right
neighbour who is the target. In a 1v1 they are the same player. Creeps that leaked the lanes
upstream also arrive, carrying their health.

- **Potential:** from the attacker's income (visible), the clock (which creeps are unlocked)
  and the population cap, the most damaging sends it could afford over the next few payouts.
  This is Legion TD 2's Recommended Value adapted to the ring.
- **Observed:** what has actually arrived, as moving averages. The flyer share, the armour-type
  mix, bosses and attackers.
- **Upstream:** creeps leaking out of the lane before this one, visible as they walk.
- **Output:** an expected and a pessimistic incoming mix over a short horizon. The pessimistic
  one drives defence, because StarCraft II's lesson is to be pessimistic about what you cannot
  see.

#### EconomyModel: what is income worth right now?

- **Payback per creep:** cost divided by income gained per payout, times the payout interval.
- **Remaining useful time.** Sudden Death is a known point: tiers 1 to 3 stop being sendable,
  and tier 4 income is capped above a line (`game_rules.md`, The creep roster). Income bought
  just before it pays back little, and the textbook rule (research §4) is to stop pure-income
  sends when the time left is shorter than the payback. Elimination risk shortens the time left
  too: an AI on few lives should not buy income it will never collect.
- **Output:** a value per gold for an income send, which is what lets a send and a tower be
  compared in one currency.

### 3.5 Stance and budget: this replaces the floors

**Floors decide which rule may spend. They cannot decide how much defence is enough**, and that
is the question the game asks. The replacement is two small parts.

**A stance**, chosen on a slow beat with hysteresis (AMAI's persistence bonus, StarCraft II's
main states):

| Stance | When | What the budget does |
| --- | --- | --- |
| ECO | the lane model says the maze holds against the pessimistic threat | most of each payout into income sends, a trickle into the maze |
| DEFEND | predicted leaks against the pessimistic threat | defence bucket first until the prediction clears |
| BURST | the target's maze has a hole a banked send can exploit | bank stock and gold, then release as one burst |
| LETHAL | a predicted leak covers the target's remaining lives | everything into that send, now |
| PRE_SUDDEN_DEATH | tier 1-3 stock and gold would be stranded by Sudden Death | dump them as pressure before it arrives |
| EMERGENCY | leaking now, few lives left | cheapest immediate fix at the bottom of the lane; never hold gold for a fix it cannot afford |

**An escrow**, AoE2's mechanism: each income payout is split into buckets (sends, maze,
upgrades and technology, emergency) by shares the stance sets. A bucket carries over, and a
bucket's gold may only be spent on its own purpose unless the stance releases it. This keeps
the one real lesson of the floors (no rule may starve another) while letting the split move
with the game.

**The Legion TD 2 rule is the default ECO/DEFEND boundary:** defence is funded to the
pessimistic threat times a safety margin, and everything above that is income. The margin is
a personality value (3.7). It is not a difficulty lever on its own, because a margin that is
too high loses slowly and one that is too low loses fast, and neither is the same as playing
worse.

### 3.6 Planners: the rules, now asking the models

Each planner proposes orders with a value in gold-comparable units and a bucket. None of them
spends: the budget does.

**Send planner**
- **Candidates:** every sendable creep, with stock, population and unlock respected through the
  same `can_execute` the button uses. That much is kept from today.
- **Value:** income value from the economy model, plus pressure value (predicted lives stolen
  on the target's maze times what a life is worth right now, which rises as the target's lives
  fall), minus opportunity cost.
- **Two modes, chosen by the stance:**
  - STREAM: buy the best earner when nothing can leak, because "a send that cannot hurt is an
    investment".
  - BURST: bank to the pack size the lane model says breaks the target's kill rate per second,
    then release.
- **Send ALL THE TIME, across every refilling reserve** (`strategy.md` 3.2). There are no quiet
  stretches. The newest creep is often not the right buy, because its reserve holds only a few,
  and there is always something to send.
- **Spreading the gold is a THREE-WAY constraint, not an optimisation** (`strategy.md` 3.2):
  cheapest-first earns the most, but it costs attention the AI does not have (3.8) and it
  population-blocks. The planner buys up the price list until one of the three binds, and drops
  the cheapest tiers once their extra efficiency stops mattering.
  - **Population binds about once a payout** while spamming for income, so it is checked every
    payout rather than modelled loosely.
  - **An aggressive send is tens of creeps in total**, not a pack or two.
- **Straddle the payout** (`strategy.md` 2.1): spend down to zero just before a payout, then
  spend the payout the moment it lands, so that many creeps arrive as one wave. This is a
  standing technique, not only an opening trick.
- **Stock is a resource too.** A reserve only refills while below full (`game_rules.md`), so
  sitting at full stock wastes it. This is probably why "income per SEND" beat "income per
  gold" in the tuning findings: when stock or time is the limit, the efficient creep is the
  wrong buy.
- **Population, not gold, is usually the greedy limit** (`strategy.md` 3.2). The planner asks
  the lane model how long a creep will live in the target's maze, and against a back-loaded
  maze it stops dribbling cheap creeps that will clog its population. That gold goes to
  attackers and floods instead.
- **The greedy/aggressive balance is the planner's central decision** (`strategy.md` 3.1):
  - always aggressive falls behind in income
  - always greedy lets the defender never upgrade and snowball
  - so pressure is judged by what it FORCES the defender to spend, not only by lives it steals

- **When to lean aggressive: the expert's three triggers** (`strategy.md` 3.1). All three read
  off the table, so none needs hidden information:
  - **the target's maze VALUE for the match time.** An expensive maze for now means lives are
    unlikely to be stolen, so stay greedy.
  - **far behind in income:** stay greedy and catch up.
  - **the target far ahead in income:** pressure them, so they do not win for free.
- **An attack is a SEQUENCE over several payouts, not one send** (`strategy.md` 3.3 and 4.5).
  - It is planned as phases: escort and aura ground creeps, the main creeps, then flyer bursts.
  - It can be CANCELLED part way, which means stopping the aggressive sending, not recalling
    anything. The usual reason is that the AI's own maze needs upgrades first.
  - A save-up attack (several payouts banked for one very large wave) is valid and costly to
    the AI's own income.
  - Massing flyers or very fast creeps against a maze unprepared for that type is an attack of
    its own.
- **Composing an aggressive send**, the rules from `strategy.md` 4.2 and 4.3:
  - armour type chosen against the defender's damage types
  - aura creeps mixed in
  - ground first, then flyers on top
  - stacked against single-target mazes, staggered against area damage
  - **timed to CONVERGE**: send times offset by each creep type's travel time (the maze route
    for ground creeps, the straight line for flyers), so that different creep types meet at
    the depth where the defender's damage is weakest
- **Attackers force the front.** Against a back-loaded maze, attackers make the defender invest
  at the front, and a flood plus flyers then overwhelms the back (`strategy.md` 3.3).
  - **Sending attackers is RARE**, though: it tanks the sender's income, and a good defender
    answers by upgrading (`strategy.md` 4.6).
  - The planner only considers them against a very weak front, and only at the top level.
- **Just enough defence, and a few leaks on purpose** (`strategy.md` 3.5). The ECO/DEFEND
  boundary in 3.5 of this document is "just enough not to leak".
  - At the top level it may accept a small, planned leak rather than overbuild, especially
    against a very aggressive send.
  - The two ways a match is actually lost are both things the stance should watch for:
    overestimating the maze against a strong send, and falling too far behind in income.
- **Ring size is a small modifier at most** (`strategy.md` 3.6): three-player rings favour greed,
  four-player rings favour pressure, and larger rings dilute both.
- **The endgame send pattern is DATA.**
  - Tier 4 sending is an art form whose patterns change with every patch (`strategy.md` 4.5).
    So a pattern is an authored resource, not code: an ordered list of phases, each with a
    composition, a length in payouts and a spacing (stacked or staggered).
  - The first pattern is the expert's: Kodo, Naga and Obsidian escort, Shredders as the main
    body for three to four payouts, then short bursts of Frost Wyrms and Harpies for two to
    three.
  - A patch that moves the meta is then an edit to a `.tres`.
- **Counter-sending belongs here, not in the tower planner.** Flyers into weak anti-air,
  Fortified creeps into a Piercing maze, attackers at a lane whose front towers are cheap. Read
  off the target's maze through the lane model, with a counter table as data (3.9) for the
  cases the model is too coarse to see. **Sends chosen against a SPECIFIC TECHNOLOGY are
  advanced play** (`strategy.md` 4.4) and belong to the top difficulty only.

**Maze planner**
- **Shape from STAGED TEMPLATES.** A maze is not one template but an evolution
  (`strategy.md` 5.1): the shipped blueprints 1 to 4 run from early tier 1 to the endgame
  shape, and an endgame reference maze says which tower stands where.
  - Each stage is a saved `TowerLayout` extended with a ROLE per cell (3.9).
  - Blueprint 1 grows in place into 2. From 2 to 3 and from 3 to 4 a section is SOLD AND
    REBUILT, so moving between stages is a planned sale as well as new builds.
  - **Stages advance on the expert's timings** (`strategy.md` 5.1):
    1. blueprint 1 finished by a few hundred income
    2. then the front, with the first elemental towers
    3. the back during tier 2
    4. later, the tier 1 middle is exchanged, and every Basic tower becomes a Core and an
       elemental tower (a Core morphs at once, because something is always researched)
  - **The easy maze is a LEFT-RIGHT maze built properly** (`strategy.md` 5.5): from the very top,
    with half a cell between the horizontal lines. Today's generated zigzag is the right idea
    with the wrong spacing, and it cannot express a half-cell corridor (phase 0).
- **Size from INCOME, not from the clock or a fixed count.** The LTW-like bot deadlocked with a
  clock-sized maze, and today's AI stops at a fixed one. Grow the maze while the lane model says
  more length buys more kills per gold, and stop when it does not. Exposure saturates once
  ranges cover the route.
- **Order: the stage's own, and row-complete within it.** A partial row adds almost no path,
  because creeps walk around it, so rows go up whole. Any subset of a legal layout is legal, so
  the order never blocks. Within a row, alternate direction (a boustrophedon) so the builder
  does not walk back across the lane after every row. **The builder's walk is the real limit on
  build rate.**
  - **"Front first" is the research's default and NOT the expert's.** Blueprint 1 starts in the
    MIDDLE of the lane on purpose: creeps take longer to reach it, which buys another income
    payout of building before first contact (`strategy.md` 2.1). The meta start puts two
    Sentries down and builds one of blueprint 1's diagonal lines first. Front first applies to
    the easy left-right maze, which starts from the very top.
- **Nothing is struck off for having been ordered.** Kept from today (tuning finding 8).

**Tower planner**
- **Which tower on which cell comes from the ROLE, not from the menu order.** That fixes the
  one-tower-line bug (review G2) at the root.
- **The endgame roles are the expert's** (`strategy.md` 5.2):
  - frontline: holds attackers, Mountain Giants especially
  - attacker sustain: heals towers against the Phoenix
  - attacker debuff: auras cutting creep attack speed and attack damage
  - early control: stuns and current-health damage near the start of the route
  - armour strip: as early as possible, so everything behind hits harder
  - back damage
  - anti-air spread through the maze, with flying priority on
  - **slow coverage**: aura slows placed so the whole maze is covered
  - **stun lines**: Beastmasters linked to fire exactly along a vertical corridor
- **The first elemental towers go where they get the most UPTIME**, usually the middle of the
  maze, never the very front: creeps spawn already inside a front tower's range instead of walking
  the maze in front of it (`strategy.md` 5.1).
- **Discs start at a few hundred thousand income, and are upgraded only in the very endgame**, as
  the last step of finishing the maze (`strategy.md` 6.5). Mostly Earth and Primal by then.
- **Before the endgame**, the generic roles fill the gaps:
  - blocker: the cheapest wall, usually a Basic tower that is replaced later
  - damage: the longest exposure
  - splash: where the route doubles back and creeps bunch
  - anti-air: along the flyer line, which is not the maze route
  - patch: a Basic tower that covers the current technology's weakness
- **No endgame maze keeps Basic towers**, so every Basic cell carries a planned replacement.
- **Until then, Basic towers PATCH the technology's weaknesses and are upgraded as far as the
  weakness needs**, sometimes all the way (`strategy.md` 5.1):
  - Turrets for missing anti-air
  - Cannons for heavy armour and against attackers (Cannons are the quick answer to a Corrupted
    Treant)
  - Crushers and Cannons for missing area damage

  Which technology needs which patch is data in the counter table (3.9), filled in as the
  per-technology notes arrive.
- **Key positions are defended and repaired first** (the lane model's item 7). Divineshrooms
  stand in the row 10-12 separator and at other key positions against the Phoenix
  (`strategy.md` 5.2 and 5.3). A destroyed key tower is rebuilt before anything else the
  moment its rubble clears.
- **Beastmaster lines are the hardest placement in the game** (`strategy.md` 5.4), and a top
  difficulty behaviour:
  - each stands aligned with a vertical line of towers
  - each is linked so its beast runs exactly vertically and catches the corridors on both sides
  - every vertical creep path is covered by at least one
- **Every Hurricane Elemental has flying priority on**, at every level that builds one.
- **Coverage roles are a placement problem, not a per-cell choice.** Slow coverage and
  anti-air spread are solved over the whole route: a set cover of the route cells by aura
  radius, where small gaps are acceptable (`strategy.md` 5.2). The rest are per-cell.
- **Upgrades by leaks prevented per gold** against the pessimistic threat, with the branch chosen
  by role and by what the damage mix is missing.
  - **Do not model the shooting pause.** A tower stops shooting while it upgrades, but the expert
    calls that very marginal, and in practice an upgrade waits for the payout that funds it
    anyway (`strategy.md` 5.5a). Review finding B7 is closed by this.
- **Sell and morph.** Selling outclassed or stranded Basic towers to fund elemental ones is
  standard play (research §4). Selling carries a persistence penalty so the maze does not churn.
- **Discs** go into the holes a template names.
- **It never juggles and never traps creeps**, at any difficulty (decided 2026-09-15). Selling
  and rebuilding to reroute committed creeps is considered bad behaviour and is planned to be
  removed from the game, and trapping creeps inside towers should not happen at all. A sale is
  allowed to change a maze's shape between stages, never to move creeps already walking it.
- **What it must NOT do** is rebuild the defence around whatever is walking in the lane this
  minute. Role coverage should be broad enough that one send type cannot walk through, and the
  pessimistic threat model is what widens it. Reactive over-commitment is the 0-12 result.

**Opening planner** (new, from `strategy.md` 2)
- **The meta start is a SCRIPT, and it is the top levels' opening:**
  - two Sentries
  - the builder sent to the top of the maze on a chained attack order
  - Sheep bought one second before a payout, down to zero gold
  - the Timber Wolf killed by the builder for its bounty
  - one more send from that bounty
- **Scripted rather than planned**, because it is a known sequence tuned by years of testing, and
  a planner reinventing it would do worse. It hands over to the other planners once the first
  wave is dealt with.
- **The builder's attack order belongs here, in the first phases** that build a brain, and not in
  the micro planner at the end. It is part of how the opening pays for itself.
- **Easier levels skip the script:** a left-right maze and slower, smaller sends.

**Tech planner**
- **Open on a damage Ultimate and take a slow tower next** (`strategy.md` 6.2). Prefer openings
  whose requirement already unlocks a slow line, as the Arcane Orb does with the Sludge
  Monstrosity. The Firelord is currently the strongest tower.
- **The first purchase is usually TWO technologies**, reaching another Ultimate or Greater tower,
  at a few hundred thousand income (`strategy.md` 6.3). It is ONE technology earlier when that one
  completes something useful, as the Hurricane opening's step to the Greater Sludge does.
- **The opening Ultimate from a weighted table per personality.** Later, the weights are learned
  from which openings win (section 4). The draft uses the same scoring over the three options
  it is offered, which fixes review B2.
- **Later research only when a planner's proposal needs it**, as an HTN-style decomposition:
  "get tower X" becomes the techs, a Core, and the upgrade walk. `AiHand.branch_reaches` is
  already half of that.

**Emergency rule.** Few lives left and leaking now: the cheapest tower that adds damage at the
bottom of the lane, immediately. Never save for a better one (the LTW-like bot died holding
600 gold).

**Micro planner** (last phase):
- **as a defender, focus the Kodo Beasts** in an endgame wave with tower attack orders. The
  expert calls this something the defender MUST try (`strategy.md` 4.5 and 5.6).
  - Orb Keepers do the focusing (big single-target damage and a stun). Their short range is why
    the tower planner keeps nearly all of them inside a Primal disc's range aura.
  - Area-damage towers are pointed at the biggest clumps.
- steer attacker creeps, and the Phoenix above all, at the key positions (the lane model's item 7)
- aim the Phoenix's dive along a line of key towers
- switch Prioritize on while flyers are in range

This is the one place an order-rate cap matters for fairness.

### 3.7 Personality and randomness

**A difficulty says how WELL an AI plays; a personality says HOW.** Two resources rather than
one, so a twelve-player skirmish at one difficulty is still eleven different opponents. This is
what Bloons TD Battles 2, AMAI and 0 A.D. do.

A personality holds:
- greed (the ECO/DEFEND safety margin)
- burst appetite
- opening-Ultimate weights
- template preferences
- a persistence strength

Continuous values are drawn within a range at match start, as 0 A.D. does.

**Randomness** comes from a `RandomNumberGenerator` the brain owns, seeded from the match seed
and the slot, **never the match RNG** (review B1). It is used for:
- the personality draw
- a weighted pick among proposals scoring within a small band of the best (FAF's tie-break),
  which gives variety without chaos
- the judgement noise in 3.8

**Readable adaptation** is optional and cheap: a short line in the leak log when the AI changes
stance ("building anti-air"). Halo's and F.E.A.R.'s lesson is that players credit only the
intelligence they notice. Whether an opponent should talk at all is a design question
(section 8).

### 3.8 The hands: `AiPacer` and `AiHand`

`AiHand` stays as it is and grows the verbs it lacks: sell, morph back, place disc, Prioritize,
draft pick, attacker and Phoenix orders. **Every one still goes through `Commands`.** That is
what makes cheating structurally impossible, and a rework that gave it up would lose the best
property the current AI has.

`AiPacer` is new and sits between the planners and the hands. It is the human-limits layer
AlphaStar used, and it applies to every difficulty:

- **Perception delay.** The view the models see is the world as it was a moment ago, so a new
  creep type is noticed late, the way a person notices it.
- **Decision cycle.** How often the stance and planners run. For a strategic game the relevant
  human figure is the look-decide-act cycle: StarCraft II telemetry puts it at several seconds
  for low-ranked players and about half that for professionals. Reflex reaction time is the
  wrong figure (research §6).
- **Order cap per window.** Mostly for micro and mass upgrades. The builder's walk and creep
  stock already rate-limit the rest.
- **ONE attention budget shared by attacking and defending** (`strategy.md` 5.6). In the endgame a
  person attacks and defends at once, and defending knocks them out of their sending rhythm. An AI
  that runs perfect Kodo focus and a perfect send pattern in the same seconds is superhuman in a
  way players notice. So micro orders and send orders draw on the same cap.
- **Finding a creep takes time.** A Kodo hidden behind other creeps is not found instantly: the
  pacer adds an acquisition delay to a focus order that grows with how crowded the target is.
  How the game itself should make hidden Kodos clickable is an open design question of the
  project owner's.

### 3.9 Data: what gets authored

**Everything a designer might want to change is a `.tres`**, per `CLAUDE.md`. None of it
references a scene by anything but path.

| Resource | Holds |
| --- | --- |
| `AiDifficulty` | knowledge flags (which models and planners are on), pacing, judgement noise, strategy pool size |
| `AiPersonality` | greed, burst appetite, opening weights, template preferences, persistence |
| `AiConfig` (kept) | the difficulties in dropdown order, and the personalities |
| `AiMazeTemplate` | a `TowerLayout` path plus a role per cell, and which personalities use it. The endgame one is built from the reference maze (`strategy.md` 5.2a) |
| `AiCounterTable` | creep traits to tower roles for defence, maze weaknesses to creep choices for offence |
| `AiModelCorrections` | the lane model's per-trait multipliers and its fitted constant, with the date and harness they came from |
| `AiSendPattern` | one attack as ordered phases: composition, length in payouts, stacked or staggered, and the delay that makes the phases converge (`strategy.md` 4.3 and 4.5) |
| `AiOpeningScript` | the scripted opening (`strategy.md` 2.1): which towers where, the builder's first orders, and the send timing against the payout |

`AiProfile` splits into the first two. Its boot validation carries over, and grows a check that
every template's roles and paths resolve. **Beware the typed-array trap** (`CLAUDE.md`): a
difficulty list that empties silently is a single player screen with nothing in it. Validation
refuses that at boot.

### 3.10 What stays, what goes

| Today | Fate |
| --- | --- |
| `AiDirector` | **kept.** Also picks which brain a seat gets while both exist |
| `AiHand` | **kept, extended** with the missing verbs |
| `AiConfig` | **kept**, lists difficulties and personalities |
| `AiProfile` | **split** into `AiDifficulty` and `AiPersonality` |
| `AiMazePlan` | **grows** into the maze planner; template plus roles; the zigzag stays as fallback |
| `AiPlayer` | **replaced** by `AiBrain`. Kept runnable as the bench BASELINE until the new brain beats every tier of it, then moved to `Archive/` with the README entry that folder asks for |
| `AiBench` | **kept, extended** (phase 0) |
| `MatchRecorder` | **kept**; the raw material for section 4 |
| `CommandService.submit_for` / `submit_player_action_for` | **kept** |

**Class names get an `Ai` prefix throughout**, because `class_name` is global and the game
already has `TechManager` and similar. **Expect many small classes rather than few large
ones**: gdlint's public-method ceiling already flags `PlayerArea` and `Unit`, and a brain that
grows into one file will join them.

---

## 4. How it learns

**Short answer: not at runtime, at first, and on purpose.** A brain that changes itself during
play cannot be hand-edited, debugged or balanced. Supreme Commander 2's developers and AoE2 DE's
author both name that as the cost. So learning happens *offline*, and what it produces is data a
person can read, diff and edit. In the order it is worth doing:

### 4.1 Calibrating the models
**What:** the lane model's corrections and its fitted constant.
**From:** a bench harness that streams creeps at saved mazes and counts leaks.
**When:** phase 1, and again whenever balance changes what a tower or creep is.
**Output:** `AiModelCorrections`.

This is not glamorous, and it is the learning that matters most: every decision downstream
trusts these numbers.

### 4.2 Tuning by self-play on the bench
**What:** personality and difficulty values.
**How:** an evolutionary search (CMA-ES or plainer) over values, scored by *placement*. Never
by lives or kills, which is Supreme Commander 2's commander-flight bug waiting to happen.

**Against a LEAGUE, not against itself:**
- a hall of fame of frozen past bests
- **exploiter profiles** that each do one degenerate thing: flyers only, income only and never
  defending, attacker spam, bank everything for Sudden Death, turtle
- both 1v1 and four-player rings, because they reward different play

Self-play alone leaves blind spots a person finds (research §5).

**Statistics:** paired seeds with seats swapped, and a sequential test (Stockfish's approach)
before accepting a change. Given `CLAUDE.md`'s rule that a measurement is paired or it is
nothing, this is the same rule applied to the AI.

**Output:** better numbers in `.tres` files, reviewed like any other change.

### 4.3 Mining the recordings
Every match is recorded, and a player or the bench can keep one (`MatchRecorder`). **Hundreds
of human matches is enough for statistics and nowhere near enough for a neural policy**:
personalising the human-like chess engine Maia to one player took about 5,000 of their games.
So what gets mined is tables:

- **maze templates:** cluster the mazes players actually build, at the end and part-way
  through, into `AiMazeTemplate` files
- **openings:** which Ultimates people take, and which win
- **send curves:** income against time by skill band, gold banked before a first tier-N send,
  and how sends bunch around payouts and Sudden Death
- **time to counter:** first flyer arrival to first anti-air tower, which is the honest value for
  a difficulty's perception delay
- **sell timing:** when Basic towers go for elemental ones

**The tool is build-time Python in `Tools/ReplayMiner`**, stdlib only, the same shape as
`Tools/ModelGen`. It reads recordings and writes checked-in resources. Nothing at runtime
reaches into `Tools/`.

**Prerequisite: recordings of good human play.** None fitting exist yet.
- Playtest matches are to be kept (decided 2026-09-15). **The user decides per match whether
  it was a serious match that is relevant for learning, or just a test.**
- So the miner reads only matches marked serious, and the mark has to live somewhere a tool
  can read. A filename convention or a line appended to the kept `.jsonl` is enough, and
  choosing between them is part of phase 6.

### 4.4 Adapting within a match
Rules, not learning, and AoE2's shape:
- the threat model's moving averages of what has been sent
- the lane model's correction for the lane it is actually defending (predicted leaks against
  observed leaks)
- stance changes with hysteresis

This is most of what reads as "it adapted to me".

### 4.5 Remembering a player across matches: decided against
**Not built** (decided 2026-09-15). The research option was a small bandit over a handful of
strategies per human, stored in `user://`. It is recorded here so it is not proposed again as
though new.

Variety comes from personalities and the brain's own RNG instead (3.7). The AI starts every
match knowing nothing about who it is playing.

### 4.6 Later, maybe
- **A learned stance selector over scripted planners**, the EA SEED Plants vs Zombies pattern
  (research §4): a small policy picks the stance, everything else stays authored. It is the only
  learned component that keeps the brain editable.
- **k-nearest-neighbour send decisions from recordings** ("what did a person do next in a
  situation like this", as Killer Instinct and Steamhammer do), once there are enough
  recordings.
- **"Play against a friend's ghost"**: a feature, not a difficulty.

**Rejected:** end-to-end reinforcement learning, and language models as players (TowerMind
measured a clear gap to human experts). Cost, retraining on every balance change, and blind
spots.

---

## 5. How difficulty scales

### 5.1 Principles
1. **One brain at every level.** A level switches knowledge on and off and sets how carefully it
   thinks. There is no separate "Easy code".
2. **No bonuses at any level, ever** (decided 2026-09-15), **even if that means the harder
   levels are not challenging in the first iterations.** An Insane AI that wins does so by
   playing better. There is no labelled cheater tier either.
   - The AI cannot cheat by construction (3.8), and that is now a requirement rather than a
     property.
   - If Insane is too easy, the answer is a better brain.
3. **Imperfection lives in JUDGEMENT, never in actions.**
   - An easier AI *misjudges*: noise on the lane model's and threat model's estimates, and a
     longer perception delay.
   - It never builds anti-air against no flyers, never leaves gold idle on purpose, never places
     a random tower.
   - Today's `distraction_chance` (a skipped pass) is the right instinct and becomes perception
     delay.
4. **Easy is capped and simplified, not sabotaged.** AoE2 DE's lower levels cap population and
   skip technologies; StarCraft II's lower levels switch behaviours off. Here that means a
   smaller strategy pool, no counter-sending, no selling, and simpler templates.
5. **The best behaviours are reserved for the top**, as AoE2 DE's Extreme is the only level with
   all its micro.
6. **The ladder must be TRANSITIVE and ANCHORED.**
   - Transitive: every level beats the one below on the bench over paired seeds, and a
     round-robin shows no cycles.
   - Anchored: playtests say where each level sits against people.

   Today's ladder is ordered but not anchored (review B5).

### 5.2 The levers

| Lever | Easy | Normal | Hard | Insane |
| --- | --- | --- | --- | --- |
| Lane model on its own maze | coarse | yes | yes | yes |
| Threat model | observed sends only | observed | observed + potential | observed + potential + upstream |
| Stance | ECO / DEFEND only | + PRE_SUDDEN_DEATH | + BURST | + LETHAL |
| Reads the target maze's damage distribution (front or back) | no | coarse | yes | yes |
| Composes aggressive sends (armour, auras, ground then air, stagger or stack, convergence) | no | simple mixes | yes | yes |
| Sends against a SPECIFIC technology (advanced play, `strategy.md` 4.4) | no | no | no | yes |
| Opening | left-right maze from the top, few sends | blueprint stages, plain sends | blueprint stages, sends timed to payouts | the meta start script (`strategy.md` 2.1) |
| Maze shape | left-right, half-cell corridors (`strategy.md` 5.5) | blueprint stages | blueprint stages | blueprint stages to the endgame maze |
| Roles per cell | template's roles only | yes | yes | yes |
| Sells and morphs | no | no | yes | yes |
| Discs | no | no | yes | yes |
| Key positions defended and repaired first | no | repair only | yes | yes |
| Beastmaster lines (`strategy.md` 5.4) | no | no | no | yes |
| Endgame send patterns (`strategy.md` 4.5) | no | no | simple | full |
| Focusing the Kodos, and other defence micro | no | no | no | yes |
| Straddling payouts to stack sends (`strategy.md` 2.1) | no | yes | yes | yes |
| Deliberate small leaks rather than overbuilding (`strategy.md` 3.5) | no | no | no | yes |
| Sending attackers (rare, against a very weak front) | no | no | no | yes |
| Micro (attackers, Phoenix, Prioritize) | Prioritize only | Prioritize only | basic | full |
| Judgement noise | high | medium | low | none |
| Perception delay and decision cycle | slow | moderate | quick | quick, still human |
| Strategy pool | narrow | some | wide | all |

The names follow `ai_config.tres` today; "Medium" in conversation is "Normal" there.

**Pacing is human at every level**, including Insane (3.8). An opponent that wins on superhuman
speed is exactly what players call unfair, however clean its economy.

**One AoE2 lever needs a decision before it is used:** its lower levels wait to age up until the
human does. The equivalent here would be Easy not unlocking higher send tiers ahead of the
person. That is a mild form of adapting to the player, and it is listed in section 8 rather
than assumed.

### 5.3 How a ladder is accepted
1. **Bench:** a round-robin between every level and the exploiter profiles, paired seeds with
   seats swapped, 1v1 and four-player. Every level beats the one below, and no level loses to an
   exploiter it should handle.
2. **The baseline:** the new Normal beats today's Insane. Until it does, the rework has not
   earned its complexity.
3. **People:** a playtest per ladder change, recordings kept. The question is where each level
   sits: Easy is beatable by a new player, Normal by somebody who knows the rules, Hard needs
   good play, **Insane tries to play like an experienced player** (`strategy.md` 10.4).
   - Recordings of players new to the game are expected from upcoming tests, and are the
     reference for how Easy should look.
   - The income benchmarks in `strategy.md` 3.4 are the reference for how Insane should look.
4. **Human-likeness**, once it matters: anonymised lane recordings, "was this a person?" plus a
   certainty rating, the real question hidden among others (research §6). Expect even humans to
   score well short of certain.

---

## 6. Engineering constraints

- **Determinism.** The brain owns its RNG (3.7). It reads the world but never writes to it
  except through orders. Its own state is deterministic given the setup and the orders so far,
  so the bench stays paired and a replay stays exact.
- **Authority.** Only the machine running the world runs a brain, as today.
- **Replays.** A replay injects the recorded AI orders (they are marked `ai`) and does **not**
  run the brain. That only works once B1 is fixed.
- **Networked AI seats** (not planned, but not to be designed out):
  - The brain runs on one designated peer and its orders go into lockstep with the AI's slot.
  - That needs a sanctioned exception to the server overwriting `player_slot` from the peer
    id, since the relay builds no world and so cannot host the brain.
  - Learned data and the brain's RNG then exist only on that peer, which is fine because the
    orders are what travels.
- **Cost.**
  - A twelve-lane skirmish is up to eleven brains on a player's own PC, which `CLAUDE.md`
    already records as over budget for simulation at that size. So brains are staggered (one
    per tick), the models are analytic and cached per maze version, planners run on the
    decision cycle rather than every tick, and nothing forward-simulates a lane.
  - AoE2 treats about 20 ms per pass as its lag threshold. Here the budget is a small slice of
    a simulation tick that the simulation itself already nearly fills at high player counts.
    It is **measured on the target machine with the bench**, not reasoned about.
- **Logging.** Per-pass decisions use `Log.debug`. A stance change or an opening choice is a
  per-player action and may be `Log.info`.
- **Headless first.** Every model and planner is testable without a renderer. Nothing in the
  brain may depend on anything that reads back from the RenderingServer.

---

## 7. The plan

Each phase has an acceptance test and a **positive control**: the thing in the output that
proves the code under test actually ran (`CLAUDE.md`, Testing). Sizes are rough, so sessions
can be planned around usage:
- **S:** one session, no agents
- **M:** one session, possibly a few agents
- **L:** several sessions

### Phase 0: Baseline and hygiene (S). No behaviour change beyond bug fixes.
- Fix review B1 (own RNG), B2 (draft pick through the profile's Ultimate), B3 (descriptions),
  B4 (stale comments and docs).
- **Give today's Easy the maze the expert describes** (`strategy.md` 5.5):
  - The zigzag's corridor becomes a count of INTERNAL cells, so half a cell can be expressed.
  - Easy builds a left-right maze from the very top with half-cell corridors.
  - This is small and makes Easy look right to a person long before the new brain exists.
- **Bench:**
  - seat-swapped pairs
  - a round-robin and transitivity report
  - a placement-based score
  - a way to seat today's `AiPlayer` against a future `AiBrain`
- **Exploiter profiles** built on today's brain where it can express them (flyers only, never
  defends, attacker spam).
- **Record today's full matrix as the baseline**, in a finding.
- *Positive control:* the report states how many matches ran per pair, with seats swapped.

### Phase 1: `AiView` and `LaneModel` (M). No behaviour change.
- The view, with the fairness table from 3.3 as its docstring.
- The lane model as pure functions, with per-maze-version caching.
- **A flood harness in the bench:** stream creep type X at saved maze M, count leaks, print
  predicted against measured.
- **Calibrate across a spread of the roster:** ground and flyers, each armour type, a shield,
  a revive, a slow-resistant creep.
- **Acceptance:** predicted and measured leaks agree within a tolerance chosen and recorded in the
  finding, across the whole spread, with the misses listed rather than averaged away.
- *Positive control:* the harness prints the number of creeps spawned and killed per case.

### Phase 2: Economy (M). Stance, budget and send planner on its OWN lane only.
- `EconomyModel`, `ThreatModel` (observed and potential), stance with hysteresis, escrow budget,
  send planner (STREAM, BURST, PRE_SUDDEN_DEATH), emergency rule.
- The maze and tower decisions are still today's, so the change is isolated.
- **The opening script** (`strategy.md` 2.1), including the builder's attack order and the
  Timber Wolf, for the top levels.
- **Acceptance:** at equal maze behaviour, the new economy beats today's at every tier on the
  bench. Its income curve is compared against the expert's benchmarks (`strategy.md` 3.4):
  roughly the price of the newest unlocked creep per payout, and 3-4 million at Sudden Death for
  an experienced player. **A target, not a gate**: an early brain that falls short is expected,
  and bonuses are never the fix.
- *Positive control:* per-stance time and per-bucket spend in the bench line.

### Phase 3: Maze and towers (L).
- Roles per cell, `AiMazeTemplate`, stage changes on the expert's timings, row-complete order
  with boustrophedon walking, upgrade by leaks prevented per gold, branch by role, sell and
  morph, discs.
- Key positions (the lane model's item 7): protected, and repaired first.
- Beastmaster lines and Sludge coverage from the endgame reference maze.
- **First templates:** shipped blueprints 1 to 4 as the stages, and
  `ReferencesForClaude/ExampleMazes/example_endgame_maze.tres` (`strategy.md` 5.2a) for which
  tower stands where in the finished maze.
  - **That file cannot be loaded at runtime.** `ReferencesForClaude/` is reference material and
    `export_presets.cfg` excludes it from every build, so a template built from it is COPIED into
    `Resources/` and the copy is what ships. Reading it from where it lives would work in the
    editor and be missing in the game, which is the trap `CLAUDE.md` records for `.tres` files
    in a build. Roles are authored by hand from
  `strategy.md` 5.2, and the sells between stages are planned from the differences between
  consecutive blueprints. `Tools/MazeView` draws any of them.
- **Acceptance:** beats phase 2's brain; no single exploiter profile walks through a completed
  maze.

### Phase 4: Reading the opponent (M).
- Counter-sends from the target's maze, the potential and upstream halves of the threat model,
  LETHAL, and the counter table as data.
- **Acceptance:** beats phase 3's brain. Against a maze deliberately built without anti-air, it
  sends flyers measurably more than against one with it.
- *Positive control:* the count of sends chosen for a counter reason.

### Phase 5: The ladder (M, plus a playtest).
- `AiDifficulty` and `AiPersonality`, `AiPacer`, judgement noise, knowledge flags, the lever
  table in 5.2.
- **Acceptance:** the bench criteria in 5.3, then a playtest to anchor the levels. Old
  `AiPlayer` goes to `Archive/`.

### Phase 6: Learning from data (L).
- `Tools/ReplayMiner`: templates, openings, send curves, time to counter, and everything
  `strategy.md` 10.6 lists as better learned from recordings than from description.
- The offline tuning loop against the league.
- **Needs:** recordings of good human play, marked serious by the user (4.3), which is why
  keeping playtest matches should start now.

### Phase 7: The rest (M each, in any order).
- Micro (attacker steering, Phoenix aim, Prioritize, Beastmaster linking where a template has
  not already set it), readable stance callouts, networked AI seats.

---

## 8. Decisions, and what is still open

### Decided by the user, 2026-09-15
1. **No bonuses at any difficulty**, even if the harder levels are not challenging at first
   (5.1).
2. **The AI does not read another player's research.** It may draw conclusions from the towers
   it sees, and in the Random technology mode (and a mirrored draft, once one exists) the
   technology is known to everybody anyway (3.3).
   - Sending against a specific technology is considered very advanced LTW play (`strategy.md`
     4.4), so it is a top-difficulty behaviour (5.2).
3. **No memory of a player across matches** (4.5).
4. **No juggling and no trapping creeps**, at any difficulty (3.6). The community sees
   juggling as bad behaviour, and it is planned to be removed from the game. Trapping creeps
   inside towers should not happen at all.
5. **Playtest matches are kept**, and the user decides per match whether it was serious enough to
   learn from (4.3).

### Still open
These are the defaults the plan assumes until told otherwise. The gameplay questions (the maze
stages, sending, technology) are in `strategy.md` section 10.

1. **Easy pacing itself to the person** (not unlocking higher send tiers ahead of them,
   AoE2-style)?
   - *Default:* no.
2. **Should the AI announce stance changes** in the leak log or chat?
   - *Default:* no, until it is tested.
3. **AI seats in multiplayer lobbies**, eventually?
   - *Default:* not designed for, not designed out (section 6).

---

## 9. Deliberately rejected, and why

- **End-to-end reinforcement learning, or a language model as the player.** Cost, a black box
  nobody can edit, retraining on every balance change, blind spots a person finds.
- **Forward-simulating a lane inside a think pass.** Per-unit simulation cost is the project's
  limiting weakness. Simulation is used offline to calibrate the analytic model instead.
- **Runtime maze optimisation.** NP-hard, and templates beat greedy placement. Local search
  runs offline, to improve templates.
- **Rebuilding the defence around what is in the lane now.** The measured 0-12. Broad role
  coverage plus a pessimistic threat model instead.
- **Rubber-banding a labelled difficulty.** Players resent an AI that forces an even game.
- **Resource bonuses slipped in quietly.** Beyond being resented, gold compounds through income
  here, so a small bonus snowballs. StarCraft II has to ramp its cheat over twenty minutes for
  the same reason.
- **GOAP.** The decisions are numeric (gold, income, stock), not symbolic preconditions.
- **A labelled cheater tier** (decided 2026-09-15). No bonuses anywhere, even at the cost of a
  hard level that is not hard enough yet.
- **Per-player memory across matches** (decided 2026-09-15).
- **Juggling and trapping creeps** (decided 2026-09-15). Community bad behaviour, planned out of
  the game, and never something the AI does.
