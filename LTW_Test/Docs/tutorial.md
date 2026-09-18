# The tutorial

**What this file is for:** how the teaching match is built, so that changing what it teaches
is editing content rather than reading code. It carries no lesson WORDING - that is in ordinary
`.tres` files under `Resources/Tutorial/Lessons/` and is meant to be argued with - and no rules
of the game, which are `game_rules.md`'s.

**Status, 2026-09-18: first rework landed, more iterations to come.** The lessons after the
sending lesson are out of `tutorial_script.tres` for now (their files are the `later_*` ones)
while the lessons are gone over one at a time. The tutorial was rebuilt
around three wishes of the project owner: far fewer and far shorter lessons; time that stops
only when it has to, with the player held by what they HAVE instead; and an opening where the
player can do only the one thing they are asked, with exactly the gold it costs. What it
teaches follows `strategy.md`: the maze it builds is the proper left-right maze from 5.5.

---

## 1. The tutorial is a real match

Same world, same economy, same towers, same opponent machinery, same send ring. There is no
second game underneath it and there must never be one: a separate scene would be a second thing
to keep working, and a tutorial that teaches something the game does not do is worse than none.

What differs is only what a lesson has to control. `TutorialSetup` builds the match and
`TutorialDirector` sets the board on its first tick:

- **three lanes**: the player, then the FIRST opponent, then the SECOND, in ring order and never
  shuffled
- **no starting gold and no starting income.** A lesson hands over exactly what its task costs
- **no opening phase.** The match clock starts at the moment the first creep can be sent,
  because the first lessons hold the clock anyway and the sending lesson must find its creep open
- **fewer lives for the opponents** and plenty for the player, both on `tutorial_script.tres`:
  beating an opponent is a lesson, and a lesson should take minutes
- **technology is PICK**, so the technology lesson has the player spend the allowance themselves

Everything else is the defaults, deliberately: a player who finishes the tutorial and opens a
lobby should recognise every number they saw.

`MatchSetup.mode == TUTORIAL` is the whole gate. `TutorialDirector` lives in the ordinary match
scene and costs a multiplayer match and a skirmish one comparison.

## 2. The shape of it

Three parts, and the lessons are written against this shape:

1. **THE HELD OPENING.** The match clock stands still, the player may do only what the lesson
   asks, and every lesson hands over the gold for its task. They select the builder - the Build
   menu is shut until they have - build a few towers in the middle of the first row, watch two
   small waves walk round them, close the row and build a second one, watch a bigger wave zigzag
   through, and send their first creeps from a reserve set to exactly the number asked for.
   Nothing is timed. The waves are real packs, so their Timber Wolves pay a little bounty on
   top of the granted gold; that is accepted rather than engineered away.
2. **THE FIRST OPPONENT.** The sending lesson: the camera is held on the first opponent's lane
   while the player sends their first creeps from a reserve set to exactly the number asked
   for, with nothing else allowed. Then the world stops for an EXPLANATION of the numbers at the
   top of the screen - gold, income, the payout timer - and the player watches one payout land.
   Then the limits come off, the clock runs, the
   income is set to a lump, the creep roster is moved ahead, and the first opponent is WOKEN
   from sparring into a profile that DEFENDS and never sends - the lesson keeps sending its own
   waves at the player instead, none stronger than the opening already threw. The lesson ends
   when it is beaten. This is where the basics are played rather than explained.
3. **THE SECOND OPPONENT.** It has been in the match from the start, building a maze on STANDBY
   outside the send ring, so part 2 was a plain duel. Beating the first brings it in, the
   Research Center opens, and its half teaches technology and elemental towers. Beating it ends
   the match, and the ordinary result board takes over.

**How it ends.** When the last lesson in the script is done the match ENDS, whoever is still
standing (`PlayerManager.conclude`): every creep is taken off the field, nothing is paid or sent
any more, nothing more can be ordered (`ActionLimits.nothing`), and the ordinary result board
opens - its Continue leads back to the main menu rather than to a match summary. So cutting the
script short is enough to end the tutorial early, which is how it is iterated on. When the
player runs OUT OF LIVES the world is held for good and `TutorialDefeatPanel` covers the screen,
swallowing every click, with Retry (the tutorial again, through the loading screen) and Main
Menu. It is caught on the elimination rather than on the match ending, because the match
usually goes on without the player - two opponents are still standing.

## 3. The pieces

| File | What it is |
| --- | --- |
| `Scripts/Game/Tutorial/TutorialStep.gd` | ONE LESSON, abstract. What it says, gives, allows and points at. |
| `Scripts/Game/Tutorial/Steps/*.gd` | What FINISHES a lesson. One subclass per kind. |
| `Scripts/Game/Tutorial/TutorialScript.gd` | The lessons in teaching order, and the board: opponents' profiles, lives, what is always allowed. |
| `Scripts/Game/Tutorial/TutorialDirector.gd` | Which lesson is open, what it handed over, what has happened since. |
| `Scripts/Game/Tutorial/TutorialSetup.gd` | The match it is played in: lanes, names, settings. |
| `Scripts/Game/Tutorial/TutorialWave.gd` | One wave a lesson sends: a delay, a creep, a number of sends. |
| `Scripts/Game/Tutorial/TutorialPage.gd` | One page of an explanation: its words, the HUD element it is about, a caption. |
| `Scripts/UI/TutorialInfoPanel.gd` | An explanation's page, in the middle of the screen. |
| `Scripts/UI/TutorialDefeatPanel.gd` | The screen for running out of lives: Retry, or the main menu. |
| `Scripts/Game/Tutorial/TutorialMoment.gd` | Something that stops the match the first time it happens, whichever lesson is up. |
| `Scripts/Game/Tutorial/TutorialGuide.gd` | Which unit a lesson walks the player to, and whether it is selected. |
| `Scripts/Game/Tutorial/TutorialWorldArrows.gd` | The arrows hovering over the builder and the open blueprint cells. |
| `Scripts/Game/ActionLimits.gd` | What one player may do when that is less than the rules allow. |
| `Scripts/UI/TutorialPanel.gd` | The lesson on screen, its progress, and the way on. |
| `Scripts/UI/TutorialPointer.gd` | The golden border on the HUD button a lesson wants pressed. |
| `Scripts/UI/TutorialSpotlight.gd` | The dim around one thing in the WORLD. |
| `Resources/Tutorial/` | The lessons, the script, and the mazes they draw. |
| `Resources/Config/Ai/ai_tutorial*.tres` | The sparring partner, and the two profiles the opponents wake into. |

## 4. A lesson is a resource, and it owns four things

The same shape everything else in this project that carries behaviour has. What makes a lesson
a BUILD one rather than a SEND one is which subclass it is, so nothing anywhere switches on a
kind.

**WHAT IT SAYS** - a title, a paragraph, and one line in the imperative saying what to do now.
**Short is the rule**: a lesson is read by somebody who wants to be playing. Each TASK is a row
with a tickbox on the right that gets a green tick when it is done, and a task that can be
counted says what it counts (`progress_label`): "Towers built: 1 / 4", "Waves killed: 2 / 4",
counting only what this lesson asked for. A wave is every entry sharing one delay, and it is
killed once none of its creeps is still in the lane (`TutorialWaves`). A LESSON CAN BE SEVERAL TASKS:
each task is a step of its own - its own gold, limits, blueprint, highlights and waves - and a
step with `continues_lesson` set is drawn as the next row of the lesson before it, under that
lesson's title, rather than as a lesson of its own (`TutorialScript.lesson_range`). Tasks still
to come are shown faded, so the player sees the plan. An UPGRADE task is split in two, each
granted exactly its own gold, because the gold is what stops a third tower being upgraded; it
is finished by towers of the target type STANDING (`TutorialOwnStep`), with arrows hovering over
the towers to upgrade (`arrows_on_towers_path`). A wave lesson can count creeps rather than
waves (`counts_creeps`), for one big wave where "1 / 1" says nothing. A new lesson
arrives with a small POP of the whole board, about its own middle so it never leaves the screen.

**WHAT IT GIVES** - gold, income (added, or SET once with `set_income`), a reserve of sends set
to an exact number, a blueprint, waves in the player's lane, an opponent woken, the Research
Center opened, and the creep roster moved ahead or held short of a tier - see section 5.

**A lesson waits before it opens** (`delay_seconds`): a beat after the last one is done, to see
the last tower go up or the last creep die. The panel says the last lesson is done meanwhile, and
everything that lesson held stays held through the gap.

**AN EXPLANATION** (`TutorialExplainStep`) is the one kind of lesson that is READ rather than
done, for what cannot be done - what the numbers on the HUD mean. It holds the world, hides the
lesson panel, and shows one `TutorialPage` at a time in the middle of the screen: the element
the page is about gets the golden border and a short CAPTION under it, everything else is
dimmed, and Continue turns the page. Reach for a task first; keep an explanation to a handful of
pages.

**WHAT IT ALLOWS** - whether the match clock runs, and whether the player is held to a short
list of abilities and to the blueprint's cells. See sections 5 and 6.

**WHEN IT IS DONE** - `is_complete(director)`, asked every tick of the current lesson and of
nothing else. It reads the world and must not change it. **Nothing in the builder, the sender or
the Research Center knows a tutorial exists**: a lesson is finished by the world reaching a
state, and the counters come off `MatchStats`, which is keeping them for the end screen anyway.
A lesson asking "four sends" subtracts against a mark the director took when it opened.

Two readings are deliberately NOT counters. A BUILD lesson with a blueprint reads the GROUND -
every cell of the plan has a tower of the player's on it - because a count is wrong both ways:
a tower started and cancelled counts once and stands nowhere, and a plan whose first row is the
last lesson's already has towers a count would not see. And the technology lesson counts what
is OWNED in total, because research can be undone inside its window.

## 5. Time: the clock, the world, and the anti-softlock rule

**Two different things can be held, and the tutorial nearly always wants the smaller one.**

- **The CLOCK** (`TutorialStep.holds_clock`, `MatchSession.hold_clock`). Income payouts, creep
  unlocks, reserves refilling and Sudden Death stand still; units still walk, towers still go
  up and creeps still die. This is what makes a task untimed: a player asked to build a row
  takes as long as they like, and nothing the clock times moves on without them. The held
  opening holds it; everything after lets it run.
- **The WORLD** (`TutorialStep.pauses_world`, `MatchSession.hold`). Everything stops and only
  the lesson panel answers a click. Off for every lesson today. It is there for something that
  would really go wrong while the player reads, and nothing should.

The two are one freeze with two ways in, so a lesson holding the clock while something else
pauses the world gives the clock back one gap when both let go, not the same gap twice.

A reserve refills on the TICK rather than by reading the clock, so it asks `is_clock_held()`
for itself - that is what keeps the sending lesson's reserve at exactly what was set.

**The creep roster has a clock of its own** (`MatchSession.unlock_elapsed_seconds`): the match
clock, moved AHEAD by any lead and STOPPED at any ceiling. A lesson moves it on with
`unlocks_ahead_seconds` and stops it short of a tier with `holds_back_tier` - it runs until the
last creep below that tier is open and stands there. Only a creep's start delay reads it, so
income is paid exactly as it would have been. Moving the match clock itself instead would pay
every income payout inside the skipped time on the next tick.

**A MOMENT holds the world** (`TutorialMoment`, on the script rather than in the lesson list):
the first time the player's creeps are about to leak past a row nothing can reach, the first
flyer they send, the first attacker. Each fires once, whichever lesson is up - a player who
never sends a flyer is never told about flyers, and one who sends one late is told then. The
world is held under its own name, the camera is pinned on the creep, the spotlight dims
everything else, the panel shows it with an OK, and the lesson underneath waits.

**There is no skip.** A lesson cannot be passed without doing it, and a tutorial that offers a
way out invites taking it. What makes that safe is the held opening's design: exact gold, exact
cells, nothing else allowed - cancelling a tower build is forbidden throughout for the same
reason - so it cannot be got stuck in; and a lesson whose end is an opponent beaten is ended by
the match either way.

## 6. Limits: only this, only here

`ActionLimits`, held on `PlayerState.limits`, is what makes "only the one thing the lesson asks
for" true rather than hoped for. It is null for every player in every other match, so an
ordinary match pays one lookup and nothing changes.

It is a WHITELIST: a restricted lesson names the abilities that work (`allowed_abilities`), the
script names the few every restricted lesson allows on top (`always_allowed` - moving and
stopping the builder, calling off an order), and a passive or a presentation toggle is allowed
without being named. A SUBMENU is not: which menus open is part of what a lesson teaches, so
the Build menu stays shut until the lesson about building lists it. Everything not allowed is
drawn dim. `build_on_blueprint_only` adds the blueprint's cells as the only place a tower may
start. `max_upgrade_gold` keeps the top of the upgrade tree back even on a lesson that
restricts nothing else. The Research Center is locked until a lesson opens it and stays open
after.

On top of all of it the script carries a FORBIDDEN list (`forbidden_abilities`), refused in
every lesson, restricted or not: the builder's blueprint screens, whose saved mazes would compete
with the one a lesson draws.

It is asked where intent becomes an order, and nowhere deeper: the command card dims the square
(`CommandSlot`), the panel will not open a submenu (`UnitPanel`), the controller will not arm or
send it (`CommandController`), the order road
refuses it (`CommandService`, which is the one that holds whatever the other two missed), the
area refuses the cell so the build ghost turns red (`PlayerArea.can_place`), and the Research
Center neither opens nor accepts an order.

The director builds a fresh one every lesson rather than editing it in place, so nothing a
lesson allowed can outlive it, and clears it when the tutorial ends.

## 7. The opponents

Both start as the SPARRING PARTNER (`ai_tutorial.tres`): they build a short maze with gold the
script hands them, and send nothing. A lesson WAKES one with `wakes_rival`:

- it leaves standby, if it was on it
- its income is raised to a share of the player's (`rival_income_share`), because a partner
  that sent nothing earned nothing and would otherwise wake a match behind
- its brain is handed its real profile through `AiPlayer.change_profile`. The profiles are
  named by path on the script, not listed in `ai_config.tres`, so no menu can offer them

The partner's zigzag has the same rows and corridors as the profiles they wake into, so the
short maze is the top of the long one and the woken opponent simply carries on building it.

The FIRST opponent wakes into a profile that only defends: it never sends, never builds below
the partner's rows, and upgrades nothing but an UPGRADE BUDGET (`AiProfile.upgrade_target_paths`)
- one named tower per entry, each claiming the tower nearest the spawn that can climb to it,
spaced out by `upgrade_seconds` so it gets stronger over time rather than all at once. On
top of that, `random_upgrade_seconds` has it take one random rung on one random unclaimed tower
now and then, capped in price by `random_upgrade_max_gold`, rolled on the brain's own stream. A maze
that stops near the top of the lane is what makes a leak certain once a creep is past it, and
the moment about life stealing is built on that.

**STANDBY** (`PlayerState.standby`) is what lets the second opponent sit in the match through
the first half. The ring skips a standby player exactly as it skips an eliminated one, so
nothing is sent to them and nothing that leaks walks into their lane; a standby player cannot
send; and they still count as ALIVE, which is what keeps the match from ending the moment the
first opponent falls. It is offline only, like the limits: set by the tutorial, never
replicated.

**Waves of the lesson's own** (`waves`, a list of `TutorialWave`: a delay, a creep, a number of
SENDS) put creeps into the player's lane before any opponent sends. Each send is a whole pack,
as `SendBuilding` spawns it, and the creeps are the first opponent's, so the leak and the life
steal resolve as in a real match. Two entries with the same delay are one mixed wave. The lesson
waiting on them finishes when every wave has gone out and the lane is EMPTY, rather than on a
kill count: a creep that leaks walks on or leaves, so an empty lane always arrives.

## 8. Saying where, and saying which

**A BLUEPRINT on the ground.** One blue square per cell still to build on, disappearing as each
is filled - exactly "these ones, in any order". It is the same overlay the builder's Show
Blueprint command drives. A lesson names its blueprint by `res://` PATH rather than by one of
the player's slots, which are theirs. The camera is moved onto the first row still to build.
The mazes are the left-right maze of `strategy.md` 5.5 - from the very top, half a cell
between rows - and the early lessons' plans are its first rows, so they grow into it.

**A GOLDEN BORDER on a HUD BUTTON** (`TutorialPointer`), pulsing - on the button itself rather
than an arrow beside it, and the button, never the bar it sits in: the first version pointed at
whole panels and landed between two buttons every time. Every frame it
resolves, in order: the button that selects the lesson's `guide_unit` while that unit is not
selected; then the command card square showing one of its `guide_abilities` (the Build menu,
then the tower inside it; nothing while an order is being aimed); then the control named by
`highlight_key`. The keys map to Controls in `match_hud.tscn`, so relaying the HUD out moves
the arrow with it. The dim around the target is opt-in (`dims_around_highlight`): on by default
it greyed out the whole screen, lane included.

**ARROWS IN THE WORLD** (`TutorialWorldArrows`), standing upright and pointing straight down:
one over the builder while a lesson wants it selected; one over every blueprint cell still open
when `arrows_on_blueprint` is set, but only while the lesson's tower is IN HAND - the squares
already say where, and arrows before the Build menu is even open only compete with the border
on the button; and one over every tower an upgrade task wants upgraded, gone the moment that
tower's upgrade STARTS. Every arrow bobs in step with every other, because the pool hands
arrows round as the set changes and arrows on their own phases read as the animation
restarting whenever the selection did. The mesh and its generator are
`3DArt/Effects/tutorial_arrow*`, the scene `Scenes/Effects/tutorial_hover_arrow.tscn`, and the
shader warm-up draws it in a tutorial so its material compiles before the first lesson.
`TutorialGuide` is the one answer both arrows share to "which unit, and is it selected".

**A SPOTLIGHT on the world**, dimming everything but a circle around one thing and following
it. The lesson names a SUBJECT (`MY_LANE`, `TARGET_LANE`, `MY_NEWEST_TOWER`, `LEADING_CREEP`)
rather than a position. A MOMENT uses it too, around the creep it is about.

**THE CAMERA GLIDES** wherever the tutorial moves it (`RTSCamera.glide_to`): a quick eased move
rather than a cut, so the player sees where they were taken, with panning locked until it
arrives. `CameraConfig.glide_seconds` is how quick.

**A PINNED CAMERA** (`pinned_camera`, `RTSCamera.pin`): the camera held on one point until the
task is done - no panning, no drag, no minimap jump; the wheel still zooms. For a task the
player cannot do right while looking elsewhere, which is the first send: its creeps appear in
somebody else's lane. Pins are by reason, so a moment pinning the camera over a lesson's pin
lets go of its own and hands the camera back.

**The DIM SQUARES** of section 6, in the held opening the strongest of all: the one lit button
on the card is the answer.

## 9. Changing it

**Re-ordering, cutting or adding a lesson is editing `tutorial_script.tres` and nothing else.**
The array in it IS the teaching order.

**Changing what a lesson SAYS, gives or allows is editing its own `.tres`.** Nothing reads the
wording. The lessons were first written by a small generator script rather than by hand, but
the files are ordinary hand-editable Godot and are now the authority.

**A new KIND of lesson** is a subclass of `TutorialStep` with one method - `is_complete` - plus a
reading on `TutorialDirector` if it needs one that is not already there. Prefer a number
`MatchStats` already keeps, or a reading of the world.

**A new thing to point at** is one more entry in the two parallel arrays on the
`TutorialPointer` instance in `match_hud.tscn`. They are checked against each other at boot.

**The opponents' strength** is their two profiles, their lives and the income share on the
script. None of it has been tuned against a real new player yet.

Boot once after any of it: `TutorialScript.validate()` refuses an empty list, a null lesson, a
lesson with no title, a path that does not resolve, an opponent with no loadable profile, and a
restricted lesson that allows nothing. **A typed array in a `.tres` is all or nothing** - one
entry that fails to load empties the whole list silently, which for `allowed_abilities` is a
lesson nobody can finish. That check is what turns it into a message.

## 10. What it does NOT do yet

- **It is untested with a real new player.** The pacing, the wording, the opponents' strength
  and how long each part takes are all first guesses
- **The opening's waves can leak.** Against the first four towers one creep of the second
  wave usually walks round them, and the bigger wave usually gets one or two through the
  two-row maze. It costs a life or two out of plenty, and arguably teaches what a leak is,
  but nothing in the lessons says so yet
- **Nothing in the held opening teaches the builder's own attack**, although the wave lesson
  allows it. `strategy.md` 2.1 says it matters early
- **It never shows the send ring beyond a duel.** The second opponent joining is the closest it
  comes
- **The first opponent falls quickly** once the player is set free on the lesson's income, and
  its strength has not been tuned against a real new player
- **It does not teach discs, creep abilities or tower abilities.** Deliberately, for now
- **It has no way back in.** A player who leaves half way starts again from the first lesson
- **Nothing is voiced or animated**, and the lessons do not react to what the player did
  wrong - a player who runs out of lives is offered a retry from the first lesson and nothing
  more

## 11. Testing it

`Scripts/Dev/TutorialProbe.gd`, run as `Scenes/Dev/tutorial_probe.tscn` headless, plays the
whole tutorial through the real order road, faster than real time: it builds on the blueprint,
sends, upgrades, researches and morphs a Core. Against the first opponent it sends for real,
notes when it would have fallen, and keeps it standing until every MOMENT has fired and been
dismissed, so each one's hold, pin and spotlight is checked. At the end it checks the match was
concluded - creeps cleared, nothing orderable, the result board up. `-- lose` runs the player
out of lives in the Rookie lesson instead and checks the defeat screen.
In the held lessons it also TRIES what they must refuse - a tower off the list, a cell off the
blueprint, an upgrade, another creep - and checks the gold did not move. It prints a line per
lesson with the clock, whether it is held, gold and income, and a PASS or FAIL per check.

It is scaffolding under `Scripts/Dev`, kept while the tutorial is still being iterated, and it
is written against the current lesson order: re-ordering the lessons means updating it.

Run WINDOWED with `-- shots` it also saves a screenshot to `user://tutorial_shots/` at each
moment an arrow is up, which is the only way to see where an arrow DRAWS - headless draws
nothing, and a correct target can still be drawn in the wrong place.

**Print which lesson was reached and what was checked, not whether there were errors.** A
tutorial that stalls on its third lesson and one that runs to the end look identical in a log
full of nothing. What proves the run is the lesson count at the end and the checks that fired.
