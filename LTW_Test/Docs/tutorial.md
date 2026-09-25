# The tutorial

**What this file is for:** what the tutorial teaches, what it deliberately leaves out, and the
methods it teaches with, so that a lesson can be written, split, merged or cut without
re-deriving any of it. It does NOT describe the lessons one by one: their order, wording, gold
and limits are ordinary `.tres` files under `Resources/Tutorial/` and change round to round.
Nor does it carry rules of the game, which are `game_rules.md`'s.

**Status, 2026-09-20: complete from the first tower to the last opponent, and being reviewed
with the project owner.** Lesson six was rebuilt across review rounds two and three, and the
lesson board with it - see section 12. Nothing has been tried on a real new player yet.

---

## 1. Principles

These are the project owner's, and every lesson is written against them.

- **It is a real match.** Same world, economy, towers, creeps, opponents and send ring. There is
  no second game underneath, and there must never be one: a tutorial that teaches something the
  game does not do is worse than none. What differs is only what a lesson must control, and
  everything else is the defaults, so a player who finishes it recognises every number in a
  lobby. `MatchSetup.mode == TUTORIAL` is the whole gate.
- **Done, not read.** A player learns a thing by doing it. Words are as few as possible: a short
  paragraph per lesson, and tasks of a handful of words each. Reading is reserved for what
  cannot be done - what a number on the HUD means.
- **Few lessons, several tasks each.** A lesson is one subject; its tasks are the steps of it,
  ticked off one at a time.
- **Telegraphed first, open later.** Early on the player can do only the one thing asked, with
  exactly what it costs. Once the basics are in, the restrictions come off and the player plays;
  later subjects are telegraphed again only as long as it takes to introduce them.
- **Time stops as little as possible.** An untimed task holds the match CLOCK (income, unlocks),
  not the world. The world stops only for an explanation or a first-time moment, and only until
  the player says go on.
- **No skip, and no way to get stuck.** A telegraphed task cannot be failed or wandered off; an
  open one is ended by the match either way.
- **The player can lose** where the tutorial is open, and is offered a retry. Where it is
  telegraphed they cannot.
- **Principles of good play are not taught.** How to compose a maze, where to put the expensive
  towers, what to send against what - the player is shown an opponent that does these things and
  reaches their own conclusions.

## 2. What it teaches, and what it does not

**Taught**, roughly in this order - the lesson boundaries around them are free to move:

- the builder: selecting it, moving it, and that building is what it is for
- building towers on marked cells, and that towers shoot creeps coming down the lane
- waves walking through a maze and dying in it
- the left-right maze shape of `strategy.md` 5.5, built row by row, with the three basic tower
  lines in it
- upgrading towers, with the cost of each rung
- sending creeps into an opponent's lane, and that every send raises income for good
- gold, income and the payout timer on the HUD
- life stealing: a creep that gets through takes a life from its defender for its sender
- flyers and attackers, the first time the player sends one - whenever that is
- technology: every element's Basic and two paths, and the four technologies an Ultimate
  needs; the free allowance spent on one
- the Elemental Core, and one Ultimate built A RUNG AT A TIME: the Research Center opened,
  then a free technology and then the tower it just unlocked, over and over to the top of the
  branch. Each is its own task, so what a technology BUYS is done rather than read
- beating a defending opponent, then an attacking one with a proper maze

**Not taught**, deliberately:

- discs, creep abilities and tower abilities
- the blueprint screens - the tutorial draws its own plans, and the player's saved slots would
  compete with them, so they are forbidden throughout
- maze composition and tower placement strategy - see the last principle
- the builder's own attack, Sudden Death, the send ring beyond a duel, and the other
  technology modes (the tutorial is PICK)

## 3. How it telegraphs

A TELEGRAPHED task leaves exactly one thing to do and shows where. These are the methods, and
they stack:

- **Only this** (`restricts_actions`, `allowed_abilities`, `ActionLimits`). Every command card
  square not on the task's list is drawn dim and refuses a click, a key and an order. Moving and
  stopping the builder are always allowed (`always_allowed`); passives and presentation toggles
  need no listing. A SUBMENU is not free: the Build menu stays shut until a task lists it.
- **Only here** (`build_on_blueprint_only`). A tower may start only on the task's blueprint
  cells; the build ghost turns red anywhere else.
- **Exactly this much.** A telegraphed task hands over the gold it costs and no more
  (`grant_gold`), and a send task sets the reserve to exactly the sends asked for
  (`stock_creep_path`) with the clock held so nothing refills. The gold is what stops a third
  tower being upgraded when two were asked for. Wave bounty makes it slightly more, and that is
  accepted.
- **A blueprint on the ground** (`blueprint_path`): one blue square per cell still to build on,
  disappearing as each fills. The camera glides onto the first open row.
- **A golden border on the button** (`TutorialPointer`), pulsing, on the button itself and never
  the bar it sits in. It resolves every frame, in order: the button that selects the unit the
  task needs while it is not selected (`guide_unit`); for a research task, the Research Center
  button and then the square to press; the command card square showing one of the task's
  `guide_abilities` - the Build menu, then the tower in it - and nothing while an order is being
  aimed; otherwise a named HUD element (`highlight_key`).
- **Arrows in the world** (`TutorialWorldArrows`), upright and pointing down: over the builder
  while it needs selecting; over every open blueprint cell, but only while the task's tower is
  IN HAND, so they never compete with the border; over every tower a task wants upgraded, each
  gone the moment its upgrade starts. They all bob in step.
- **Research by name** (`TutorialStep.tech_ids`): only the named technologies can be
  researched, every other square is dimmed, and the Ultimate shortcuts are refused, so the
  player ends up with exactly the Ultimate the rest of the tutorial is written around. It is
  on the STEP rather than on a research-only step, because a technology and the tower it
  unlocks are one task: the border walks from the Research Center button to the square to
  press, and then to the upgrade on the tower's own card.
- **The camera held** (`pinned_camera`): pinned where the task happens when it happens somewhere
  the player would not look - the first send appears in another player's lane - and released
  the moment the task is done. Where the player only needs pointing somewhere, the camera
  GLIDES there instead and leaves them free (`looks_at`, and a blueprint's first open row).
  Every move the tutorial makes is a quick glide rather than a cut, with panning locked until
  it arrives.
- **Nothing covers the thing named.** The lesson panel steps to the right of the Research
  Center while it is open, and aside entirely for an explanation or a moment.
- **The board, one task at a time.** What is drawn is the current task and nothing else: a
  line, a tickbox, and the sentence belonging to that rung. How far through the lesson the
  player is goes in the header as a count, because a lesson can be sixteen rungs and sixteen
  rows is a wall of text with the one line that matters hidden in it.
  - **finishing a task is SHOWN.** The tick pops in and the line turns green where it stands,
    and only then does the block slide out and the next one slide in. A task that vanished
    the moment it was done left the player unsure whether what they pressed counted, and
    `delay_seconds` is the beat that gives it room.
  - **a task COUNTING is not a task changing.** A counted objective writes its own progress
    into its text - "Kill the Skeletons (12/45)" - so the words are not an identity, and
    comparing them made every kill read as a brand new task and slide the block out and back
    in for it. What identifies the task is the STEP it belongs to, since a step carries
    exactly one. The count is rewritten where it stands and nothing moves; only finishing
    animates.
  - a new LESSON still pops the whole board. See `TutorialPanel`, and `Docs/ui.md` section 2
    for the animator components it is built from.

**Explaining** is separate from telegraphing and used as little as possible:

- **An explanation** (`TutorialExplainStep`) holds the world and shows one page at a time in a
  panel in the middle of the screen (`TutorialInfoPanel`), Continue to turn it. A page about a
  HUD element frames it with the border and a short caption and dims everything else; a page
  about nothing on screen dims the lot. The lesson panel steps aside.
- **A moment** (`TutorialMoment`) is an explanation the player TRIGGERS, the first time it
  happens and whichever lesson is up: a creep about to leak, the first flyer, the first
  attacker. The world is held, the camera is pinned just down the lane from the creep so it sits
  clear of the panel, the spotlight dims everything but it, and the same centred panel says what
  it is. A player who never meets a flyer is never told about flyers.
  - **Either side of the lane sets one off, whichever gets there first** - the player's own
    creeps walking the opponent's lane, or the opponent's walking theirs. Meeting the thing is
    what the moment is for, and the first flyer a player sees is as likely to be one sailing
    over their own maze as one they sent. A creep walking the lane of whoever sent it is
    neither: that is a leak recycling it, which the player has already been shown.
  - Two of the three then read differently depending on which way the creep was going, so a
    moment carries an `incoming_body` beside its `body` and falls back to `body` when the words
    hold either way. What a flyer IS does not change direction; "select them to give them
    orders" is wrong in front of somebody else's attacker, and a leak that wins the player a
    life is the exact opposite of one that costs them. The player's own side wins a tie.

**Where it deliberately does NOT telegraph** - the OPEN tasks, fighting an opponent and building
one's own maze:

- no border, no arrows, no blueprint, no list of allowed buttons; the task and a sentence are
  all the help there is
- only what a later lesson is for is held back, and by limits rather than by pointing: the
  roster short of a tier (`holds_back_tier`), the top of the upgrade tree (`max_upgrade_gold`),
  the basic towers while elemental ones are being learned (`forbids`)
- selling is allowed; a player who sells their maze away can lose
- nothing says what the opponent's maze does well or what to send against it

## 4. Time

**Three things can be held, and the tutorial nearly always wants the smallest one.**

- **The CLOCK** (`holds_clock`, `MatchSession.hold_clock`): income payouts, creep unlocks,
  reserves refilling and Sudden Death stand still; units walk, towers go up, creeps die. It is
  what makes a task untimed. Telegraphed subjects hold it, so a payout never lands in the middle
  of one.
- **The OPPONENTS** (`holds_rivals`, `AiPlayer.hold_thinking`): neither of them plays - no
  building, no upgrading, no sending - while the rest of the match goes on. Neither of the
  other two does anything to an opponent: it builds off gold it already has, so a held clock
  leaves it free, and a held world stops the student too. It is what stops a lesson somebody
  takes their time over costing them an enemy maze grown while they learned.
- **The WORLD** (`pauses_world`, `MatchSession.hold`): everything stops and only the tutorial's
  panels answer. For moments, and for an explanation with anything moving behind it - an
  explanation may hold the clock instead where nothing is (`TutorialExplainStep`).

The clock and the world are one freeze with two ways in, so overlapping them gives the clock
back one gap rather than two. A reserve refills on the tick, so it asks `is_clock_held()` for
itself. The opponents are held separately, on the brains themselves, and their own beats stand
still with them so a released one carries on rather than firing everything it was owed.

**The creep roster has a clock of its own** (`MatchSession.unlock_elapsed_seconds`): the match
clock moved AHEAD by any lead (`unlocks_ahead_seconds`) and STOPPED at any ceiling
(`holds_back_tier`, where the last creep below a tier opens). Only start delays read it, so a
lesson can open the roster early without paying the income that time would have paid.

**A payout can be brought forward** (`next_payout_seconds`) for a task that waits on one.

## 5. The opponents

Two, both in the match from the first tick, both named by role rather than slot
(`TutorialStep.Rival`). Their profiles are named by path on `tutorial_script.tres` and are not
in `ai_config.tres`, so no menu offers them.

- **The first** spars - builds a short maze and sends nothing - until a lesson WAKES it into a
  profile that only DEFENDS: a shallow maze near the top of the lane, grown over time by an
  upgrade budget (`upgrade_target_paths`) and random cheap upgrades. A maze that stops near the
  top is what makes a leak certain once a creep is past it. While it is the opponent the lesson
  sends its own waves at the player (`TutorialWave`), never stronger than what the player has
  already beaten.
- **The second** waits on STANDBY - outside the send ring, unable to send, still counted alive so
  the match does not end when the first falls - building and growing its own maze with a lump of
  its own (`second_rival_opening_path`, `second_rival_gold`). When a lesson wakes it, it sends,
  goes on improving the maze, and is the last thing standing between the player and the end.

Waking (`wakes_rival`) takes an opponent off standby, raises its income to a share of the
player's (`rival_income_share`), hands it any head start (`grant_rival_gold`) and gives its brain
the real profile (`AiPlayer.change_profile`).

**The mazes are data.** An opponent's maze is a `TowerLayout` naming a target tower per cell
(`AiProfile.maze_layout_path`); the AI builds whatever climbs to each target and upgrades toward
it, and `upgrades_only_to_plan` keeps a wall a wall. The second opponent's shape is the project
owner's own blueprint (`tutorial_veteran_blueprint.tres`), grown by the targets in
`tutorial_veteran_maze.tres`. Its sending is bounded by `max_send_gold_per_payout` and
`sends_attackers`, its maze by `max_maze_value`. None of these principles is explained to the
player.

## 6. How it ends

When the last lesson in the script is done the match ENDS whoever is still standing
(`PlayerManager.conclude`): every creep off the field, nothing paid, sent or orderable, and the
ordinary result board, whose Continue leads back to the main menu. Cutting the script short
therefore ends the tutorial early, which is how it is iterated on.

When the player runs out of lives the world is held for good and `TutorialDefeatPanel` covers
the screen, swallowing every click, with Retry (the tutorial again, through the loading screen)
and Main Menu. It is caught on the elimination, because the match may well go on without them.

## 7. Limits, in detail

`ActionLimits`, held on `PlayerState.limits`, is what makes "only this" true. It is null for
every player in every other match. It is asked where intent becomes an order and nowhere deeper:
the card dims the square (`CommandSlot`), the panel will not open a submenu (`UnitPanel`), the
controller will not arm or send it (`CommandController`), the order road refuses it
(`CommandService`, which holds whatever the others missed), the area refuses the cell
(`PlayerArea.can_place`), and the Research Center neither opens nor accepts what it should not.

**The Research Center has a whitelist of its own on the same terms**, and it has to: once the
lesson has opened it, it stays open behind every rung that follows, and a free technology spent
on an element the lesson is not teaching is gold the next rung cannot find. So a restricted task
allows exactly the technologies it names and, naming none, allows none
(`ActionLimits.restricts_research`).

On top of any lesson's own, the script's FORBIDDEN list is refused throughout, restricted lesson
or not. The director builds fresh limits every lesson, so nothing one allowed outlives it, and
leaves the player with none that allow anything once the tutorial is over.

## 8. The pieces

| File | What it is |
| --- | --- |
| `Scripts/Game/Tutorial/TutorialStep.gd` | One task, abstract: what it says, gives, allows and points at. |
| `Scripts/Game/Tutorial/Steps/*.gd` | What FINISHES a task. One subclass per kind. |
| `Scripts/Game/Tutorial/TutorialScript.gd` | The tasks in order, the moments, and the board: opponents, lives, what is always allowed or never. |
| `Scripts/Game/Tutorial/TutorialDirector.gd` | Which task is open, what it handed over, what has happened since. |
| `Scripts/Game/Tutorial/TutorialSetup.gd` | The match it is played in: lanes, names, settings. |
| `Scripts/Game/Tutorial/TutorialWave.gd` | One wave a task sends at the player. |
| `Scripts/Game/Tutorial/TutorialPage.gd` | One page of an explanation. |
| `Scripts/Game/Tutorial/TutorialMoment.gd` | A first-time event worth stopping for. |
| `Scripts/Game/Tutorial/TutorialGuide.gd` | Which unit a task walks the player to, and whether it is selected. |
| `Scripts/Game/Tutorial/TutorialWorldArrows.gd` | The arrows in the world. |
| `Scripts/Game/Ai/AiPlayer.gd` | `hold_thinking`, which is how a lesson stops an opponent. |
| `Scripts/Game/ActionLimits.gd` | What one player may do when that is less than the rules allow. |
| `Scripts/UI/TutorialPanel.gd` | The lesson, and the one task on screen. |
| `Scripts/UI/TutorialTaskRow.gd` | That task: its line, its tickbox, and the tick going in. |
| `Scripts/UI/TutorialPointer.gd` | The golden border, its caption, and the dim around it. |
| `Scripts/UI/TutorialInfoPanel.gd` | Explanations and moments, in the middle of the screen. |
| `Scripts/UI/TutorialSpotlight.gd` | The dim around one thing in the world. |
| `Scripts/UI/TutorialDefeatPanel.gd` | Running out of lives: Retry, or the main menu. |
| `Resources/Tutorial/` | The lessons, the script, and the mazes. |
| `Resources/Config/Ai/ai_tutorial*.tres` | The opponents' profiles. |

## 9. Changing it

- **Order, split, merge or cut** is editing the list in `tutorial_script.tres`. A step with
  `continues_lesson` is the next task of the lesson before it; one without starts a lesson.
- **What a task says, gives or allows** is its own `.tres`. The files were first written by a
  scratch generator; they are the authority now and are edited by hand.
- **A new kind of task** is a `TutorialStep` subclass with `is_complete`, plus a reading on the
  director if it needs one. Prefer what `MatchStats` already counts, or the ground itself.
- **A new thing to point at** is one entry in the two parallel arrays on `TutorialPointer` in
  `match_hud.tscn`, checked against each other at boot.
- **The opponents' strength** is their profiles, their mazes, their gold and lives on the script.

Boot once after any of it: `TutorialScript.validate()` refuses a missing lesson, an untitled
lesson head, a path that does not resolve, an opponent or moment it cannot use, and an
explanation that does not hold the world. **A typed array in a `.tres` is all or nothing** - one
entry that fails to load empties the list silently - and that check is what turns it into a
message.

## 10. Known gaps

- **Untested with a real new player.** Pacing, wording and both opponents' strength are guesses
- **The first opponent falls quickly** once the player is set free, and the second is hard for a
  player who does not change what they send. Neither has been tuned
- **No way back in.** Leaving part way starts again from the first lesson
- **It does not react to mistakes.** A player who runs out of lives is offered a retry and
  nothing more

## 11. Testing it

`Scripts/Dev/TutorialProbe.gd`, run as `Scenes/Dev/tutorial_probe.tscn` headless, plays the
whole tutorial through the real order road faster than real time. In every telegraphed task it
also TRIES what must be refused - a tower off the list, a cell off the blueprint, an upgrade,
another creep, a technology off the list, an Ultimate shortcut - and checks nothing happened.
It checks where the border resolves, how many arrows stand, that explanations and moments hold
the world and show the right panel, and how the tutorial ends. When the last opponent wakes it
also checks the four-technology rule the technology lesson teaches: the technologies the
player ends up with raise a Firelord to the Ultimate and stop the Glyph at the Greater, whose
partner is Unholy (2). Against each opponent it plays
for real and notes how the fight goes before ending it; against the first it keeps it standing
until every moment has fired. `-- lose` runs the player out of lives instead and checks the
defeat screen. It dispatches on the lesson FILE name, so a lesson renamed or added needs a
line there.

It is scaffolding under `Scripts/Dev`, kept while the tutorial is iterated.

Run WINDOWED with `-- shots` it saves screenshots to `user://tutorial_shots/` at the moments
worth looking at - the only way to see where something DRAWS, since headless draws nothing.

`-- skip` takes the DEV LESSON SKIP first and plays from the technology lesson, which is both a
check of the skip and a run of the last two lessons without the first hour in front of them.

**The DEV lesson skip is scaffolding too, and it is in `TutorialDirector` rather than here**
because it has to answer a key press in a real run. `DEV_SKIP_LESSON_KEY` leaves the lesson on
screen behind as though it had been played; `DEV_SKIP_TO_TECH_KEY` presses that until the
technology lesson is up, found by asking which step opens the Research Center rather than by
counting lessons. Both are on the numpad beside the cheats and on
`GameConfig.cheats_enabled` with them, so the skip is already off wherever they are, and it
goes out with the review rounds - the block at the end of that file is the whole of it.

What it settles is read off the skipped tasks rather than written down, so a lesson re-ordered
or rewritten needs nothing changed: every task's grants are applied, every task's blueprint is
built into the player's zone, an opponent a task waited to see beaten has every life taken off
it, and any opponent with an authored maze has it built and paid for. What it cannot reproduce
is a played match's INCOME, which comes from sending: a skipped run arrives on the base income
rather than on what twenty minutes of sending would have earned.

**Print which lesson was reached and what was checked, not whether there were errors.** A
tutorial that stalls part way and one that runs to the end look the same in a quiet log.

## 12. Picking it up

The tutorial is built in review ROUNDS: the project owner plays it, sends a list of notes, and
each round is implemented, checked with the probe (headless, then windowed screenshots that are
actually looked at) and committed. Keep to that, and keep the principles in section 1 - most
notes so far have been about them: shorter words, less stopping, a border on the button rather
than anything beside it, nothing shown before it is needed.

**Round two, 2026-09-20, lesson six rebuilt.** The owner's notes and what they became:

- the lesson no longer stops the match for the player. It holds the CLOCK and both OPPONENTS
  and nothing else, so the world moves and a student who takes twenty minutes over it meets
  exactly the Veteran a quick one does
- a task allows only its own rung, so nothing else can be upgraded, nothing can be sold, no
  upgrade can be called off and nothing can be researched off the list - the four ways a
  player could spend their way out of the lesson and be stuck in it
- no gold figures in the words. The lesson hands over what each rung costs
- the open "rebuild your maze" task is gone. Lesson seven is where the player is free, and
  they arrive at it with gold left over to build with

**Round three, 2026-09-20, one rung one task.** Round two had merged a technology and the
tower it pays for into a single task; that is undone, and the lesson is longer and flatter:

- the three explanation pages that opened it are GONE. Nothing in lesson six stops the world
  or asks to be read before it can be acted on
- every rung is its own task - open the Research Center, research one technology, press one
  upgrade - and the board shows one at a time, so the length costs the player nothing
- lesson seven starts both survivors on the same income and opens the creep roster to the
  same tier for both, so the last fight begins level

**Still open with the owner:**

- how strong both opponents should be - the first falls fast, and the second now banks an
  income it cannot spend, since what paces its sending is a beat rather than gold (section 10)
- whether the payout the income lesson waits on should only be brought forward for that task,
  as it is, or the whole tutorial's payout beat shortened
- how much gold lesson six should leave over for the maze the player builds in lesson seven
- "a 10k Glyph tower" was read as the Greater Annihilation Glyph, and the second opponent's
  elemental Ultimate as the Annihilation Glyph's own end
