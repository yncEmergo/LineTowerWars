# The tutorial

**What this file is for:** how the teaching match is built, so that changing what it teaches
is editing content rather than reading code. It carries no lesson WORDING - that is in fifteen
ordinary `.tres` files under `Resources/Tutorial/Lessons/` and is meant to be argued with -
and no rules of the game, which are `game_rules.md`'s.

---

## 1. The tutorial is a real match

Same world, same economy, same towers, same opponent machinery, same send ring. There is no
second game underneath it and there must never be one: a separate scene would be a second
thing to keep working, and a tutorial that teaches something the game does not do is worse
than no tutorial.

What differs is only what a lesson has to control, and all of it is in `TutorialSetup`:

- **no income and no starting gold.** A lesson hands over exactly what it is about to talk
  about, so the player's first tower is bought with the first lesson's gold rather than out of
  a pile they were given for no reason. The economy lesson turns income on, and that is the
  first moment it starts behaving like a real match
- **no opening phase.** Nothing can be sent at the player until a lesson says so, so twenty
  seconds of the clock standing still would be twenty seconds of nothing
- **a SPARRING PARTNER in the other lane** rather than an opponent: `ai_tutorial.tres`, which
  builds a short maze so there is something for the player's creeps to walk through and never
  sends anything back. See `singleplayer.md`
- **technology is PICK** and the lanes are not shuffled, because the send-ring lesson needs a
  fixed example and the technology lesson needs the player to spend the allowance themselves

Everything else is the defaults, deliberately: what is being taught is the game, so a player
who finishes the tutorial and opens a lobby should recognise every number they saw.

`MatchSetup.mode == TUTORIAL` is the whole gate. `TutorialDirector` lives in the ordinary match
scene and costs a multiplayer match and a skirmish one comparison.

## 2. The pieces

| File | What it is |
| --- | --- |
| `Scripts/Game/Tutorial/TutorialStep.gd` | ONE LESSON, abstract. What it says, what it gives, what it points at. |
| `Scripts/Game/Tutorial/Steps/*.gd` | What FINISHES a lesson. One subclass per kind. |
| `Scripts/Game/Tutorial/TutorialScript.gd` | The lessons in teaching order. |
| `Scripts/Game/Tutorial/TutorialDirector.gd` | Which lesson is open, what it handed over, what has happened since. |
| `Scripts/Game/Tutorial/TutorialSetup.gd` | The match it is played in. |
| `Scripts/UI/TutorialPanel.gd` | The lesson on screen, and the way on. |
| `Scripts/UI/TutorialPointer.gd` | The arrow at a named HUD control, and the dim around it. |
| `Scripts/UI/TutorialSpotlight.gd` | The dim around one thing in the WORLD. |
| `Resources/Tutorial/` | The lessons, the script, and the two mazes they draw. |

## 3. A lesson is a resource, and it owns three things

The same shape everything else in this project that carries behaviour has: an attack's
delivery is a resource, a tower's passive is a resource, a lesson is a resource. What makes a
lesson a BUILD one rather than a SEND one is which subclass it is, so nothing anywhere
switches on a kind.

**WHAT IT SAYS** - a title, a paragraph, and one line in the imperative saying what to do now.

**WHAT IT GIVES** - gold, income, a blueprint to follow, the send card opened. A lesson hands
over exactly what it is about to talk about and nothing else.

**WHEN IT IS DONE** - `is_complete(director)`, asked every tick of the current lesson and of
nothing else. It reads the world and must not change it.

That last one is the important half. **Nothing in the builder, the sender or the Research
Center knows a tutorial exists.** A lesson is finished by the world reaching a state, not by
the system it is teaching reporting in - so adding a lesson about something new is a subclass
and a counter, never a hook in the thing being taught.

The counters come off `MatchStats`, which is already counting all of it for the end screen, so
a lesson asking "three towers since this lesson opened" is a subtraction against a mark the
director took when the lesson opened. `technologies_owned` is the one exception and counts in
TOTAL rather than since - research can be UNDONE inside its window, so counting presses would
let a player finish the lesson by buying something and giving it straight back.

## 4. Pausing, and the anti-softlock rule

A lesson that is READ holds the world still, through `MatchSession.hold(&"tutorial", ...)` -
the same mechanism a technology draft uses, with its own holder name so the two can overlap
without either releasing the other. So a player reading a paragraph is not being leaked on
while they read, and the whole HUD stops with the world; only the lesson panel and the menu
answer a click.

A lesson that is DONE never pauses, obviously - a frozen world would make it impossible.

**Every lesson can be skipped after a while, and that is not optional.** A step waits on the
world reaching a state, and a world can always be put in a state it cannot reach: a maze built
where the blueprint did not ask for it, gold spent on the wrong thing, a creep that walked
past. A tutorial that can be stuck is worse than one that can be skipped. `skip_after_seconds`
is per lesson and the button appears on its own rather than being offered at once, which would
read as an invitation.

**A skipped lesson has still handed over its gold and switched on whatever it switches on**,
because the lesson after it was written assuming the one before happened. Skipping is the same
call as finishing.

The lesson clock runs WHILE the world is held, and has to: a read lesson holds the world for
the whole time it is up, and the skip is measured in exactly that number.

## 5. Saying where, and saying which

Three ways, in order of how much they take the player's attention:

**A BLUEPRINT on the ground.** One blue square per cell still to build on, disappearing as
each is filled - which is exactly "these ones, in any order". It orders nothing and it is the
same overlay the builder's own Show Blueprint command drives, so a player who puts one up
themselves and a lesson that puts one up for them are using one thing.

A lesson names its blueprint by `res://` PATH rather than by one of the player's nine SLOTS,
and the difference matters: a slot is theirs, and somebody who saved their own maze into slot
one would be shown that maze by a lesson meaning to show them the shape it is teaching. See
`BlueprintOverlay.show_layout`.

**AN ARROW at a named HUD control**, with the rest of the screen dimmed behind a hole cut
around it. The lesson carries a KEY - `send_bar`, `research_center` - and the map from a key to
a Control is authored in `match_hud.tscn` next to the things it names. So relaying the HUD out
moves the arrow with it, and a lesson written six months ago goes on pointing at the right
thing. The arrow follows its target every frame, because a HUD control MOVES: the command card
is rebuilt when the selection changes and a panel laid out this frame has a different rect
next frame.

**A SPOTLIGHT on the world**, dimming everything but a circle around one thing, and FOLLOWING
it - the creep a lesson is about is walking while the lesson is being read. The lesson names a
SUBJECT (`MY_LANE`, `TARGET_LANE`, `MY_NEWEST_TOWER`, `LEADING_CREEP`) rather than a position,
because a lesson cannot know where anything is. The projection is camera maths in GDScript -
there is no physics and no ray in this project - and the shader only draws the hole.

## 5a. Sending something at the player

A lesson can put a wave into the player's OWN lane (`spawn_creep_path`,
`spawn_creep_count`), spawned as the opponent's creeps so the leak, the bounty and the life
steal all resolve exactly as they would in a real match.

**It had to exist, and working out why is worth the paragraph.** A creep that leaks walks on
to the next lane in ring order *skipping its own sender*, which in a two lane match resolves
back to the lane it just leaked. So nothing the player sends ever comes back at them; and the
sparring partner deliberately never sends, because an opponent that kills the student is not a
teacher. Without a wave the lesson about watching a maze work could only ever be SKIPPED -
a softlock wearing a timer, which is precisely the failure `skip_after_seconds` is there to
paper over rather than to hide.

It is deliberately not a SEND: a send is a player order with a price, a reserve and a start
delay, and none of those is what the tutorial is asking for. This is the board being set up,
the same as the opening gold.

**The sparring partner is funded the same way** (`TutorialScript.opponent_gold`). A tutorial
match starts everybody on nothing so a lesson can hand the player exactly what it is about to
talk about, and an opponent with no gold builds no maze - which leaves the player sending
creeps into an empty lane and learning nothing from it.

## 6. What the fifteen lessons cover

The lane and what a creep does. The builder. Building three towers on a blueprint. What a maze
is FOR - the one idea the whole game rests on. The simple left-right maze. Upgrading in place.
The three kinds of creep and the four tiers. The send ring and life stealing. Sending.
**Why income beats bounty**, which is the second idea the game rests on. Watching your own
maze work. Technology and what an Ultimate costs. Elemental towers. Discs, and why they go in
the holes. A closing page pointing at a single player match.

They are a FIRST PASS. The wording is in fifteen files and none of it is load-bearing.

## 7. Changing it

**Re-ordering, cutting or adding a lesson is editing `tutorial_script.tres` and nothing else.**
The array in it IS the teaching order.

**Changing what a lesson SAYS is editing its own `.tres`.** Nothing reads the wording.

**A new KIND of lesson** is a subclass of `TutorialStep` with one method - `is_complete` - plus
a counter on `TutorialDirector` if it needs one that is not already there. Prefer reading a
number `MatchStats` already keeps.

**A new thing to point at** is one more entry in the two parallel arrays on the
`TutorialPointer` instance in `match_hud.tscn`. They are checked against each other at boot.

Boot once after any of it: `TutorialScript.validate()` refuses an empty list, a null lesson, a
lesson with no title and a lesson naming a blueprint that does not resolve. **A typed array in
a `.tres` is all or nothing** - one entry that fails to load empties the whole list silently,
and the editor writes that emptiness back on the next save. That check is what turns it into a
message rather than a tutorial that opens on nothing.

## 8. What it does NOT do yet

- **A lesson can spawn ONE wave and nothing more.** There is no schedule, no pressure that
  builds, and nothing that answers what the player has built. A lesson that watched the maze
  hold and then sent something it could not is where this goes next
- **It does not check WHERE anything was built.** The build lessons count towers, not cells,
  so a player who ignores the blueprint still passes. That is deliberate for the first two -
  they teach what a button does - and wrong for the maze lesson, which is about a shape
- **It never explains the elemental roster or discs by having the player use them**, only in
  prose. Both lessons are read-only pages today
- **It has no way back in.** A player who leaves half way starts again from lesson one;
  nothing is remembered between runs
- **Nothing is voiced, highlighted in the world by a marker, or animated.** The spotlight is
  the only worldspace teaching tool
- **The FFA principle is explained but never shown.** It is a two player tutorial, so the ring
  is a sentence rather than a thing that happens. A three-lane tutorial where the player
  watches a creep leak onwards would teach it in one moment

## 9. Testing it

`Scripts/Dev/OpeningProbe.gd` drives it: it acknowledges every read lesson and skips anything
else once the lesson offers, so one headless run walks the whole script and prints which
lesson it reached. That is how the blueprint bug in §5 was found - a plan shown from a file was
wiped on its first refresh beat and drew for a quarter of a second, with nothing in the log to
say so.

**Print which lesson was reached, not whether there were errors.** A tutorial that stalls on
lesson three and one that runs to the end look identical in a log full of nothing.
