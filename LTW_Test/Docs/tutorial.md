# The tutorial

**What this file is for:** how the teaching match is built, so that changing what it teaches
is editing content rather than reading code. It carries no lesson WORDING - that is in ordinary
`.tres` files under `Resources/Tutorial/Lessons/` and is meant to be argued with - and no rules
of the game, which are `game_rules.md`'s.

**Status, 2026-09-18: first rework landed, more iterations to come.** The tutorial was rebuilt
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
   asks, and every lesson hands over exactly the gold for its task. They build the first rows of
   the maze on a blueprint, watch a wave die in it, and send their first creeps from a reserve
   set to exactly the number asked for. Nothing can go wrong and nothing is timed.
2. **THE FIRST OPPONENT.** The limits come off, the clock runs, the base income arrives, and the
   first opponent is WOKEN from sparring into a real profile. The lesson ends when it is beaten.
   This is where the basics - Basic towers, the maze, sending, income - are played rather than
   explained.
3. **THE SECOND OPPONENT.** It has been in the match from the start, building a maze on STANDBY
   outside the send ring, so part 2 was a plain duel. Beating the first brings it in, the
   Research Center opens, and its half teaches technology and elemental towers. Beating it ends
   the match, and the ordinary result board takes over.

## 3. The pieces

| File | What it is |
| --- | --- |
| `Scripts/Game/Tutorial/TutorialStep.gd` | ONE LESSON, abstract. What it says, gives, allows and points at. |
| `Scripts/Game/Tutorial/Steps/*.gd` | What FINISHES a lesson. One subclass per kind. |
| `Scripts/Game/Tutorial/TutorialScript.gd` | The lessons in teaching order, and the board: opponents' profiles, lives, what is always allowed. |
| `Scripts/Game/Tutorial/TutorialDirector.gd` | Which lesson is open, what it handed over, what has happened since. |
| `Scripts/Game/Tutorial/TutorialSetup.gd` | The match it is played in: lanes, names, settings. |
| `Scripts/Game/ActionLimits.gd` | What one player may do when that is less than the rules allow. |
| `Scripts/UI/TutorialPanel.gd` | The lesson on screen, its progress, and the way on. |
| `Scripts/UI/TutorialPointer.gd` | The arrow at a named HUD control, and the dim around it. |
| `Scripts/UI/TutorialSpotlight.gd` | The dim around one thing in the WORLD. |
| `Resources/Tutorial/` | The lessons, the script, and the mazes they draw. |
| `Resources/Config/Ai/ai_tutorial*.tres` | The sparring partner, and the two profiles the opponents wake into. |

## 4. A lesson is a resource, and it owns four things

The same shape everything else in this project that carries behaviour has. What makes a lesson
a BUILD one rather than a SEND one is which subclass it is, so nothing anywhere switches on a
kind.

**WHAT IT SAYS** - a title, a paragraph, and one line in the imperative saying what to do now.
**Short is the rule**: a lesson is read by somebody who wants to be playing. A lesson that can
count its task draws the count next to the objective, which is the cheapest telegraph there is.

**WHAT IT GIVES** - gold, income, a reserve of sends set to an exact number, a blueprint, a
wave in the player's lane, an opponent woken, the Research Center opened.

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

**The anti-softlock rule.** A lesson waits on the world reaching a state, and a world can
sometimes be put in a state it cannot reach. The held opening is built so that it cannot -
exact gold, exact cells, nothing else allowed - so the skip it offers after a while is a
safety net for a bug rather than a way out anybody should need. A lesson whose end is an
opponent BEATEN offers no skip at all (`skip_after_seconds = 0`): skipping it would wake the
next opponent with the last one still in the ring, and the match ends that lesson on its own
either way. **A skipped lesson has still handed over what it hands over**, because the lesson
after it was written assuming it happened.

## 6. Limits: only this, only here

`ActionLimits`, held on `PlayerState.limits`, is what makes "only the one thing the lesson asks
for" true rather than hoped for. It is null for every player in every other match, so an
ordinary match pays one lookup and nothing changes.

It is a WHITELIST: a restricted lesson names the abilities that work (`allowed_abilities`), the
script names the few every restricted lesson allows on top (`always_allowed` - moving and
stopping the builder, calling off an order), and anything that changes nothing in the world - a
submenu, a passive, a presentation toggle - is always allowed. Everything else on the card is
drawn dim. `build_on_blueprint_only` adds the blueprint's cells as the only place a tower may
start. The Research Center is locked until a lesson opens it and stays open after.

It is asked where intent becomes an order, and nowhere deeper: the command card dims the square
(`CommandSlot`), the controller will not arm or send it (`CommandController`), the order road
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

**STANDBY** (`PlayerState.standby`) is what lets the second opponent sit in the match through
the first half. The ring skips a standby player exactly as it skips an eliminated one, so
nothing is sent to them and nothing that leaks walks into their lane; a standby player cannot
send; and they still count as ALIVE, which is what keeps the match from ending the moment the
first opponent falls. It is offline only, like the limits: set by the tutorial, never
replicated.

**A wave of the lesson's own** (`spawn_creep_path`, `spawn_creep_count`) puts creeps into the
player's lane before any opponent sends, spawned as the first opponent's creeps so the leak and
the life steal resolve as in a real match. It must be a creep that pays NO bounty, or the kill
hands the player gold the next lesson did not count on. The lesson waiting on it finishes when
the lane is EMPTY rather than on a kill count: a creep that leaks walks straight back into the
same lane in a duel, so an empty lane always arrives.

## 8. Saying where, and saying which

**A BLUEPRINT on the ground.** One blue square per cell still to build on, disappearing as each
is filled - exactly "these ones, in any order". It is the same overlay the builder's Show
Blueprint command drives. A lesson names its blueprint by `res://` PATH rather than by one of
the player's slots, which are theirs. The camera is moved onto the first row still to build.
The mazes are the left-right maze of `strategy.md` 5.5 - from the very top, half a cell
between rows - and the early lessons' plans are its first rows, so they grow into it.

**AN ARROW at a named HUD control**, with the rest of the screen dimmed behind a hole cut around
it. The lesson carries a KEY and the map from a key to a Control is authored in
`match_hud.tscn`, so relaying the HUD out moves the arrow with it.

**A SPOTLIGHT on the world**, dimming everything but a circle around one thing and following
it. The lesson names a SUBJECT (`MY_LANE`, `TARGET_LANE`, `MY_NEWEST_TOWER`, `LEADING_CREEP`)
rather than a position.

**A SELECTION**: a lesson can put the builder on the command card when it opens, so the first
thing the player sees is the card the lesson is talking about.

**The DIM SQUARES** of section 6 are the fourth, and in the held opening the strongest: the one
lit button on the card is the answer.

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
- **The demonstration wave is over in moments.** A bounty-free creep weak enough for the first
  rows dies almost as soon as it reaches them, so "watch your maze work" is a glimpse rather
  than a walk. A tougher creep would need its bounty suppressed to keep the gold exact
- **Nothing in the held opening teaches the builder's own attack**, although the wave lesson
  allows it. `strategy.md` 2.1 says it matters early
- **It never shows a leak on purpose**, or the send ring beyond a duel. The second opponent
  joining is the closest it comes
- **It does not teach discs, creep abilities or tower abilities.** Deliberately, for now
- **It has no way back in.** A player who leaves half way starts again from the first lesson
- **Nothing is voiced or animated**, and the lessons do not react to what the player did
  wrong - a player losing to the first opponent is simply shown the defeat board

## 11. Testing it

`Scripts/Dev/TutorialProbe.gd`, run as `Scenes/Dev/tutorial_probe.tscn` headless, plays the
whole tutorial through the real order road, faster than real time: it builds on the blueprint,
sends, upgrades, researches and morphs a Core, and ends each opponent once it has seen it send.
In the held lessons it also TRIES what they must refuse - a tower off the list, a cell off the
blueprint, an upgrade, another creep - and checks the gold did not move. It prints a line per
lesson with the clock, whether it is held, gold and income, and a PASS or FAIL per check.

It is scaffolding under `Scripts/Dev`, kept while the tutorial is still being iterated, and it
is written against the current lesson order: re-ordering the lessons means updating it.

**Print which lesson was reached and what was checked, not whether there were errors.** A
tutorial that stalls on its third lesson and one that runs to the end look identical in a log
full of nothing. What proves the run is the lesson count at the end and the checks that fired.
