# How good strategy-game opponents are built: research for the LTW AI

**2026-09-15.** A web survey done to design the next computer opponent. It covers Age of
Empires II: Definitive Edition, the rest of the RTS field, PvP tower defence with sending, and
how game AIs learn and scale difficulty. The design that came out of it is `ai-rework.md`, and
the review of today's AI is `2026-09-15-opponent-ai-review.md`.

**Method.** Four research briefs ran in parallel, one per topic, each told to prefer primary
sources and to tag every claim. The load-bearing claims were then re-fetched by hand (see
"What was re-checked" at the end). Numbers here are other games' numbers on the day they were
read. None of them is a value for this project.

**Confidence tags,** kept from the briefs:
- **[confirmed]**: a primary source (developer post, shipped script, paper, official patch
  notes)
- **[likely]**: several secondary sources agree
- **[unverified]**: a single forum post or search snippet

---

## 1. The short answer

**The opponents people call good or human-like are not clever in a mysterious way.** They are
hand-written rule systems sitting on top of a few solid models of the game. They cheat little
or not at all. Their mistakes look human because the mistakes are in *judgement*, not in
execution.

Eight things recur across every good example:

1. **Two layers: rules decide intent, and engine-side executors carry it out.** AoE2's script
   sets percentages and targets while the executable places buildings and picks targets.
   StarCraft II, Supreme Commander and Warcraft III's AMAI are all shaped the same way.
2. **A cheap model of the fight, consulted before committing.** The Brood War bots simulate a
   battle before engaging. StarCraft II compares army strengths with pessimistic thresholds.
   The one open PvP send-TD bot found runs a "flood model" that predicts leaks.
3. **Counters as data tables**, not code: StarCraft II's `AICounterUnitSetup` and AMAI's
   `Strengths.txt`.
4. **Budgets as shares of income** (AoE2's escrow), not fixed thresholds. Both 0 A.D. and this
   project hit the failure where rules starve each other of gold.
5. **Hysteresis and a little randomness.** A persistence bonus on the current plan, and a random
   pick among options that score equally.
6. **Difficulty from knowledge, caps and switched-off behaviours.** The best behaviours are kept
   for the top level. Bonuses are either absent or clearly labelled.
7. **Learning, where it exists, is offline or statistical.** Nothing shipped in the genre learns
   a neural policy at runtime. The Brood War bots keep a win/loss file per opponent. The
   studios that tried black-box learning cite not being able to hand-edit the result.
8. **Validated against people, not only against other AIs.** The AoE2 DE AI sits mid-table on
   the community's AI-vs-AI ladder and is still the opponent players find most human.

---

## 2. Age of Empires II: Definitive Edition

### Who built it
- **Written by Promiskuitiv ("Promi"), AI lead at Forgotten Empires.** He put his own share at
  about 95%. It grew out of his community UserPatch AI, with parts of the HD Edition AI merged
  in. [confirmed] (Spirit of the Law interview, 2020)
- The HD AI was co-written by Promi and Archon, the author of the community AI "The Horde".
  [confirmed]
- The underlying language is still Ensemble's 1999 "Expert System": `.per` files of rules,
  facts, actions and strategic numbers, extended by UserPatch and DE. [confirmed] (CPSB guide;
  airef)
- **Their stated goal:** "as human-like as possible", as strong as possible on Extreme, and as
  fun as possible on every level. [confirmed]
- **Machine learning was rejected** for engine support, compute cost, and above all
  editability: with a learned AI "you're just not able to make any small changes to it".
  [confirmed] (2020 interview)

### Cheating
- **It does not cheat on resources at any difficulty.** Promi: *"The standard AI is never
  cheating resources/technologies/etc, this can be verified in recorded games."* He credits its
  economy to multitasking and to placing drop-sites well. [confirmed, re-checked]
- **One information shortcut:** once it has seen any of your buildings, it knows your
  population counts, but not which units you have. It must see units to counter them.
  [confirmed]
- The 1999 AI did cheat: Hardest got 500 of each resource at the start and on each age-up.
  [confirmed] Adam Isgreen on DE: the old AI "had resources beyond what a normal player would
  have... it saw the whole map", while the new one "actually has to scout". [confirmed]

### What makes it feel human
- **Strategy depends on seat, civilisation and map.** A pocket player goes fast castle and a
  flank player goes early Feudal. On open maps it opens with a scout rush from the pocket about
  15% of the time. [confirmed]
- **Mid-game strategy switches** respond to game state "and for some of these even a small
  random factor". [confirmed]
- **It counters what it has seen.** Five archers seen means "a bigger group is coming" and it
  builds skirmishers or mangonels. Promi admits it can over-counter into a messy army.
  [confirmed]
- **Extreme adds fine unit control:** deer pushing, a militia rush with micro, and quick-walls
  against a rush it has seen coming. It also has Group Micro: focus fire, weighing local
  advantage, hit-and-run, and *"for realism there is a probability of the AI deliberately
  mistiming the formation change"*. [confirmed] (patch 81058)
- It **retreats from hopeless fights** and takes fewer engagements when behind. Villagers seek
  refuge before they are hit. [confirmed] (patches 34055, 35584, 37650)
- **Lower difficulties wait to age up until the human does.** [confirmed, re-checked]
- It resigns when a game is lost. [confirmed]

### How it runs
- **A rule list.** `(defrule <facts> => <actions>)` fires on every pass while its facts hold. A
  pass checks every rule, top to bottom, "as often as several times a second". [confirmed]
- **A pass over about 20 ms starts causing lag.** Expensive searches go behind 2-3 second
  timers. [confirmed] (airef)
- **State lives in "goals"** (integer variables), set by rules and read by later rules, often
  after a random roll picks a strategy. [confirmed]
- **Load-time specialisation** by civilisation, map and difficulty, and `load-random` picks a
  whole strategy file. [confirmed]
- **Escrow** reserves a percentage of each income for a named purpose. [confirmed]
- **Strategic numbers steer engine subsystems the script does not code:** villager split,
  attack-group size and share, response to sighted enemies, and building placement bands.
  [confirmed]
- **Direct Unit Control** (`up-find-local`, `up-target-objects`) is where the human-like micro
  comes from. Without it, attacks "would just send them into the enemy town center".
  [confirmed]

### Difficulty
- **Engine-side:**
  - build and research time is slower at the bottom [likely]
  - Easiest and Standard pick up targets at a shorter range [confirmed]
  - attack-group sizes are scaled down on low levels unless the script opts out [confirmed]
- **Script-side:** caps on civilian and military population, some technologies never
  researched, fancy micro off, and hit-and-run "toned down massively". **Extreme is "the only
  one that contains all of the fancy unit micro"** and plays "at full power". [confirmed]
- **Tuned by player feedback, not against rating bands.** Players said HD's Standard AI made a
  good training partner and HD's Moderate was already too aggressive, so DE smoothed the
  curve. [confirmed]
- In hindsight Promi said HD would have been better if it "adapt[ed] a little bit to what's
  happening in the game". [confirmed]
- **No official human rating per level exists.** Community estimates conflict. One puts Extreme
  near 1725 on the HD scale; forum consensus says Extreme is no challenge above about 1200 and
  plays like an 800-900 player who executes build orders perfectly but predictably.
  [unverified]

### Learning, and weaknesses
- **Within a match it adapts by rules only:** counters, strategy switches, retreats, answers to
  raids. [confirmed]
- **Across matches: nothing.** The 1999 `sn-track-player-history` never worked. [confirmed]
- The community project AlphaScripter evolves `.per` scripts by genetic algorithm through
  self-play, for the 1999 game. [confirmed]
- **On the AI-vs-AI ladder,** narrow tuned community AIs (Rehoboam and others) beat the DE AI.
  The DE AI's strength is breadth: it still places in the top four of multi-map events.
  [confirmed]
- **Known exploits:**
  - villagers running back and forth under attack [confirmed]
  - over-countering [confirmed]
  - predictability, tower rushes pulling many villagers, and feeding armies into walls
    [unverified]

---

## 3. The rest of the RTS field

### StarCraft II's built-in AI
- **Ten levels:** Very Easy to Elite, then Cheater 1 (Vision), Cheater 2 (Resources) and
  Cheater 3 (Insane). The API names are offset from the in-game names. [confirmed]
- **The cheater resource bonus ramps over time,** from the shipped `MeleeAI.galaxy`:
  - Resources: 1.0x for two minutes, rising to 1.5x at twenty minutes
  - Insane: 1.2x rising to 2.0x at twenty minutes

  [confirmed, re-checked] Vision is a per-difficulty flag. [confirmed]
- **Elite and below get no bonuses and are held back instead.**
  - Forced worker and defence delays on the low levels.
  - No extra tech buildings below Medium.
  - About 36 behaviour flags per level: kiting, fleeing, danger-map pathing, retreat maths,
    proxy scouting. One comment says extra scouts "waste a ton of APM… so we only use this on
    high APM melee difficulties".

  [confirmed] An APM limiter exists; its values were not found. [unverified]
- **Attacking under fog is deliberately pessimistic.** With cheat vision it feels stronger above
  an evaluation ratio of 110 and weaker below 90. Without vision the thresholds are 150 and
  100, because "we're likely underestimating the enemy". [confirmed]
- **Build styles are selectable** (Rush, Timing, Aggressive, Economic, Air). A Blizzard
  developer: higher difficulties get "a much wider variety of build orders". [confirmed]
- **Countering is a table:** per enemy unit, build this many of that counter. [confirmed]

### Brood War and StarCraft II bot competitions
- **Persistent files between rounds** since AIIDE 2012. Bots use them to pick a strategy against
  the same opponent, "which typically increased their win rates over time". [confirmed]
  (Churchill/Čertický survey, IEEE ToG 2018)
- **AIIDE 2017:** Iron led without learning and its win rate "slowly dropped". Two learning bots
  overtook it around round 85 of 110. [confirmed]
- **How they learn:**
  - UAlbertaBot and CherryPi use UCB1 over a strategy list
  - MegaBot uses epsilon-greedy over three whole bots with a recency-weighted average
  - AIUR picks one of five "moods" and reweights them per opponent
  - Steamhammer snapshots both sides' unit mix every 30 s into a file per opponent and predicts
    the enemy by nearest neighbour

  [confirmed]
- **Fight or flee from a combat simulator** (SparCraft, up to 8v8 in under 5 ms, or the faster
  approximate FAP). UAlbertaBot runs the fight in simulation first and continues only if the
  outcome is positive. [confirmed]
- **Limits of bandits:** they help most against weak or fixed opponents. UAlbertaBot "tried
  everything, to little avail" against a strong bot and won 1%. Too little exploration also
  misses good options. [confirmed]
- **Known weakness of the scene:** most bots pick a playbook at the start and follow it to the
  end, and humans exploit the pattern. [confirmed]

### Warcraft III
- **The melee AI is JASS:** an ordered build list, and an attack loop that waits for an army,
  computes a force level and picks a target in priority order.
  - Newbie waits 240 s before its first attack, never retreats, never targets heroes and never
    makes all-ins. [confirmed]
  - Insane doubles gold and lumber. [likely]
- **AMAI (Advanced Melee AI) turns the AI into data tables:**
  - strategies with priorities and bonuses
  - personality profiles (aggression, uncertainty, persistence, surrender value)
  - a counter table, and prediction rules that infer the enemy mix from buildings seen
  - a job scheduler with separate frequencies
  - strategy choice by weighted roulette, with a persistence bonus
  - **below Insane, enemy-strength estimates get random noise scaled by `uncertainty`**

  [confirmed]

### Supreme Commander: Forged Alliance Forever, and 0 A.D.
- **FAF's base AI is builder groups.** Each builder has a priority, conditions (economy, unit
  counts, threat) and an optional priority function. Among the top-priority builders whose
  conditions pass, one is picked at random. [confirmed]
- **FAF's "AIx" cheat is explicit and adjustable:** build rate and income multipliers, plus
  optional omni-vision. [confirmed]
- **0 A.D.'s Petra AI has six levels:**
  - gather multipliers from 0.42x to 1.56x, so it is handicapped below Medium and cheats above
  - population scaling at the easy end
  - personality drawn within ranges
  - its own queue manager admits the design makes it "always sit on a few hundreds resources"

  [confirmed]

### AlphaStar and OpenAI Five
- **AlphaStar reached Grandmaster** (above 99.8% of ranked players).
  - Fairness caps: 22 non-duplicate actions per 5 s, about 110 ms latency, a camera interface.
  - Supervised learning on 971,000 human replays alone reached the 84th percentile.
  - The league was main agents, main exploiters and league exploiters, each on 32 TPUs for 44
    days.

  [confirmed]
- **OpenAI Five** trained for 10 months and won 99.4% of 7,257 public games. 29 teams still
  found 42 wins against it. [confirmed]
- **Not a route for this project** in cost, and not in maintenance either: every balance change
  would mean retraining.

---

## 4. Tower defence, and PvP send-TDs in particular

### Games in the genre with computer opponents
- **Legion TD 2 has bots, but their internals were never published.** From the v7.04 patch
  notes [confirmed, re-checked]:
  - *"Beginner and Easy bots no longer forget to build, but now make mistakes that new players
    often make"*
  - *"Hard bots no longer cheat with income"*
  - *"Insane bots bonus income reduced from +65 to +50"*

  The developer says the tiers up to Platinum do not cheat, and Diamond and above cheat "by
  starting with bonus income". [confirmed]
- **Legion TD 2's "Recommended Value" is a threat estimate shown to players:** the defence value
  needed to clear the wave, raised by what the opponent could send. It ignores typing and
  position. [confirmed]
- **The official Legion TD 2 guide:** *"Spend just enough gold on fighters to clear your waves
  and spend the rest of your gold on workers."* It also says to invest in income in proportion
  to what the attacker spends, not while they bank. [confirmed]
- **Bloons TD Battles 2's AI has personalities** crossed with round count. They range from
  never sending, through occasional easy rushes and a continuous stream of efficient sends, to
  regular strongest-available rushes. [confirmed]
- **A Warcraft III "Line Tower Wars AI" map (epicwar #60923), read from its `war3map.j`:**
  - it builds hand-placed rows, front to back, and upgrades finished rows
  - it sends a fixed batch per gold threshold on each income tick
  - it hides gold in a "Safe" variable between ticks
  - **difficulty is purely extra income** (income/20, /10 or /7 per tick), rubber-banded upward
    below 3 lives
  - it never looks at the opponent

  [confirmed by source inspection, in the brief]
- **Indie devlogs of 2026 LTW-likes** [the projects' own claims]:
  - an income target after which pure income sends stop scoring as free (LTW99)
  - banking toward a pricier creep when just short, emergency defence at the goal end when low
    on lives, selling stranded or outclassed cheap towers, and clumping sends against
    single-target defences (CreepClash)

### The one open LTW-like bot with measured design decisions
`PH-Gousse/tower-defense` on GitHub, an LTW-like browser game with a deterministic simulation,
records its bot decisions as ADRs with results. **The quotes below were re-checked against
`docs/adr/0016-bot-reads-the-board-with-a-flood-model.md` and `packages/sim/src/bot.ts`.**

- **The bot is a command source.** It is a pure function of state that emits the same commands
  a player does, so bot matches record and replay.
- **A flood model reads the board.** Per tower, it takes the route tiles in range (widened by
  crowd spread) and computes firing time, shots and kills; leaks are creeps minus kills. It has
  one fitted constant, calibrated with a headless harness that "streams creeps at a maze and
  prints the model's prediction".
- *"A greedy 'longest walk per tile' placement stalls at 43 tiles; the tight serpentine reaches
  71 with 17% more damage per tower."*
- *"Picking the wave predicted to leak most, sent every decision, lost 0-4 to the table's
  bank-and-burst rhythm."*
- *"two bots ran 33 minutes and 1,478 sends without a single leak"* by dribbling the cheapest
  creep between income payouts.
- *"when nothing affordable is predicted to leak -- most of every match -- the model sends the
  best earner... A send that cannot hurt is an investment."*
- **Reactive tower choice lost.** Against a fixed-template bot over twelve matches, a variant
  that spent its intelligence on *defence* went 0-12, while one that spent it on *sending* went
  10-2. The bot's own comment: *"specialising against the wave currently in your lane answers
  the wave that is already dying."*
- **Holding gold for an unaffordable fix** *"stalled the ordinary build branch, and a hard bot
  with a thin maze died in four minutes with 600 gold in hand."*
- **Maze size tied to the clock deadlocks.** The bot *"aimed at 45 towers from minute two and
  then spent twenty minutes buying them one at a time on starting income"*. Maze size is now
  towers per gold of income.
- **Difficulty is play, not cheating:** spend ratio plus reaction delay, validated by a
  round-robin that must be transitive. The shipped presets were the first transitive triple
  found. Aggression was *not* monotone. [from the brief]

### Maze building as a computational problem
- **Choosing k blocking cells on a grid to maximise the shortest path is NP-hard.** ("Desktop
  Tower Defense Is NP-Hard", LNCS 2017.) The graph form is "k most vital nodes" /
  shortest-path interdiction, which is hard even to approximate within a factor below 2.
  [confirmed]
- **Practical solvers from the Pathery puzzle** (Mayulime):
  - candidates restricted to cells on a shortest path (`d(s,v)+d(v,f)=d(s,f)`)
  - "chokepoints" as guaranteed gains
  - 1-opt place/move hill climbing
  - ruin-and-recreate (clear a rectangle and re-optimise) as the strongest method
  - optimal walls "look like a tree"

  [confirmed as repo documentation]
- **Templates beat greedy placement:** the serpentine result above, and hand searches finding
  that zigzags pack the longest paths. [confirmed]
- **Damage exposure rather than path length:** no formal paper was found.
  - Community mazing theory favours spots where a tower "fires into the path twice", and multi-
    pass spirals. [unverified]
  - **Exposure saturates:** in the LTW-like bot, a tighter, longer maze lost 6-0 on a 16-wide
    lane because long-range towers already fire for the whole lap. [from the brief]
- **Incremental building has no literature.** Adding walls can only lengthen a path or
  disconnect it, so every subset of a legal layout is also legal: any build order stays
  unblocked. Which order defends best is the open question. [derived]
- **Juggling** (Desktop Tower Defense, Fieldrunners): sell and rebuild a wall to flip which exit
  is open, so creeps retrace the maze. [confirmed as a community technique]

### Research on AI for tower defence
- **Avery, Togelius et al., IEEE CEC 2011:** a genetic algorithm evolves each creep wave to be
  "maximally effective against the previous strategy of the player", scored by simulated
  playouts, with "thousands of waves... per second". The closest published attacker AI.
  [confirmed]
- **EA SEED on Plants vs Zombies (CoG 2024):** a reinforcement-learning policy picks one of four
  high-level *stances* over hand-built features, and the existing scripted AI executes the
  stance. Success rate 57.1% against 48.0% for the script alone, after 10K episodes.
  [confirmed]
- **Anderson & Falconer (2025)** mined player tactics from 11,517 replays of a competitive
  mobile TD with sequence pattern mining. [confirmed abstract]
- **TowerMind (AAAI 2026)** is a TD benchmark with a "clear performance gap between LLMs and
  human experts". [confirmed]

### The invest-or-defend trade-off
- **Formal shape: optimal reinvestment is bang-bang.** Invest everything, then stop, and switch
  once the remaining time is shorter than the payback time. [confirmed for the textbook case
  (Evans' control notes); the general rule is derived]
- **What games do in practice** is a survival constraint instead: "just enough" defence (Legion
  TD 2), income targets (LTW99), or maze size scaled to income (the bot above).
- **Bloons TD Battles 2 players separate two metrics:** "eco per dollar" and the fastest eco
  regardless of cost. [unverified, community wiki] This is very probably the same effect
  `singleplayer.md` hit as "income per SEND, not per gold": when stock or time is the limit
  rather than gold, the efficient creep is the wrong buy.

### No LTW 12.4a strategy guide was found online
Wintermaul Wars guides say:
- *"DONT SEND ANYTHING THAT YOU KNOW WOULDN'T GO THROUGH!!!"*
- "behind on income is like losing the game automatically"
- stack air against a defence with no air splash

[unverified, community] A Line Tower Wars: Reforged thread says to spam basic towers early
"since you can sell them all later". [unverified] **The best source for how 12.4a is really
played is the people who play it.**

---

## 5. How game AIs learn

### Learning from human play, in shipped games
- **Forza Drivatar** learned per-player driving on an authored racing line, needed heavy
  rubber-banding, and was **dropped in Forza Motorsport (2023)**. The new AI "no longer
  replicates the driving behavior of your friends" and is built "without any cheats, hacks,
  and rubber banding". [confirmed]
- **Killer Instinct Shadows** use case-based reasoning. They store an action with 40+ *relative*
  state measures, match situations by nearest neighbour, and lower the relevance of actions
  that get punished.
  - They "do not react faster than humans can... they are guessing in the same way humans do".
    [confirmed]
  - They copy your mistakes too.
- **Supreme Commander 2** trained small neural networks offline for platoon fight-or-flee.
  - The shipped AI fled from enemy commanders, because the fitness function never valued
    killing one.
  - The designers' verdict: a black box nobody can tune, and "if you change anything... you
    have to start training from scratch".

  [confirmed]
- **Colin McRae Rally 2.0** trained its driving network on "a few thousand training pairs" of
  the developer's own driving, on top of a racing line computed separately. **The clearest case
  of small-data imitation that shipped:** an authored plan plus learned parameters. [confirmed]
- **Gran Turismo Sophy** is reinforcement learning with etiquette in the reward, and was
  deliberately crashing into opponents a week before its exhibition. [confirmed]

### Learning across matches
- **Per-opponent files plus a bandit** is the proven shape (Brood War bots, above).
- **Strategy choice as rock-paper-scissors:** the Nash mix is the safe choice, and moving away
  from it pays only against weak opponents. [confirmed]
- **Rating AIs:**
  - OpenAI Five rated itself with TrueSkill against a fixed reference pool
  - Stockfish accepts a change only after a sequential probability ratio test over paired
    games

  [confirmed]
- **Not found:** any shipped RTS or TD with a per-human "this player always rushes flyers" file.
  Per-human memory has only shipped in fighting-game ghosts.

### Offline self-play and imitation at small scale
- **League play** (AlphaStar): main agents, exploiters that train only to beat the current best,
  and held-out scripted strategies ("a cannon rush or early flying units") as checks.
  - "Naive self-play has high Elo, but is more forgetful."
  - A hall of fame of past champions is the standard fix. [likely]
- **Self-play leaves blind spots:** adversarial policies beat superhuman KataGo over 97% of the
  time, and a human who learned the trick won 14 of 15. [confirmed]
- **Dynamic scripting** (Spronck) learns *weights over hand-written rules* after each encounter.
  - Top culling (the best rules become unavailable while the AI is winning) held Neverwinter
    Nights encounters near a 50% win rate. [confirmed]
  - Evolutionary search was used offline to find counter-tactics, which were then added to the
    rule base. [likely]
- **Scale:** Maia, a human-like chess engine, needed 12 million games per rating band.
  Personalising to one player only helped from about 5,000 of their games. **Hundreds of
  replays are statistics, not a neural policy.** [confirmed]

---

## 6. Difficulty, fairness and feeling human

### What players accept
- **Soren Johnson:** "With cheating, perception becomes reality, so transparency is the antidote
  to suspicion and distrust", and "When the question is one of fairness, the player is always
  right." [confirmed]
- **Clearly labelled cheats are tolerated** (StarCraft II's "Cheater", FAF's "AIx", Legion TD 2's
  top tiers). Hidden bonuses and visible rule-breaking are resented, and so is superhuman input
  (the AlphaStar APM debate). [confirmed]
- **Adjusting difficulty to the player** diminishes the player's sense of accomplishment for
  some (Spronck), and knowing it is on reduces its effect. [confirmed / likely]
- **Left 4 Dead's Director** adjusts *pacing, not difficulty* ("Amplitude is not changed,
  frequency is"). [confirmed]
- **Civilization is the documented bonus model.** In VI each level above Prince adds combat
  strength and +8% science / +20% production and gold. Reviews call the high levels "cheap".
  [likely]

### Human limits, for pacing an AI
- **Simple visual reaction is about 250 ms.** OpenAI Five reacted in 217 ms. AlphaStar was
  capped at 22 actions per 5 s and about 110 ms of delay, and observed every 370 ms on
  average. [confirmed]
- **StarCraft II telemetry** [confirmed] (PLOS ONE):
  - first action after a new screen: about 720 ms
  - a full look-decide-act cycle: about 5 s for Bronze players, about half that for
    professionals
  - mean APM 117

  **For a game whose decisions are strategic, the cycle length is the relevant figure, not
  reaction time.**

### Mistakes that look human
- **Halo playtests:** with weak enemies 8% of testers called them "very intelligent"; with tough
  enemies, 43%. "Tougher = smarter." They advise informing the player rather than being subtle.
  [confirmed]
- **Deliberate mistakes should be plausible:** move before firing, miss the first shot. F.E.A.R.
  used callouts so players noticed the squad's plans. [likely]
- **Weakened engines do not play like weak humans:** Stockfish matches 35-40% of human moves,
  human-trained Maia 46-52%. So an AI weakened by *random bad actions* looks like a machine.
  One weakened by *misjudging* looks like a person. [confirmed]

### Testing whether an AI feels human
- **BotPrize (Unreal Tournament 2004), 2012:** two bots were judged human 52.2% and 51.9% of the
  time, while actual humans averaged about 40%. [confirmed]
- **Recommended protocol:** a yes/no question plus a certainty rating, the real question hidden
  among distractors, anonymised players, and indirect measures such as "report as bot".
  Watching judges complement playing ones. [confirmed]

---

## 7. Architectures, and where each breaks

| Architecture | Suits | Breaks when |
| --- | --- | --- |
| Rule / priority lists (AoE2, Warcraft III, FAF) | authored macro knowledge | rules starve each other of resources; there is no lookahead |
| State machines (StarCraft II main and attack states) | phases and modes | transitions multiply |
| Behaviour trees (Halo 2) | reactive per-agent behaviour | economy-wide trade-offs |
| Utility AI (Dave Mark's Infinite Axis Utility System) | many options scored on continuous inputs | curves need tuning; flip-flops without inertia |
| GOAP (F.E.A.R.) | small symbolic action sets | numeric economies, adversaries |
| HTN planning (Killzone 2, Horizon, PurpleWave's macro) | authored "how to achieve X" | every method must be authored |
| Influence / threat maps | cheap spatial summaries | small maps |
| MCTS (Total War: Rome II campaign) | big turn-based choices with a forward model | real-time budgets; Rome II looked one turn ahead and was criticised for slow turns [likely] |
| End-to-end reinforcement learning (AlphaStar, OpenAI Five) | unlimited compute | cost, retraining on every balance change, blind spots |

**The shipped RTS AIs mostly combine three pieces:**
- a rarely-run strategy selector (weighted random, a bandit, or nearest neighbour against
  history)
- managers on a beat, working from priorities, conditions and counter tables
- a small state machine per group, gated by a fight evaluation or simulation

---

## 8. What was re-checked by hand

Quoted verbatim from the live source on 2026-09-15:

- **Promiskuitiv's Steam post that the AoE2 standard AI never cheats resources:** held, word for
  word.
- **StarCraft II's cheater harvest ramps in `MeleeAI.galaxy`:** held, including the exact
  formulas.
- **Legion TD 2 v7.04's bot lines:** held, word for word.
- **The LTW-like bot's measurements:**
  - held: the 43 versus 71 serpentine, bank-and-burst beating model-picked sends 0-4, 1,478
    leak-free sends, the unaffordable-fix death, and "a send that cannot hurt is an investment"
  - the 0-12 reactive-defence result and the clock-sized maze deadlock are in the source file
    rather than in the ADR the brief named. Both held there, the second in different words
    than the brief used

Not re-checked:
- the AoE2 per-level percentages (tagged in section 2)
- the Warcraft III LTW map's script (the brief read it from a downloaded map)
- the community rating estimates
- anything tagged [unverified]

---

## Sources

**Age of Empires II**
- Spirit of the Law, "Interview with the creator of the Definitive Edition AI" (2020): https://www.youtube.com/watch?v=eYcxohpnXo0
- Spirit of the Law, "How the AoE2 AI Thinks (ft. Promi)" (2019): https://www.youtube.com/watch?v=-S1CkfzEHSU
- Promiskuitiv on resource cheating: https://steamcommunity.com/app/813780/discussions/0/1735510154206574934/
- Promiskuitiv on difficulty (2021): https://steamcommunity.com/app/813780/discussions/0/3082142648919514069/
- Forgotten Empires AI page: https://www.forgottenempires.net/ai
- CPSB scripting guide: http://userpatch.aiscripters.net/CPSB.pdf
- UserPatch reference: https://userpatch.aiscripters.net/reference.html
- airef: https://airef.github.io/
- Patch notes: https://www.ageofempires.com/news/aoe2de-update-34055/ , https://www.ageofempires.com/news/aoe2de-update-35584/ , https://www.ageofempires.com/news/aoe2de-update-37650/ , https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-81058/ , https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-107882/
- Isgreen on DE AI: https://www.pcgamesn.com/age-of-empires-2-definitive-edition/new-civs
- AlphaScripter: https://github.com/mboop127/AlphaScripter
- Community rating discussion: https://forums.ageofempires.com/t/ai-difficulty-levels/107341

**RTS**
- StarCraft II API and AI scripts: https://raw.githubusercontent.com/Blizzard/s2client-proto/master/s2clientprotocol/sc2api.proto , https://github.com/SC2Mapster/SC2GameData
- Liquipedia, StarCraft II AI: https://liquipedia.net/starcraft2/Artificial_Intelligence
- StarCraft AI competitions survey: https://certicky.github.io/files/publications/Starcraft-AI-ToG-2018.pdf
- UAlbertaBot: https://github.com/davechurchill/ualbertabot/wiki/Artificial-Intelligence
- Steamhammer and satirist.org: http://satirist.org/ai/starcraft/blog/archives/362-Steamhammers-opponent-model.html , http://satirist.org/ai/starcraft/blog/archives/854-AIIDE-2019-what-UAlbertaBot-learned.html
- SparCraft: https://ojs.aaai.org/index.php/AIIDE/article/view/12527 ; FAP: https://github.com/N00byEdge/FAP
- AlphaStar: https://storage.googleapis.com/deepmind-media/research/alphastar/AlphaStar_unformatted.pdf
- OpenAI Five: https://arxiv.org/abs/1912.06680
- AMAI: https://github.com/SMUnlimited/AMAI
- FAF: https://github.com/FAForever/fa
- 0 A.D.: https://github.com/0ad/0ad
- Soren Johnson on AI cheating: http://www.designer-notes.com/game-developer-column-7-our-cheain-hearts/
- Halo 2 AI: https://www.gamedeveloper.com/programming/gdc-2005-proceeding-handling-complexity-in-the-i-halo-2-i-ai
- F.E.A.R.: https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf
- HTN planning: https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf , https://www.guerrilla-games.com/read/htn-planning-in-decima
- Infinite Axis Utility System: https://www.gdcvault.com/play/1021848/Building-a-Better-Centaur-AI
- Total War AI: https://www.gamedeveloper.com/design/revolutionary-warfare-the-ai-of-total-war-part-3-

**Tower defence**
- Legion TD 2: https://beta.legiontd2.com/updates/v704-campaign-imp/ , https://beta.legiontd2.com/manual/ , https://legiontd2.wiki.gg/wiki/Recommended_value
- Bloons TD Battles 2: https://www.bloonswiki.com/Hero_Challenge , https://bloons.fandom.com/wiki/Eco_(BTDB2)
- Warcraft III LTW AI map: https://www.epicwar.com/maps/60923/
- LTW99 devlog: https://chaztats.itch.io/line-tower-wars/devlog/1656723/v12-ltw99
- CreepClash devlog: https://ennix.itch.io/creepclash/devlog/1560907/update-summarized-devlog
- PH-Gousse bot: https://github.com/PH-Gousse/tower-defense (docs/adr/0005, docs/adr/0016, packages/sim/src/bot.ts)
- Desktop Tower Defense is NP-hard: https://link.springer.com/chapter/10.1007/978-3-319-60675-0_2
- Shortest-path interdiction: http://archive.dimacs.rutgers.edu/TechnicalReports/TechReports/2007/2007-02.pdf
- Pathery solvers: https://github.com/Tridwoxi/Mayulime , https://github.com/bwoodbury3/pathery-solver
- Avery et al. 2011: http://julian.togelius.com/Avery2011Computational.pdf
- EA SEED on Plants vs Zombies: https://arxiv.org/abs/2406.07980
- TowerMind: https://arxiv.org/abs/2601.05899
- Evans, optimal control: https://math.berkeley.edu/~evans/control.course.pdf
- Mazing guides: https://maultactics.gg/articles/mazing-guide , http://wmwl.weebly.com/wmw-guide.html
- Red Blob Games on TD pathfinding: https://www.redblobgames.com/pathfinding/tower-defense/

**Learning and difficulty**
- Forza: https://forza.net/news/forza-motorsport-drivatars-tire-physics
- Killer Instinct: https://www.gamedeveloper.com/programming/the-killer-groove-the-shadow-ai-of-killer-instinct , https://www.ultra-combo.com/shadow-training-manual-v1-0/
- Supreme Commander 2: https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter30_Using_Neural_Networks_to_Control_Agent_Threat_Response.pdf
- Colin McRae Rally 2.0: http://ai-junkie.com/misc/hannan/hannan.html
- Gran Turismo Sophy: https://ai.sony/blog/from-research-to-deployment-in-one-year-gt-sophy-is-now-available-to-all-gt7-players
- Brood War bot learning: https://cdn.aaai.org/ojs/12961/12961-52-16478-1-2-20201228.pdf
- Strategy selection as a game: https://cdn.aaai.org/ojs/12857/12857-52-16373-1-2-20201228.pdf
- Stockfish fishtest: https://official-stockfish.github.io/docs/fishtest-wiki/Fishtest-Mathematics.html
- KataGo adversarial policies: https://arxiv.org/abs/2211.00241
- Dynamic scripting: https://spronck.net/pubs/SpronckGAMEON2004.pdf
- Maia: https://arxiv.org/abs/2008.10086v1
- StarCraft II telemetry: https://pmc.ncbi.nlm.nih.gov/articles/PMC3776738/
- Halo, "The Illusion of Intelligence": https://www.jmeiners.com/shamans/papers/ai/the_illusion_of_intelligence.pdf
- Left 4 Dead Director: https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf
- Civilization difficulty: https://civfanatics.com/civ5/info/difficulties/
- BotPrize: https://news.utexas.edu/2012/09/26/artificially-intelligent-game-bots-pass-the-turing-test-on-turings-centenary/
- Human-likeness evaluation: https://www.frontiersin.org/journals/computer-science/articles/10.3389/fcomp.2021.774763/full
