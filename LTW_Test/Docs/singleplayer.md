# Single player and the opponent AI

**What this file is for:** the computer opponent. What it is made of, why it is shaped that
way, what it can and cannot do today, and what to build next. It carries no numbers - every
one of them is authored on an `AiProfile` `.tres` and is meant to be turned - and no rules of
the game, which are `game_rules.md`'s.

Read `content.md` first if you are adding a difficulty, and `game_rules.md` if you are
arguing about what the AI *should* do. This is how it does it.

---

## 1. What single player IS

A SKIRMISH is a real match, offline, with computer opponents in some of the lanes. It is not a
mode with rules of its own: the same world, the same economy, the same towers, the same send
ring, the same win condition and the same end screen. The only things that differ are that
there is no network and that some of the lanes are played by a profile.

That is the load-bearing design decision in the whole feature, and everything below follows
from it:

- **the settings are the LOBBY's settings.** `SkirmishSetup` instances the very same
  `lobby_settings_panel.tscn` a host edits, in a local mode - see `LobbySettingsPanel.show_local`.
  A skirmish is therefore played by the rules a lobby plays by, clamped by the same
  `sanitise()` the server runs, rather than by a second copy of them that drifts
- **the AI is a PLAYER.** It owns a slot, a `PlayerState`, an area, a builder and senders.
  Nothing in the simulation knows it is not a person
- **there is no ranked skirmish**, because ranked means two results are comparable and a
  result against a computer opponent is not comparable with anything. The Ranked tick still
  sits on the panel, because what it really does is LOCK the rules to the defaults - a
  perfectly good thing to want in a practice game. It simply never reaches a ladder

## 2. The pieces

| File | What it is |
| --- | --- |
| `Scripts/Config/AiProfile.gd` | One DIFFICULTY, as data. Every number the brain reads. |
| `Scripts/Config/AiConfig.gd` | The list of them, in the order a dropdown shows them. On `References`. |
| `Scripts/Game/Ai/AiDirector.gd` | Creates one brain per AI seat. In the match scene, on `References`. |
| `Scripts/Game/Ai/AiPlayer.gd` | ONE BRAIN. The rules. |
| `Scripts/Game/Ai/AiMazePlan.gd` | WHERE the towers go, and in what order. |
| `Scripts/Game/Ai/AiHand.gd` | Finding the button and pressing it. Every order goes through here. |
| `Scripts/UI/Menus/SkirmishSetup.gd` | The setup screen. |
| `Resources/Config/Ai/*.tres` | The difficulties. |

`MatchSetup.mode` is what says a match is a skirmish, and `MatchPlayer.ai_difficulty` is what
says a seat is a profile rather than a person. Both are ordinary serialisable fields, so a
lobby that one day offers an AI seat costs no wire format change.

## 3. The shape of the brain, and why

**It is a list of RULES run on a beat.** Every rule is a question about the world right now
and an order if the answer is yes. They are tried in priority order and the pass stops at the
first one that spends gold.

That is Age of Empires II's shape and it was chosen deliberately over the two obvious
alternatives. A STATE MACHINE makes every new behaviour a state that has to be reachable from
every other one, and the transitions become the thing you maintain. A PLANNER needs a model of
the world good enough to simulate forward, which for a game where the other player decides
what arrives in your lane is a model you cannot have. A rule list grows by one rule.

The rules today, hardest first:

1. **OPENING** - spend the free research on an Ultimate, once.
2. **SEND** - buy creeps for whoever this AI is attacking, on its own beat.
3. **MAZE** - put up the next tower in the plan.
4. **UPGRADE** - raise a tower that is already standing.

Sending sits above building, which is not the obvious order and is there for a reason worth
knowing: a send fires on a beat and a build fires whenever there is ten gold, so a build rule
asked first wins every race and the AI never sends at all. Income compounds and a tower does
not, so the beat wins the tie.

## 4. IT CANNOT CHEAT, and that is structural

Every order the AI gives goes down the road a player's click takes: through `AiHand`, into
`Commands`, into the same `ability.execute()`, refused by the same world. It pays the same
gold, waits the same build time, is refused the same placements, and is refused a send it
cannot afford by the same `can_execute` that greys the button.

It is not trusted not to cheat. It is simply never given another way in.

Two things make that work:

- **`CommandService.submit_for` and `submit_player_action_for`** name the slot explicitly,
  because an AI is a player at this machine that nobody is sitting at. They are NOT a way
  round ownership: online, the server overwrites `player_slot` from the peer id on arrival, so
  a slot written by a caller is thrown away exactly as a modified client's would be
- **the brain asks the CARD**, not the simulation. `AiHand.build_ability` walks the builder's
  own command card - submenus included - to find the button that places a tower. An ability
  that is not reachable from that card is one the order road would refuse anyway

The one thing that is *not* routed as an order is the tutorial's grants, and that is a
different feature with a different justification - see `tutorial.md`.

## 5. What it builds: a plan is a FILE

`AiMazePlan` is a list of internal cells with a target tower type against each, in build
order. Two ways one is made:

**A SAVED LAYOUT.** A profile names a `TowerLayout` by `res://` path - the very resource a
player's blueprint is. So teaching an opponent a new maze is *saving one from your own
builder* and dropping the file in, not writing code. This is the important half and it is
where the feature is meant to grow.

**THE GENERATED ZIGZAG**, for a profile that names no layout: rows of towers across the lane
with a single gap, alternating sides, so creeps walk left, right, left all the way down. It is
the simplest maze the game has and it is the one the tutorial teaches - which is exactly why
an easy opponent should be building it. A player learning the shape should be playing against
the shape.

The build ORDER is front to back whichever way the plan was made, because a tower defence is
lost at the top of the lane and because that is how a person builds one. An AI half way
through a maze then looks like a player half way through a maze rather than like a scatter.

**A plan names a TARGET, not the tower to place.** Most of a real maze is towers nothing can
build directly - the builder places a 10g Basic or an Elemental Core and everything above them
is reached by upgrading. So an entry says where the maze is going, `_placeable_for` resolves it
back down to whichever buildable tower can still climb to it, and the upgrade rule does the
climbing. `AiHand.branch_reaches` is the walk.

## 6. The economy: three floors, and two failed attempts

This is the part that took measuring, and both earlier versions looked fine in code.

**Attempt one: no floors.** The cheapest rule wins every race against an empty purse. The AI
built a beautiful maze and, in twenty minutes, never sent a single creep - its gold was zero
every time the send rule was asked.

**Attempt two: one shared reserve.** The same thing one rule along. Upgrades, being cheap and
constant, ate every coin that arrived, and the maze stopped growing at eight towers for the
rest of the match.

**What it is now: one floor per rule, and they go up in the order the spending matters least.**

| Floor | Rule it gates | Why it is where it is |
| --- | --- | --- |
| `send_floor_gold` | SEND | Lowest. Income compounds and a tower does not. |
| `build_floor_gold` | new towers | Middle. |
| `upgrade_floor_gold` | UPGRADE | Highest, so upgrading is what a RICH AI does rather than what every AI does constantly. |

Gold filling up therefore switches the rules on one at a time: an AI with a little sends, with
more also builds, with a lot also upgrades. None of the floors applies until there is a maze
worth defending (`min_towers_before_sending`), so an AI still opens by building flat out.

The send beat is deliberately **not reset on a beat it could not afford**. Once the beat is
due the AI sends the moment it can pay, which turns an income tick into a send rather than
into a wasted fifteen seconds.

Measured after that change: a Normal opponent took its income from 20 to 63 in three minutes
of match time, built a maze of 28 towers, sent 27 creeps and won.

## 7. Difficulty: where it comes from

**From better DECISIONS, not from cheating and not mainly from reflexes.** That is the AoE2
lesson and it is the easiest thing to get wrong. An opponent that plays the same game slowly
is a worse teacher than one that plays a simpler game properly.

So the axes, roughly in order of how much they actually matter:

1. **the maze.** An easy AI builds the short generated zigzag; a hard one builds a maze a
   person saved. This is most of the difference and it is authored rather than coded
2. **the roster.** Which towers it ends up with, which is the upgrade targets in its plan
3. **the economy.** The three floors and the send beat - how much of its gold goes to
   offence, and how early
4. **the technology.** Whether it takes an Ultimate at the start at all
5. **the handicaps**, and these belong at the EASY end only: `decision_seconds` is the honest
   reaction time - the AI does not look at the world between passes - and
   `distraction_chance` skips a whole pass. Deliberately a skipped pass rather than a
   deliberately worse decision: an AI that plays badly on purpose teaches a player bad habits

`ai_tutorial.tres` is the fifth profile and is not selectable. It is a sparring partner: it
builds a short maze so the tutorial has something for a creep to walk through, and it never
sends, upgrades or researches. `AiConfig.selectable_indices` is what keeps it out of the
dropdown, and the dropdown therefore maps a POSITION to a profile INDEX - the two are
different numbers and anything that assumes otherwise offers a difficulty nobody should pick.

## 8. What it does NOT do yet

In roughly the order they are worth doing. Everything here is a rule or a field, not a
rewrite - which is the point of the shape.

- **It does not counter anything.** It sends the most expensive creep it can afford and
  defends with whatever its plan says. A real opponent answers what is in its lane: Warden at
  the front against Mountain Giants, Divine Shroom and Hurricane spread through the maze
  against Phoenix and flyers, Orb Keeper at the start for percentage damage, armour reduction
  early so everything behind it hits harder, Sludge spread so its slow covers every point.
  This wants a plan that names a ROLE per cell rather than a tower type, and a rule that reads
  what is walking
- **It never uses elemental towers or discs.** The Elemental Core is on its build menu and the
  upgrade walk would reach the whole roster, but nothing tells it which element to research or
  which path to take. This is the single biggest gap: `game_rules.md` is clear that Basic
  towers do not win matches, and a hard AI that never sells them is a hard AI that loses late
- **It never sells.** A real endgame maze has sold most of its Basic towers to pay for
  elemental ones
- **It does not place discs in the holes of its maze**, which is where the expanded blueprint
  idea pays off: a layout that carries disc types as well as tower types would give the AI
  both for free, since `TowerLayout` already stores a `unit_type_id` per cell and a disc is an
  ordinary building
- **It does not command attacker creeps**, which are the only creeps their owner can steer
- **It does not react to being attacked at all** - no emergency tower, no panic upgrade
- **It plays offline only.** `AiPlayer` already guards on `MatchSession.is_authority()` and
  rolls on the shared match RNG, so the arithmetic is deterministic; what is missing is a
  decision about WHERE an AI lives in a lockstep match. One peer running it and sending the
  orders is the obvious answer and the guard is already the right shape for it

## 9. Adding a difficulty

1. Copy a `.tres` in `Resources/Config/Ai/` and change the numbers.
2. Add it to `profiles` in `ai_config.tres`, in the place it belongs in the order - **easiest
   first**, because that array IS the order the dropdown shows.
3. Boot once. `AiConfig.validate()` refuses an empty list, a null entry, and a profile naming
   a maze or a tower that does not resolve.

**The index is not an authored id.** Inserting a difficulty in the middle renames every seat
above it, which is fine for a setting chosen on a screen and thrown away with the match, and
is exactly why it must never be written into a save or onto the wire as an identity.

## 10. Testing it

`Scripts/Dev/OpeningProbe.gd` is scaffolding and is meant to be deleted, but the shape is
worth repeating: a scene that parks a `MatchSetup` in `MenuNavigation.pending_match`, instances
`Main.tscn` as a child, and prints what the AI has managed every few seconds. **Print what was
actually achieved - gold, income, towers, sends, upgrades - and not "no errors"**: a brain that
never ran and a brain that ran perfectly look identical from outside, and both of the economy
bugs above were invisible in a log.

Set the probe's `process_mode` to `ALWAYS`, or it stops counting exactly while the thing it is
watching is holding the world.
