# How Line Tower Wars is played well

**What this file is for:** the KNOWLEDGE a strong player has and the rules do not state. It is
written so an agent can understand the game well enough to configure, script and train a
computer opponent. It is the input `ai-rework.md` builds the AI's knowledge from: its counter
tables, maze templates, stances and send patterns.

It is not the rules (`game_rules.md`) and not the numbers (`unit_data.md`). It names units and
mechanics and points there for figures. **It carries no stat numbers.** The few numbers it does
carry are the META's own: a maze row, a cluster depth, an income benchmark, all stated by the
project owner. They change when the meta changes, not when a `.tres` does. Where an example
leans on a default match setting, it says so, because a changed setting changes the
arithmetic and not the idea.

**Living document, and deliberately incomplete.** The game is deep and this is a first pass.
Section 10 lists what is still missing. Add to it whenever a gap is filled.

## Where every claim came from

| Tag | Meaning | How far to trust it |
| --- | --- | --- |
| **[expert]** | stated by the project owner, a long-time LTW player, on 2026-09-15 unless dated otherwise | authoritative for the meta it describes |
| **[derived]** | Claude's reading of `game_rules.md`, `unit_data.md`, a blueprint file or a `Tools/MazeView` run | plausible, **unconfirmed**; correct or promote it when an expert has read it |
| **[community]** | outside sources, see `Findings/2026-09-15-rts-ai-research.md` | background only, not LTW 12.4a specific |

**When an [expert] and a [derived] line disagree, the expert line wins** and the derived one
is corrected, not argued for.

---

## 1. What winning looks like

- **Income is by far the most important factor in winning.** [expert] Everything else
  (towers, lives, technology) is paid for by it, and it compounds.
- Lives end the match, and they are also a lever: a creep that leaks steals a life *and* keeps
  walking into the next lane (`game_rules.md`, Life steal and recycling). [derived]
- **So every decision trades between two uses of the same gold** [expert]:
  - greedy play: cheap sends that raise income
  - aggressive play: expensive sends that steal lives and force the defender to spend
- The defence is paid for out of what is left.

---

## 2. The opening

### 2.1 The meta start [expert]
**This is the very advanced start. An easy AI should not play it.**

1. **Build two towers, Sentries, at (2.5|15) and (3.5|16).** The maze begins with the diagonal line
   of blueprint 1 those two towers belong to. *(Positions are written the way players write them,
   (column|row); `Tools/MazeView` prints the same notation. In `blueprint_1.tres` they are internal
   cells (5,34) and (7,36).)* The finer points of the start are better learned from a recording
   than from a description. [expert]
2. **Send the builder to the top of the maze and chain an attack order**, so it starts hitting
   the very first creeps immediately. Hitting Sheep and Timber Wolves with the builder matters.
3. **Wait until you have the gold for four Sheep, with one second left until the next income
   payout, and send the four Sheep just before the payout ticks.** That leaves zero gold, and the
   payout pays the raised income. *(On the default match settings of 2026-09-15 that is 40 gold
   into four Sheep, for 28 income.)*
4. **The payout lands: send two more creeps. Kill a Timber Wolf with the builder as soon as
   possible** for its bounty, and send one more creep with it.
5. **If the towers are placed properly and the builder is used properly, there is just enough
   damage to kill exactly the send you made yourself.** It is barely enough, and one or two may
   leak sometimes.

**Why the first maze is in the MIDDLE of the lane, not at the top** [expert]:
- Creeps take longer to reach it, which buys time for another income payout to come in and more
  towers to be built before first contact.
- Earlier metas started in the BACK for the same reason.
- A lot of testing went into this. It may not be perfectly optimal, but it is very good.

**Why wait for the last second before the payout** [expert]:
- **It sends more creeps at once.** The four Sheep go out one second before the payout and the
  next two the moment it lands. So six or seven Sheep arrive as one wave instead of two waves
  ten seconds apart.
- Two staggered waves give the defender more total uptime for towers and builder, and are much
  easier to kill.
- One stacked wave is far harder, because nobody has any area damage yet at that point.
- **Straddling the payout** (spend everything just before it, then spend the payout at once) is a
  key, often-used technique all match long, whenever a lot of creeps need to arrive within a
  very short time. [expert]

**Notes** [derived, to be confirmed]:
- A send's income applies from the next payout onwards (`game_rules.md`, Economy), so waiting for
  the last second costs no income either.
- In the Sheep pack only the Timber Wolf pays bounty (`unit_data.md` 6.2). That is why the Wolf is
  the builder's target.
- The builder only fights when ordered (`game_rules.md`, The builder), so step 2 is a
  deliberate order and not something that happens by itself.

### 2.2 The start for a weaker player [expert]
- An easy opponent plays a **left-right maze** (5.5) and sends **slower and less**, the way a
  player who does not know the game would.
- Recordings of players completely new to the game are expected from upcoming tests, and are the
  better source for what an easy opponent should look like.

---

## 3. The economy: greedy and aggressive

### 3.1 The balance [expert]
- **Always playing aggressive makes you fall behind in income.**
- **Playing too greedy lets your defender off the hook:** they never have to upgrade, so they
  snowball their own income instead.
- The right play is a **balance**, and it shifts with what the defender builds and with what is
  being sent at you.
- **When you are under attack yourself** you have to invest in defence, and may have to
  **cancel an attack** (3.3).

**When to go aggressive, and when not** [expert]. There are many factors; these are the main
ones:
- **The defender's maze VALUE, relative to the match time.** An expensive maze for this point in
  the match means you probably cannot steal lives, so do not go aggressive. An expensive maze is
  not automatically a good one, but analysing a maze properly is a large topic of its own.
- **Far behind in income:** do not play aggressive for a while. Catch up first.
- **Defender far ahead in income:** play aggressive, so they do not win for free by never being
  pressured.

Every player's value and income are in the table on screen (`game_rules.md`, Interface), so
all three signals are information the AI may read. [derived]

### 3.2 Greedy play [expert]
- **Always spend all your gold, and spend it on generating income.** Banked gold earns nothing.
- **Cheaper creeps generate more income for their cost**, attackers excepted. The rule behind it
  is that the income-to-cost ratio worsens as creeps get stronger (`game_rules.md`, Economy).
  [derived]
- **In theory the cheapest creep is always best. In practice population blocks you.** Creeps
  count against your population while they are alive in another lane. If they live long you hit
  the cap, cannot send, and gold piles up unspent.
- **How much you can spam depends on the defender's maze:**
  - **Damage in the FRONT:** your creeps die fast, population frees up, and you can spam more.
  - **Damage in the BACK:** your creeps live long and spam-sending into it is awkward. That is
    where attackers and aggressive play come in (3.3).
- A reserve only refills while it is below full (`game_rules.md`, Sending creeps), so a full
  reserve is income left on the table. [derived]
- **How the gold is spread across creep types** [expert]:
  - **In theory: start with the Sheep and buy up the price list, cheapest first, until the gold is
    gone.** That makes the most income out of a given amount of gold.
  - **In practice that costs too much APM**, and later it stops being worth it: the extra
    efficiency of sending tier 1 creeps once income is in the hundreds of thousands barely
    matters.
  - **So the real rule is a middle way: do not get population blocked, still spend all the gold,
    and do not spend all your attention on sending.**
- **The population cap really does bind.** When spamming for income you reach or come close to the
  cap about once every payout. An aggressive send is more like 40-80 creeps in total. [expert]
- **There are no quiet stretches. Players send creeps ALL the time**, to stack up income.
  [expert]
  - The strongest creep available is often NOT the one to send, because its reserve only allows a
    few.
  - The reserves of many creep types are refilling constantly, so there is always something to
    send.
  - The skill is keeping gold flowing through all of them, not waiting for the next unlock.

### 3.3 Aggressive play [expert]
- **Expensive creeps steal lives and force upgrades.** A defender who has to upgrade is not
  investing in income, even if nothing leaks.
- **Cheap creeps rarely steal lives.**
- **Attackers force the defender to build strong towers in the FRONT.** Against a defender whose
  damage is still mostly at the back:
  1. The attackers force investment at the front.
  2. Flood the maze with many strong creeps that only start dying at the very end.
  3. Send flyers over them, and the back is overwhelmed.
- **An attack is not one send.** It takes place over 20-60 seconds, like the convergence example
  in 4.3.
- **Cancelling an attack means STOPPING the aggressive sending part way.** For example, you may
  need to upgrade your own towers before you can send the Wyverns or Banshees that were meant to
  finish it, because you would lose too many lives otherwise.
- **Saving up for several income payouts** without spending anything, for one very large attack,
  is valid. It is **heavy on your own income**.
- **A valid attack can also be simply a lot of flyers, or a lot of very fast creeps**, when the
  defender is not prepared for that type. It all depends on their maze.

### 3.4 Income benchmarks [expert]
- **A player should roughly always be able to send one of the creep that just unlocked, give or
  take fifty percent.**
- **In a very aggressive game income tends to be lower.**
- **Experienced players have 3-4 million income when Sudden Death starts.**

**Reading it:**
- **The first benchmark is per income payout:** income per payout ≈ the price of the newest
  unlocked creep. [expert, confirmed]
- It describes the unlock phases. Between the last tier 3 unlock and Sudden Death nothing new
  unlocks, and the Sudden Death figure is the benchmark there. [derived]
- These are the targets a bench should compare an AI's income curve against (`ai-rework.md`
  phase 2).

### 3.5 Just enough defence, and leaking on purpose [expert]
- **The optimal case is always investing JUST ENOUGH in the maze not to leak, and everything else
  in sending.** Overbuilding the maze loses income.
- **Good players know how much damage their towers can do**, so they usually see a leak coming
  early. For an AI this is easier still once there is data: it can calculate, or rely on earlier
  calculations.
- **In a very high level 1v1 you usually HAVE to leak some**, or you fall too far behind in income.
  The hard part is knowing when to leak what, and not leaking too much by accident. The specifics
  are too deep for a first lesson.
- **Against a very aggressive send it can be right to leak a few** rather than fall far behind.
- **All of that assumes everything is under control.** Players eventually lose in one of two ways:
  - overestimating their maze and losing many lives to a strong send
  - falling too far behind in income to keep up

### 3.6 Free-for-all dynamics [expert]
A high-level example of how the ring changes the balance, for players of about equal skill. **Not
to be over-weighted:** games like this will be rare for a long while.

- **Three players: aggression tends to hurt you.** Your defender is the player sending to your
  attacker. Pressure your defender hard, and they cannot send properly at your attacker, who then
  has a free game against you. So three-player games tend to be greedy.
- **Four players: aggression tends to help you.** Pressure your defender, and they cannot attack
  the player in front of them, who is the one sending to your attacker. That player is then free to
  pressure your attacker. So sending aggressively harms your own attacker.
- **The more players are alive, the less this matters**, because the effect does not carry through
  many lanes.

### 3.7 Economy facts an agent should hold [derived]
- **Income** is paid on a fixed shared interval.
- **Payback.** Each creep's payback time is its cost divided by its income per payout, times
  the interval. Early cheap sends pay back within a few payouts and keep paying all match.
- **Technology after the free opening gets more expensive with every purchase** (`unit_data.md`
  2.2). An endgame player owns almost every technology [expert], so late income has to cover a
  very large technology bill on top of the maze.
- **Sudden Death changes the economy** (`game_rules.md`, The creep roster):
  - tiers 1-3 stop being sendable
  - tier 4 pays little income, and less still above an income cap
  - anyone below an income floor is raised to it once
  - the Treasure Goblin is a pure income creep that is refused above the cap
- **Primal (1), the Primalist, generates gold per attack.** Below Ultimate it is penalised for
  packing Primal towers together (`unit_data.md` 4.7).

---

## 4. Sending

### 4.1 What each kind of creep is for
| Kind | Used for |
| --- | --- |
| cheap creeps of the current tier | income [expert] |
| expensive creeps | stealing lives and forcing upgrades [expert] |
| attackers | forcing strong towers in the defender's front; poor income [expert] |
| aura creeps | **always mixed in** to aggressive sends [expert] |
| flyers | sent **on top of** ground creeps to flood the maze, or massed against a defender unprepared for them [expert] |
| very fast creeps | massed against a defender unprepared for them [expert] |
| bosses | steal two lives each (`game_rules.md`) [derived] |

### 4.2 Composing an aggressive send [expert]
- **Match the armour type to the defender's damage**, using the armour matrix (`unit_data.md`
  1.1) against their actual towers.
- **Ground first, then air on top.** Ground creeps fill the maze slowly and distract; flyers sent
  after them arrive over the same, busy towers, and the maze floods.
- **Mix auras in.**
- **Stagger or stack by the defender's AoE:**
  - stacked (arriving together) against single-target mazes
  - staggered (spread out) against mazes with a lot of area damage
- **It is a very complex topic.** Real send patterns should come from recordings of serious
  matches (`ai-rework.md` 4.3).

### 4.3 Convergence: making different creeps arrive together [expert]
During tier 2, against a defender who has put all their damage (their best towers) in the back
of the maze:

1. Send a few slow **Sea Turtles** for 10-20 seconds.
2. Follow with **Dragonspawn**, which are faster and catch up with the turtles.
3. Follow with **Wyverns or Banshees**.
4. All three meet in the back of the maze. Flyers ignore the maze and are effectively the
   fastest.

**The general method** [derived]:
- A creep's arrival time at a point is its route length to that point divided by its speed.
- **Ground creeps take the maze route**, which in an endgame maze is several times the lane's
  length (measure it with `Tools/MazeView`, section 9). **Flyers take the straight line**, so a
  slow flyer can still arrive first.
- The delay between sending two creep types, for them to meet at a chosen depth, is the
  difference of their two travel times. Speeds are in `unit_data.md` 6.
- Slows stretch ground creeps' travel times; flyers are only slowed where they pass anti-air.
- The expert's timing is consistent with the ratio of those speeds on an endgame-length route.

### 4.4 Sending against a technology
- **Choosing sends against the defender's specific technology is considered very ADVANCED play.**
  [expert] For the AI it belongs to the top difficulty only.
- **What a sender may know** [expert, decision]:
  - conclusions drawn from the towers it can SEE in the defender's maze
  - the defender's technology when the match makes it obvious: the Random technology mode, and a
    mirrored draft once one exists
  - nothing the HUD does not show

### 4.5 Endgame sending: tier 4 [expert]
**Good endgame sending is an art form of its own.** Its patterns have been discussed and changed
with every patch, and doing it well is considered very advanced. **The main style has the same
shape as the tier 2 convergence example:**

1. **First, many ground creeps with auras.** Kodo Beasts are the aura carriers, and they matter
   most.
2. **The main creep is the Goblin Shredder**, guarded by **Obsidian Statues and Naga Sirens sent
   before it**.
3. **Usually three to four income payouts** of ground sending like this.
4. **Then two to three payouts' worth of short bursts of flyers.** Frost Wyrms and Harpy
   Windwitches are both good.

**The defender must try to focus the Kodos manually** (a tower attack order onto a creep,
`game_rules.md`, Towers and attacking).

**The Demon is very rarely used.** Its use is stealing single lives, for example from a player
sitting at one life; in a normal endgame it is not worth its price.

**Why that composition works** [derived from `unit_data.md` 6.5 and 6.6, to be confirmed]:
- The Shredder's Reactive Armor cuts the big hits endgame towers deal, and Goblin Engineering
  caps how far it can be slowed.
- The Kodo carries both Endurance and Devotion auras, and its War Stance buffs creeps around it
  once it is hurt.
- The Naga carries a regeneration aura and restores nearby creeps' eaten armour.
- The Obsidian Statue's Annihilation Aura weakens towers near it, and it leaves Ghouls when it
  dies.
- So the ground wave is a moving stack of buffs around the Shredders. Killing the Kodos
  unstacks it, which is why the defender focuses them.

### 4.6 The attacker creeps
**What an attacker does** [derived from `game_rules.md`]:
- Left alone it walks to the nearest tower, destroys it and moves on. It never walks to the end
  zone by itself.
- It targets towers only, never discs or the builder. Destroyed towers leave rubble for a while.

**The Phoenix, a flying attacker, is a special case** [expert]:
- It is used to **"poke holes" in key positions** of the defender's maze, which significantly
  shortens the route the creeps have to walk to the end.
- **A purely vertical maze makes that far easier** (5.3).
- **A defender has to repair the maze** when it happens.
- **Divineshrooms in key positions are the most important Phoenix defence:** they can outheal
  its damage and they deal good damage themselves.

**The Mountain Giant is the tier 4 ground attacker, and the Warden frontline is its answer**
(5.2). [expert]

**Sending attackers is rare in general** [expert]:
- **It tanks your income.**
- It is used when the defender's front towers are very weak and a hole can be poked in the maze.
- **Good players react by upgrading towers fast enough**, even when the front was weak, so the
  player sending attackers often loses out.
- The details are advanced.

---

## 5. The maze

### 5.1 How a maze evolves through a match
**The shipped blueprints 1-4 are that evolution** [expert]: blueprint 1 is roughly early tier 1,
and blueprint 4 is the endgame shape without discs. A blueprint marks POSITIONS only
(`game_rules.md`, Blueprints). Every entry in those files is the same placeholder tower type, so
the files say nothing about which tower goes where.

Draw them (section 9):

```
python Tools/MazeView/maze_view.py Resources/Blueprints/blueprint_1.tres --path --shape
```

**What the files show, read on 2026-09-15** [derived; the `.tres` files are the authority]:

| Blueprint | Shape |
| --- | --- |
| 1 | A compact staggered block in the MIDDLE of the lane: diagonal lines with half-cell offsets. |
| 2 | The whole lane: a wall across the front with a gap, vertical corridors down the upper section, a horizontal separator, a staggered middle, a second separator, vertical corridors down the lower section, and a closing wall at the bottom. |
| 3 | Blueprint 2 with the first separator thickened and the staggered middle rebuilt as vertical corridors. |
| 4 | Blueprint 3 with the second separator opened into vertical corridors on one side. |

**When each part goes up** [expert]:
1. **Blueprint 1 (the middle) is finished by about 200-400 income.**
2. **Then the front is built, and the first elemental towers.**
3. **The back is less urgent, but has to be done at some point in tier 2.**
4. **The middle built first in tier 1 has to be exchanged at some point**, because it is not
   part of the endgame maze.
5. **Every Basic tower is exchanged for an Elemental Core and elemental towers.** A Core can
   always be morphed straight away, because something is always researched and the elemental
   tower is better.

**How the stages connect** [derived, from comparing the files]:
- Blueprint 1 is contained entirely in blueprint 2: the early maze grows in place.
- From 2 to 3, and from 3 to 4, some towers are removed and others added where they would
  overlap: a section is sold and rebuilt.
- This matches the expert's point 4: the tier 1 middle is replaced.

**Where the first elemental towers go** [expert]: wherever they get the most UPTIME, which is
usually somewhere in the MIDDLE of the maze. A strong tower at the very front has poor uptime:
creeps spawn already inside its range rather than walking the maze in front of it, and further in
they are also being slowed and stunned.

**Basic towers** [expert]:
- **No endgame maze uses Basic towers. It is all elemental.**
- Basic towers get the maze shape going early, with cheap 10g towers for tower uptime.
- **They patch the weaknesses of the technology a player is on, and then they DO get upgraded,
  sometimes all the way to 25k.** Which Basic, and how far, is very specific to the technology.
  Some technologies handle most things on their own and never upgrade a Basic tower at all.
  - **Scorpion** really needs some Crushers in the front for early area damage, some upgraded all
    the way.
  - **Hurricane** likes some Cannons against the tier 2 Sea Turtles, some upgraded all the way.
  - **Warden** may need Turrets against tier 2 air such as the Banshee. The 10k Arcane Orb it comes
    with has good damage against air, but may not be enough.
- **In tier 1**, Cannons and Crushers at their 150g step matter for technologies with no area
  damage of their own.
- **Cannons are the quick answer to a Corrupted Treant attack.** Some technologies even need
  Cannons at 5k-25k against Siege Engines.
- In general, from those examples [derived]:
  - Turrets patch missing anti-air
  - Cannons patch weakness to heavily armoured creeps (Siege damage) and answer attackers
  - Crushers and Cannons patch missing area damage

### 5.2 The endgame maze [expert]
Every technology ends in the same or a very similar endgame maze. When tier 4 starts, a player is
finishing the maze into its final state, has almost every technology researched, and transforms
each elemental tower into the right one for its position.

**Shape:**
- **A horizontal cluster three to five deep across the very front**, against attackers. How deep
  depends on the current meta and on how strong attackers are.
- **The rest of the maze makes creeps move VERTICALLY.** It lets towers further back start
  attacking sooner and gives them more uptime.
- **Not completely vertical, though.** Fully vertical would probably be the most efficient for
  damage, but it is very vulnerable to the Phoenix (5.3). So there is almost always **at least
  one more horizontal line at around row 10-12**, splitting the maze into two sections.

**The front cluster:**
- **The frontline is almost always Ancient Wardens**, which can hold off Mountain Giants.
- **Behind them, many Divineshrooms**, which heal against the Phoenix.
- **A Holy disc** is very important.
- **At least one Lich and one Titan Vault**, to reduce attackers' attack speed and attack damage.

**Through the rest of the maze:**
- **Many Orb Keepers early in the maze**, for the stun and the percentage damage.
- **Firelords to strip creep armour as soon as possible.**
- **In the back, for damage:** more Firelords, Gravediggers, Moonbeams, Arcane Orbs and Titan
  Vaults all work.
- **Divineshrooms and Hurricane Elementals spread around the maze** against flyers. **A Hurricane
  must always have its flying priority on** (Prioritize).
- **Ultimate Sludge Monstrosities in key positions**, so their slow aura reaches over the whole
  maze and creeps are always passively slowed. **Almost the most important part.** Small gaps in
  the coverage are fine, because of how the slow works with stacks. The Sludge positions in the
  reference maze (5.2a) are proper and are the reference; recordings will refine them.
- **Beastmasters** (5.4).
- **Several Divineshrooms normally sit in the row 10-12 horizontal line**, to defend that line
  against the Phoenix (5.3).
- Spacing Orb Keepers to avoid their maximum-mana interaction is **not important**.

**Why those towers work** [derived from `unit_data.md` 4, to be confirmed]:
- **The Ultimate Ancient Warden** deals full Siege damage across its whole splash (Siege is strong
  against the Mountain Giant's Fortified armour), permanently erodes armour, and heals itself from
  its damage.
- **The Ultimate Divineshroom** hits air only, and heals friendly towers near it from its damage.
- **The Ultimate Lich's aura cuts creep attack speed, and the Ultimate Titan Vault's cuts creep
  attack damage.** Both only matter against attackers.
- **The Holy disc** gives towers in its radius armour and regeneration.
- **Orb Keepers early:** part of their damage is a share of the target's CURRENT health, worth the
  most before a creep is hurt. Their range is very short, so they sit right on the route.
- **Firelords early:** eruptions take armour off several creeps at once, permanently, and deal more
  against armour already missing. Everything behind hits harder.
- **Sludge coverage:** the aura is stack-based and its grip lingers briefly after a creep leaves
  (`unit_data.md` 4 preamble and 4.10). That is why small gaps cost little.

### 5.2a The reference maze [expert]

**`ReferencesForClaude/ExampleMazes/example_endgame_maze.tres` is a well functioning endgame maze
for advanced players**, built by the project owner on 2026-09-16. It is the authority for what
5.2 describes, and it is what an AI's endgame template should be built from. Draw it:

```
python Tools/MazeView/maze_view.py ReferencesForClaude/ExampleMazes/example_endgame_maze.tres --path
```

**It is reference material, not game content.** `ReferencesForClaude/` is excluded from every
exported build, so anything that has to load a maze at runtime needs its own copy under
`Resources/`.

**What it shows** [derived from the file, read 2026-09-16]:
- **The front rows are the attacker defence**, exactly as 5.2 says: a full row of Ultimate Ancient
  Wardens across the very front, then a row mixing Divineshrooms with a Sludge, a Titan Vault and a
  Lich, then a row of Firelords, Hurricanes and another Divineshroom around a Holy disc.
- **The upper section is vertical corridors**, filled mostly with Ultimate Orb Keepers, with
  Sludges, Hurricanes and Beastmasters at the ends of the columns.
- **The horizontal separator** carries the towers that hold a line: Divineshrooms and Hurricanes
  against the Phoenix, the Ultimate Lich, a Titan Vault, an Alchemist, Firelords and Beastmasters.
- **The lower section is vertical corridors again**, in blocks: an Arcane Orb block, then a large
  Firelord block, with Gravediggers, Divineshrooms, Hurricanes and Sludges down the sides and
  Orb Keepers down the right-hand column.
- **The bottom row closes the maze** with Gravediggers.
- **Discs fill the holes**, mostly Advanced Earth and Advanced Primal, with single Advanced Arcane
  and Advanced Holy discs in the front.
- **Beastmasters sit at the ends of vertical lines** (5.4), and the Sludges are spread so their
  auras cover the length of the maze (5.2).
- Its key positions (5.3) are the bottom closing row and the ends of the last columns: losing one
  bottom-row tower halves the route.

### 5.3 The Phoenix and the key positions [expert unless marked]
- **The Phoenix pokes holes in key positions**, shortening the route. A purely vertical maze makes
  that far easier: one hole in a long vertical wall lets creeps skip a whole lap.
- **The horizontal line at row 10-12 breaks the maze into two sections**, and the Divineshrooms
  standing in it defend it.
- **A defender repairs holes.**

**Where the key positions are** [derived]. `Tools/MazeView --holes` removes each tower in turn and
measures how much the route shrinks. On blueprint 4 and on an older endgame maze (both read
2026-09-15), the towers whose loss costs the most are:
- the closing wall at the bottom of the lane, where losing a single tower roughly halves the
  route
- the ends of the vertical tower columns
- the row 10-12 separator

So a hole-poking attacker aims at those first, and a defender protects and repairs them first.

### 5.4 Beastmasters [expert]
- **Probably the most complex tower to use properly**, and nothing a weaker opponent would ever do.
- **Each is placed aligned with a vertical line of towers**, and linked so that its beast runs
  exactly vertically, **hitting the creep corridors on BOTH the left and the right side** of that
  tower line.
- **Every vertical path creeps walk should be covered by at least one Beastmaster.**
- The positions in the reference maze (5.2a) are proper and are the reference.

**Note** [derived, to be confirmed]: the vertical sections of blueprints 2-4 have creep corridors
half a cell wide between tower columns, which fits a beast running down a column line and
catching both corridors at once.

### 5.5 The easy maze [expert]
- **An easy opponent should use only a LEFT-RIGHT maze**, but properly:
  - **starting from the very top**
  - **only half a cell between the horizontal lines**
- It sends slower and less.

**Note** [derived]:
- A half-cell corridor fits about a third more rows into the lane than a full-cell corridor
  (measured with `Tools/MazeView`'s route on 2026-09-15). Every tower row then borders two
  corridors half a cell away.
- The tutorial teaches this maze: from the very top, half a cell between rows, the same shape
  the AI generator builds.

### 5.5a Upgrading while creeps are walking [expert]
**It does not matter.** A tower stops shooting while it upgrades (`game_rules.md`, Upgrading a
tower), but losing that much uptime on one tower is very marginal. In practice an upgrade often
waits for an income payout anyway, and is simply done when the gold lands.

### 5.6 Defending in the moment [expert]
Very advanced, but the core of it:
- **Point the area-damage towers at the biggest clumps of stacked creeps.**
- **Kodo Beasts are the priority.** They have to be clicked fast, before the wave stacks up around
  them.
  - In Warcraft III Kodos are often hidden behind other units and hard to click, and the same is
    somewhat true in this build already. How to adapt that is the project owner's open
    question.
- **Orb Keepers do the focusing:** huge single-target damage, and a stun. Their range is very
  short, so **almost every Orb Keeper stands within range of a Primal disc** (the range aura).
- **In the endgame you are attacking and defending at the same time.** That gets overwhelming
  quickly, and defending can knock you out of your sending rhythm. The attention a player has is
  itself a resource.

**For the computer opponent** [derived]: clicking a Kodo that is hidden behind other creeps is
exactly the precision a human lacks. An AI that focuses every Kodo instantly would be superhuman
in a way players notice. See `ai-rework.md` 3.8.

### 5.7 Things a maze must never do [expert, decision]
- **No juggling.** Selling and rebuilding towers to reroute creeps already committed to a route
  is seen as bad behaviour in the LTW community. It is possible in the Warcraft III version and is
  planned to be removed from this game.
- **No trapping.** A builder can build towers around a live creep to trap it, and there are more
  elaborate setups. It should not happen. It is easy to detect and so should be easy to fix, and it
  is not an important issue.
- **The AI does neither, at any difficulty.**

---

## 6. Technology

### 6.1 How technology is used [expert unless marked]
- **The opening is four free technologies, which is exactly one Ultimate** (`unit_data.md` 2.3).
  [derived]
- **The opening also unlocks the Greater tower of the path it requires**, and leaves that path's
  own Ultimate two technologies away (`unit_data.md` 2.3). So every opening comes with a second
  tower line for free. [derived]
- **Every technology plays differently from tier 1 to tier 3**, with its own strengths and
  weaknesses.
- **Every technology ends in the same or a very similar endgame maze** (5.2). By tier 4 almost
  everything is researched, and towers are transformed into what their position needs. In this
  build that means returning an elemental tower to an Elemental Core and morphing it again
  (`game_rules.md`, The Elemental Core). [derived]
- **Basic towers patch a technology's weakness** (5.1).

### 6.2 What is strong right now [expert]
- **Currently the best tower is the Firelord.** Every damage tower named in 5.2 is fine.
- **The Arcane Orb is especially good:** its requirement makes the Greater Sludge Monstrosity
  buildable straight away, so it comes with a slow tower.
- **Rule of thumb:** open on a damage tower (Gravedigger, Arcane Orb, Titan Vault, Firelord,
  Moonbeam, Scorpion, Leviathan) and **get a slow tower next**.
- **The Sludge Monstrosity is a popular choice for that slow**, because its positions get
  settled early and then need no more thought.
- **Technology paths are complex and differ a lot.** Proper notes per technology will follow,
  once an AI that understands the basics exists.

### 6.3 When technology is bought [expert]
- **The first purchase is usually TWO technologies at once**, because in most cases the goal is
  another Ultimate or another 10k tower. That typically takes two.
- **The exception is a single technology that completes something useful on its own.** For
  example the Hurricane opening is one 50k technology away from the Greater Sludge Monstrosity,
  which is very useful because it brings a slow.
- **Timing, by income per payout:**
  - one 50k technology: around **100-150k income**
  - two technologies: between **200k and 400k income**, usually late tier 2 or early tier 3
    - where in that range depends on how well the starting technology handles the current
      phase of the match on its own

**Why two** [derived]: an Ultimate needs its own element's Basic and path plus another element's
Basic and path (`unit_data.md` 2.3). The opening already owns four, so the next Ultimate or
Greater tower usually lacks exactly an element's Basic and one path.

### 6.4 The twenty paths at a glance [derived from `unit_data.md` 2.3 and 4; to be corrected]

| Opening Ultimate | Identity | Also unlocks, up to Greater | Endgame role [expert] |
| --- | --- | --- | --- |
| Spellslinger (Arcane 1) | magic single target, a slowing spell burn, a splash orb at full mana | Crystal | - |
| Arcane Orb (Arcane 2) | chaos attacks that bounce, every other as spell damage, bonus vs flyers | **Sludge Monstrosity** (slow) | back damage; strong opening |
| Ancient Warden (Earth 1) | ground-only Siege splash at full damage, permanent armour erosion, self-heal | Arcane Orb | frontline vs Mountain Giants |
| Scorpion (Earth 2) | piercing single target, crits that grow as the target weakens, burst after idling | **Lich** (slow) | damage |
| Moonbeam (Fire 1) | ground-only Siege splash, very long range; lower tiers decay after being built | Harbinger | back damage |
| Firelord (Fire 2) | normal splash; procs spell damage on several targets and strips armour permanently | Annihilation Glyph | early armour strip, back damage; **best tower now** |
| Divineshroom (Holy 1) | AIR ONLY splash, slows, pushes armour below zero; the Ultimate heals towers | Beastmaster | anti-air, anti-Phoenix, front and separator |
| Titan Vault (Holy 2) | piercing multi-target amplifying spell damage; Ultimate aura slows, cuts attack damage | Moonbeam | front vs attackers, back damage |
| Lich (Ice 1) | magic splash chill; Ultimate aura cuts attack speed, burns a share of max health | Gravedigger | front vs attackers |
| Crystal (Ice 2) | piercing lance through a line of creeps, ignores armour value | Divineshroom | - |
| Annihilation Glyph (Lightning 1) | chaos single target at extreme range, ramps on one target; the Ultimate chains | Alchemist | - |
| Orb Keeper (Lightning 2) | chaos, very short range, current-health share damage, stuns | Titan Vault | early in the maze |
| Primalist (Primal 1) | generates gold per attack; armour-reducing blast | Firelord | - (economy) |
| Beastmaster (Primal 2) | Siege, a second target, a beast that runs a line and stuns ground creeps | Scorpion | stun lines (5.4) |
| Gravedigger (Unholy 1) | multi-target poison stacks that detonate; the Ultimate's detonation splashes | Leviathan | back damage |
| Alchemist (Unholy 2) | Siege splash that grows with kills; the Ultimate changes creeps' armour type | Spellslinger | - |
| Harbinger (Void 1) | pulls a creep back along the lane and burns a share of its maximum health | Ancient Warden | - |
| Leviathan (Void 2) | chaos splash that eats armour and grows its own damage | Hurricane Elemental | damage |
| Hurricane Elemental (Water 1) | piercing splash, paralyses flyers so ground towers can hit them | Orb Keeper | anti-air, flying priority on |
| Sludge Monstrosity (Water 2) | stacking slow aura, a stun on repeated hits; Ultimate amplifies physical damage | Primalist | slow coverage (5.2) |

### 6.5 Discs
- A disc fills a hole that creeps walk over. It never blocks and can never be attacked
  (`game_rules.md`, Technology discs). [derived]
- A player may own only one Ultimate disc per element. [derived]
- **When to build them** [expert]:
  - **Not before roughly 200k income.**
  - **Upgrade them only in the very endgame, at around 4 million income.** Upgrading discs is the
    LAST step of finishing an endgame maze.
- **Which ones** [expert]:
  - It depends on which discs the technology being played makes available.
  - **In the endgame it is mostly Earth and Primal discs** (attack speed and attack range).
  - Before that many of them are viable in the right situation.
  - **The Holy disc is very important in the front** (5.2).
- The reference maze (5.2a) fills its holes mostly with Advanced Earth and Advanced Primal discs,
  and carries one Advanced Holy and one Advanced Arcane disc in the front. [derived]

---

## 7. Creep traits and what answers them [derived, to be corrected]

A quick sheet built from `unit_data.md` 6.6: what each trait punishes in a maze, and the kind of
tower that answers it. It is raw material for the counter table in `ai-rework.md` 3.9. It is the
RULES' logic, not tested play.

| Trait | Punishes | Answered by |
| --- | --- | --- |
| Flying | little anti-air, or anti-air off the straight line flyers take | anti-air spread along that line (Divineshroom, Hurricane with priority on, Turret early) |
| Attacker | cheap or unsupported front towers; key positions (5.3) | Warden frontline, Lich and Titan Vault auras, Holy disc, Divineshroom heals, repairing holes |
| Skittering | towers that would otherwise pick it first | nothing specific; it is shot last |
| Ethereal | mazes relying on length alone, since it walks through towers | raw damage along the straight line |
| Elemental Warding | a maze built on one damage type | a mixed damage-type maze |
| Hardened Skin | many small hits | armour erosion first (Firelord, Warden, Leviathan), then big hits |
| Spell resistances | spell-damage towers, slows, stuns, debuffs | physical damage |
| Quickness | very long-range towers | shorter-range damage |
| Reactive Armor (Shredder) | a few very large hits | many medium hits; focus its aura escort (4.5) |
| Stoneskin, Goblin Engineering, Legendary Spell Resistance | slow-based mazes | damage rather than slows |
| Chaos Barrier, Mana Drain | mana-dependent towers | towers that do not rely on mana |
| Abyssal Carapace | nothing special, but it is a huge shield | sustained damage |
| Death Pact, Exhume Ghouls | damage only at the front, since the creep gets back up | damage spread along the route |
| Auras (Devotion, Endurance, Regen) | whatever they buff | killing the carrier first, manually if needed (4.5), and armour reduction |
| Wicked Curse, Annihilation Aura, Volatile Death | towers clustered where these creeps die or walk | spread, and killing them away from the core |
| Unfathomable Power (Demon) | nothing can kill it | nothing; its answer is being ahead (4.5) |

---

## 8. What this means for the computer opponent

The design implications are carried into `ai-rework.md`. In short:

- **Opening.** The meta start (2.1) is a scripted opening for the top levels, including the
  builder's attack order and straddling the payout. Easy opens on a left-right maze and sends
  little (2.2, 5.5).
- **Maze planner.**
  - Follow the blueprint stages (5.1) on the expert's timings: blueprint 1 by a few hundred
    income, then the front and the first elemental towers, the back during tier 2, and the tier 1
    middle and every Basic tower exchanged later.
  - Assign towers by the roles in 5.2, including Sludge coverage, Beastmaster lines (5.4), the
    Divineshrooms that hold the separator, and Orb Keepers inside Primal disc range (5.6).
  - Patch the technology's weaknesses with Basic towers, upgraded as far as the weakness needs
    (5.1).
  - Protect and repair the key positions (5.3).
- **Send planner.**
  - **Send all the time**, across every reserve that is refilling, not only the newest creep
    (3.2).
  - Balance greedy against aggressive (3.1), with the three triggers: the defender's maze value
    for the match time, and the income gap in both directions.
  - **Defend just enough, and at the top level leak a little on purpose** rather than overbuild
    (3.5).
  - Know when population is the limit (3.2), and read where the defender's damage sits.
  - **Straddle payouts** to land many creeps at once (2.1).
  - Run attacks as multi-payout sequences that can be cancelled (3.3), composed and timed to
    converge (4.2, 4.3), with the endgame pattern of 4.5 at the top level.
  - **Attackers only rarely**, against a very weak front (4.6).
  - Compare income against the benchmarks (3.4).
  - The three- and four-player ring dynamics (3.6) are a small modifier at most.
- **Defence micro.**
  - Area damage onto the biggest clumps, and Kodos focused with Orb Keepers, at the top level
    (5.6).
  - **Human-limited**: attention is shared between attacking and defending, and a hidden Kodo is
    not found instantly.
  - Flying priority on every Hurricane, at every level that builds them.
- **Technology.**
  - Open on a damage Ultimate, get a slow next, and prefer openings that come with one (6.2).
  - The first purchase is usually two technologies at a few hundred thousand income, or one
    earlier when it completes something (6.3).
- **Difficulty.** These are top-level play:
  - counter-sending against a specific technology
  - endgame send patterns
  - Beastmaster lines
  - Kodo focus
  - deliberate leaking

  The standard levels get no bonuses, ever.
- **Forbidden.** Juggling and trapping, at every level (5.7).

---

## 9. Seeing a maze: `Tools/MazeView`

`maze_view.py` draws any `TowerLayout` as text: one character per internal cell, player rows
labelled, discs marked. It can also show an approximate creep route with its length, and which
towers' loss would shorten that route most. Run it from the project root:

```
python Tools/MazeView/maze_view.py Resources/Blueprints/blueprint_4.tres --path --shape
python Tools/MazeView/maze_view.py <any layout.tres> --path
python Tools/MazeView/maze_view.py <any layout.tres> --holes 10
```

- **The first form** draws the shape only.
- **The second** names every tower with a two-letter code and a legend.
- **The third** lists the key positions (5.3).

**Draw a maze rather than pasting a drawing of it into a document**: the file changes, the paste
does not. The route is an approximation (the script says how): good for shape and relative length,
not for exact timings. A player's own saved mazes and the layout cheat's file live under `user://`
on that machine.

---

## 10. What is still missing

Numbered so an answer can name its question. Answers go into the sections above, tagged [expert].
**Much of what is left is advanced enough that it should be studied in recordings rather than
described** (10.6). Only the questions that help the core understanding are asked directly.

### 10.1 The maze
1. **Which elemental tower goes where, before the endgame.** 5.2a says what the finished maze
   holds; what an early or middle maze holds, and in what order the reference maze is reached,
   is not written down.

### 10.2 Sending and economy
1. **Sudden Death:** does the approaching retirement of tiers 1-3, or the income floor, change what
   is sent just before it? Are Treasure Goblins used?
2. **Bounty:** beyond the Timber Wolf in the opening, does bounty from kills matter to decisions, or
   is it simply a side effect of defending?

### 10.3 Technology
1. **Per path:** how it plays in tiers 1-3, its weaknesses, how to defend with it, which Basic towers
   patch it, and how to send into it. Deliberately deferred until an AI that understands the basics
   exists (6.2).

### 10.4 Difficulty
1. **What mistakes do new players typically make?** Those are the mistakes Easy and Normal should
   make. Recordings of new players are expected (2.2).
2. **Between Easy and the top level,** what should Normal and Hard feel like: a player who knows the
   rules but not the meta, and a decent regular?

### 10.5 The project owner's own open questions
Recorded so they are not mistaken for gaps in the AI's knowledge:
- how juggling will be removed from the game (5.7)
- how clicking a Kodo that is hidden behind other creeps should work (5.6)
- the tutorial, complete end to end as of 2026-09-18 and under review (`tutorial.md`)

### 10.6 What recordings of serious matches should answer
These were deliberately not described, because a recording shows them better. They are what
`Tools/ReplayMiner` (`ai-rework.md` 4.3) should be built to extract:
- **The exact opening:** tower order, builder movement and attack timing, and the first sends
  against the payout clock (2.1).
- **When to leak what**, and how many lives a good player gives up and when (3.5).
- **Send patterns** in every tier: composition, stacked or staggered, timing against payouts, and
  convergence delays (4.2, 4.3), and the tier 4 art form (4.5).
- **Attacker usage**, and how it is answered (4.6).
- **Sludge, Beastmaster and disc placements** across real endgame mazes (5.2, 5.4, 6.5).
- **Defence micro:** which creeps get focused, when, and how often (5.6).
- **Technology purchases:** what, when, and at what income (6.3).
- **How gold is actually split across creep types** while spamming for income, and how much
  attention that takes (3.2).
- **"An expensive maze for the timing":** there is no rule of thumb, so the relationship between
  a maze's value, the match clock and whether lives can be stolen has to be measured (3.1).
- **Where short-range and long-range towers stand** relative to the corridors, beyond "the most
  uptime" (5.1).
- **The transitions** between blueprint stages as they actually happen (5.1).

