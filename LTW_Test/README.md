# Line Tower Wars (working title)

A standalone 3D remake of the Warcraft III custom map **Line Tower Wars**: a PvP tower
defence for 2–12 players where each player defends their own lane and spends gold to send
creeps into everyone else's.

Built with **Godot 4.7**, targeting PC (keyboard & mouse).

## Status

Pre-alpha. The current and only milestone is a **1v1 prototype**. Free-for-all with 3+
players is out of scope until that works.

**It is networked and playable.** A dedicated server hosts lobbies and relays the match; two
clients join, build, send creeps at each other, steal lives and finish with a placement. A
player who disconnects has their maze erased on the same turn on every machine, and the match
carries on without them; a divergence between two games is detected and ends the match for
both rather than for whichever one noticed.

**It plays by deterministic lockstep.** Every machine simulates the whole world from the same
seed and the same orders, so there is no state stream at all — the server forwards orders,
stamps who sent them, and compares world checksums so a disagreement is caught rather than
papered over. An order is booked a turn or two ahead and run by every peer on that turn, and
how far ahead is MEASURED from the live connection rather than authored, so the input delay
tracks the ping instead of being a constant everybody pays. See
[multiplayer.md](Docs/multiplayer.md) §11.4 for how that works, and
[Findings/2026-09-04-input-delay.md](Docs/Findings/2026-09-04-input-delay.md) for what it
measured on the day.

**A session can be logged to a file**, from a tick box in the lobby, off unless somebody asks
for it. It records the connection, the match, every stall and who it was waiting for, the
input delay as it adapts, and the turn stream itself — which is the replay format, so a
divergence reported by a tester is reproducible rather than a shrug. It lands in the game's
user folder; on Windows that is `%APPDATA%\Godot\app_userdata\LTW_Test\logs\`.

**It exports to a Windows build**, which is how a tester who is not on the dev machines plays
it: one release preset, and a handed-out build reaches the rented server without being told
where it is. Nothing about a build is committed - an export is reproducible from the commit it
was made at, and the server is deployed from that same commit so the two cannot disagree.
[Docs/building.md](Docs/building.md) is the procedure.

**A player is asked what to call themselves** the first time they open multiplayer, and
cannot go online until they have chosen — the prompt is modal and, on a first run, has no
way past it. It suggests the machine's login name without accepting it as the answer, refuses
punctuation and symbols while taking any language's letters, and is changed later from a
button in the multiplayer panel showing the current name. It is kept in `user://settings.cfg`
with the video and audio choices, because it is typed at runtime by whoever is sitting there.

**Everybody picks a colour in the lobby**, from a dropdown of coloured squares on their own
row, and it travels with them into the match. It is per-match identity rather than a lane number — the server
keeps it unique, leaving frees one rather than shuffling everybody else's, and a player who
gets moved when the lanes are dealt keeps the colour they chose. Nobody sits colourless: the
first player in is red, the second blue, down the source game's own palette.

**The host sets up the match in the lobby**, and everybody in the room watches the rules
change as they do it. What each player starts with, which creeps are in the game at all,
whether the lanes are shuffled, and whether players are named or only coloured. A RANKED
match is played on the standard rules and locks the lot, so two results are comparable. The
one thing a ranked host still chooses is how the opening technology is dealt: spend the free
research yourself, take one Ultimate rolled for everybody, or DRAFT — three Ultimates rolled
for the whole match, the same three offered to every player, with the world held still until
they have all chosen.

**The Basic tower roster is real.** All three lines, both branches of each, every tier — the
numbers are copied from Warcraft III Line Tower Wars 12.4a as [unit_data.md](Docs/unit_data.md)
records them. The builder places only the cheapest tower of a line and everything above it is
reached by upgrading, so the build menu stays four buttons deep whatever the roster does.
Towers are placeholder primitives, but to a deliberate visual system: shape says which line,
one silhouette change says which branch, and a six step metal ramp says which tier. The
elemental roster answers the same three questions with colour instead — an element owns a
hue, a path owns a silhouette, and the tier is read off the element's own material rather
than off a metal, because metal was the loudest thing on all thirty of those towers and made
them read as one silhouette with the top swapped. Only their 200g and 800g towers wear any,
and there a ring is the whole of what separates a pair that is otherwise one shape at two
sizes. Both systems are written down under Presentation in [game_rules.md](Docs/game_rules.md),
and they are what a 3D artist should be handed with the models.

**The whole creep roster is real** — all four tiers at the source game's own numbers, plus the
Timber Wolf that only ever arrives inside a Sheep pack and the Ghoul that only ever crawls out
of a dead Obsidian Statue. They unlock one at a time on the match clock, cost population that
is now enforced, and come in three kinds: ordinary creeps that walk the maze, flyers that
ignore it entirely, and attackers that go after the towers and are the only creeps their owner
can command. A Boss steals more than one life; how many is per creep, in the roster.

**Building that roster is where most of the game's machinery came from**, because a creep is
where the rules get interesting. Creeps carry MANA, banked from being hit or regenerated on a
clock, and spend it on a trait. One SHOOTS, lobbing at a tower on a clock beside its own. One
converts nine tenths of itself into a damage-absorbing SHIELD. Some SPAWN other creeps. Some
reach back the other way and leave effects on a TOWER - a curse on its attack speed, an aura
weakening its damage, a drain that takes its mana and keeps five times what it took. One walks
straight THROUGH the maze, one DODGES anything shooting from far enough away, one braces
against whichever damage type has hurt it most and can move that brace every few seconds. And
one carries the roster's only ACTIVE ability: the Phoenix is aimed by its owner, dives out
along that line and back burning what it passes over, and Stop calls the dive off. Armour is
not always a constant either - Hardened Skin starts absurdly high and wears off as the creep
is hit, down to a floor it never falls below.

**SUDDEN DEATH is the one place a tier means anything.** At a fixed point on the match clock
the whole of tier 4 unlocks at once, with no per-creep start delay, and tiers 1 to 3 stop being
sendable for the rest of the match — the only time a creep is ever taken away from a player.
Anybody under an income floor is raised to it, once, so a player who has been losing slowly can
still afford the tier that ends the match; and tier 4 sends stop paying properly above an
income cap, so Sudden Death does not compound.

**A creep sender has no body.** It stands nowhere on the map: no model, no footprint, nothing
to click, nothing on the minimap and nowhere for the camera to fly to. There is one per creep
tier, and each is reached through a row of squares over the unit panel that selects it and puts
its creeps on the panel. A sender is still an ordinary unit underneath — an order names a unit
over the wire and the server checks its card — so it can also be put in a control group, which
is how it is reached by keyboard.

**The creeps have a visual system of their own**, on the same three axes and answering them
differently. What a creep does to the maze is its FAMILY and is the firmest of them — a flyer has no
legs and hangs over a shadow disc pinned to the ground, and an attacker is the only creep whose
weapon is lit. Its body plan and hide colour say WHICH creep, and a ladder on its gold cost says
how dangerous it is: its eyes brighten, its claws and plates ramp from bone to blackened
steel, and it gains shoulder plates, then a row of spines, then a crest of horns. SIZE is the
one rung of that ladder that is capped: the whole roster lives inside a narrow band whose
ceiling belongs to a top tier Boss, because a tier carries no mechanical meaning and a field
of creeps two and three times each other's size is chaotic to read.
Every creep walks, and the walk is measured in distance travelled rather than played on a clock,
so a chilled creep takes fewer steps and a stunned one stands still. A killed creep pops the
gold it paid in the air over where it died. All of it is under Presentation in
[game_rules.md](Docs/game_rules.md) alongside the tower rules.

**The technology system is built, and so is everything it gates.** A Research Center screen
sells the ten elements and the two tower paths each of them owns, at the source game's own
prices, with the four-technology cross requirement every Ultimate carries, a roll for a random
Ultimate and a few seconds in which a press can be taken back.

**The elemental roster is real.** All ten elements, both paths of each, every tier — and
the named ability every one of them carries, at the source game's own numbers.
The builder places a fourth tower, the 200g **Elemental Core**, which morphs free into whichever
element its owner has researched; each path is then gated on that path's own technology, and the
gate is the same call the Research Center makes rather than a second copy of the rule. Any
elemental tower worth 800 gold or more can also go back the way it came, returning to a bare
Core on the same cell and refunding everything above the Core's own price. A handful of pieces
of those abilities are approximated or left out; [game_rules.md](Docs/game_rules.md) lists each
one rather than leaving them to be found.

**The technology DISCS are real too, and they are not towers.** All thirty-one of them: a
2,500g base disc that is unlocked from the first second of a match and does absolutely nothing,
morphing free into any element its owner has researched and then twice more into an Advanced
and an Ultimate. **Creeps walk straight over a disc.** It claims its square against anything
else being built there and blocks nothing at all, so a disc goes in the holes a maze already
has rather than making new ones — which is what makes the shape of a maze and what is standing
in it two decisions instead of one. It cannot attack and cannot be attacked either, so an
attacker creep can do nothing with the square at all. All ten effects are built, and most of
them are the first thing in the game to reach a TOWER with anything good: attack speed, reach,
armour, repair rate, mana, damage scaled by how varied the maze around it is, a chill and an
armour bite added to what nearby towers already do, and the Lightning disc's static, which
heals a tower off its own damage and throws an attacker's damage back at it. The other two fire
on the creeps standing on the disc, which is the walkable rule paying for itself. A disc has no
model: it is drawn as three flat layers — the same square foundation a tower claims its square
with, a round worked plate set into it that says the building is a disc, and a coloured circle
in the middle whose colour is the element and whose size is the tier. Round on square is the
whole trick, and an upgrade grows only the circle. Two of the three disc tiers ask for technology as a COUNT rather than a named one —
two of an element's three, then all three — which is the only place in the game that does.

Making that work meant building four things the game did not have: **status effects** on creeps
— chill, stun, paralyze, permanent armour erosion, burning, poison, amplification — **mana** on
towers, **multishot**, and **ground effects**: a patch an attack leaves behind that keeps
damaging whatever stands in it, which unlike a status effect stays where it landed and catches
what walks in afterwards. Spell Damage now has something that deals it.

**Every one of those status effects is now readable.** Selecting a single unit draws a row of
debuff squares along the bottom of its panel, each picturing the tower ability that applied it,
counting its stacks in the corner and closing over as it runs out; hovering one says what it is,
what it is doing with its own numbers, how long is left and how far its stacks have climbed. A
client is told about them for the unit it is looking at, and about no others — see
[multiplayer.md](Docs/multiplayer.md) §5.4.

**That roster is being reviewed one element at a time**, and the review changes rules all ten
share, so each change is opted into per element rather than applied to all of them at once.
`Tools/ModelGen/style.py` is the authority on which elements are in. Reviewing an element is
where most of the combat machinery has come from: called-down meteors and burning ground; the
one shot in the game that does not home, but flies straight, pierces everything in its path
and expires on a distance of its own; particle impacts and an arc drawn from the tower to
every creep a hit reached, including the ones an ability chained to; towers that convert their
neighbours into copies of themselves; the first tower carrying two named abilities on two
squares; and auras that build up on a creep in steps and drain off again once it leaves,
rather than snapping to full strength the moment it is in range.

**Orders CHAIN, the way they do in any RTS.** Holding shift queues an order behind whatever a
unit is already doing instead of replacing it, and the three that can be chained are the three
that take time: Move, Attack and Build. Each knows for itself when its task is over — a walk
arrives, a tower is STARTED, a named creep dies — and the next one begins. Giving one of those
three without shift wipes the chain; pressing anything else on the card leaves it alone. Shift also
keeps the ability armed for exactly as long as the key is held, so a row of towers is one press
of the button and one click per tower; letting go releases the ability while the chain carries
on, which is what stops the next click placing a tower nobody asked for. What is queued is drawn
on the ground: a waypoint for every walk still to come, and a
grey ghost of every tower ordered and not yet started — which also holds that ground, so the
next placement cannot be aimed on top of it. A tower is paid for when the builder reaches it,
never when the button was pressed, so a chain may be longer than the gold in hand and one that
still cannot be paid for is dropped there.

**The attack order became an attack-MOVE** in the same pass, which is what makes chaining it
worth anything. Aimed at a unit, anything that can walk closes the distance and kills it; aimed
at the ground it walks there and fights what it meets, standing to fight and then carrying on.
A tower cannot walk, so for a tower it is the plain "shoot that one" order it always had — but
the order is now HELD until the target dies rather than thrown away when it is out of reach,
which is what lets a player line up which creep a tower hits next. **The builder can fight**,
badly and slowly, with a hammer it swings on the attack's own windup.

**The map is a fixed 6 x 2 grid of twelve lane slots**, whoever turned up. A 1v1 fills two of
them and the other ten are black ground, which the camera and the minimap both still cover.

**The content is complete.** Every tower, every creep, every disc and every technology of the
source game is in, at its own numbers. What is left is not roster work.

What is deliberately not built yet, in rough order of size: **bandwidth optimisation** (the
server sends the whole world every tick, which is fine for a 1v1 on a LAN and nowhere near
twelve players), **client-side prediction**, **anything past a 1v1**, an **end screen**, and
**sound** — there is no `Audio/` folder yet and not one audio file in the project.

Two small rules of the source game are also uncopied, and both are written down where they
belong rather than here: Sudden Death making creeps tankier by the minute
([unit_data.md](Docs/unit_data.md) §1.7), and a technology tower refunding less than a Basic
one when sold ([game_rules.md](Docs/game_rules.md)).

There is one piece of tooling worth doing: [unit_data.md](Docs/unit_data.md) §8.2, which
would generate that file's stat tables out of the resources instead of shadowing them by hand.
It was deferred for want of content, and there is now no shortage.

Nothing here is blocking. [multiplayer.md](Docs/multiplayer.md) §13 says what is not built on
the network side and why; [game_rules.md](Docs/game_rules.md) marks the rules that are decided
but have no code, and lists in one place the choices Claude made that nobody has reviewed.

**Not yet playtested.** Most of the roster has never been played against a person, so the
towers and creeps that were built last are the ones most likely to be wrong.

## Documentation

They live in [Docs/](Docs/); only this file and `CLAUDE.md` stay in the root, because a git
host looks for the first by name and Claude Code loads the second. Read them in this order.
Each one is the authority on its own subject, and where two disagree the more specific wins.

| File | Contents |
| --- | --- |
| [game_rules.md](Docs/game_rules.md) | **The RULES**: how the game works — economy, mazing, sending, damage resolution, lives, win condition. Says which of them are built. Holds no numbers; points at unit_data.md for every one. |
| [unit_data.md](Docs/unit_data.md) | **The NUMBERS**: every tower, creep, disc and technology of Warcraft III Line Tower Wars 12.4a, whose balance the prototype copies. Costs, stats, upgrade paths, tech requirements, and what is still unknown. Reconstructed from `ReferenceFilesFromOtherProjects/LineTowerWarsData/`. |
| [content.md](Docs/content.md) | **The PROCEDURE**: how a tower, creep, disc or ability is added or changed — which files it is made of, which of them ModelGen generates and must not be hand-edited, how an id is picked, and what refuses bad content at boot. |
| [CLAUDE.md](CLAUDE.md) | Code conventions, naming, the resource/reference architecture, and the engine gotchas that have already cost a debugging session. |
| [multiplayer.md](Docs/multiplayer.md) | What the networked build is, where each part of it lives, and the decisions (D1–D29) behind it. The long one. |
| [server.md](Docs/server.md) | How to start, stop and aim the dedicated server. Controls only. |
| [Docs/](Docs/) | The index for all of the above — which file answers what, and where a new document goes. |
| [Docs/Findings/](Docs/Findings/) | Investigations: something measured, chased down or ruled out, written up and dated. |

## Running it

**Single player**, for iterating on gameplay: open `Scenes/Main.tscn` and press F6. It
stands in a one-player match and needs no server.

**A networked match** needs a server and two clients:

```powershell
.\Tools\run_server.ps1        # a dedicated server on localhost, headless
```

then run two client instances from the editor (Debug → Customize Run Instances…, count 2,
no feature tags) and press **Multiplayer** in each. Full detail, including what the log
should say, is in [server.md](Docs/server.md).

**Developer cheats** shortcut the parts of a match you are not testing — gold, every creep
unlocked at once, every technology granted, and a whole maze saved and rebuilt. They are on
the numpad, and `Scripts/Input/CheatController.gd` is the list and the authority on which
key is which.

The **layout pair** is the one worth explaining. One key writes the maze standing in your
area out to a file as building types and grid cells; the other builds that file back, free
and finished, so a maze worth testing against is one press away instead of five minutes of
clicking. `TowerLayout` is the file format and `GameConfig.cheat_layout_path` is where it
goes — `user://` by default, and every save logs the folder. Loading is non-destructive and
per entry: anything already standing keeps its cell, so a second press adds nothing and a
press over a half-built maze fills in the rest. Nothing about placement is waived — the area
refuses a taken cell or one under rubble exactly as it refuses a build order — only the
price, the build timer and the walk.

**The LOAD half was reported not working on 2026-09-03 and has not been investigated.** Saving
is believed fine. Treat this paragraph as what it is meant to do rather than as a report that
it does.

The file is ordinary hand-editable Godot, and the format is deliberately the smallest honest
one: a type id and a cell per entry, area-local, so a layout saved in one player's area
loads into anybody's. That is also the shape a player-facing maze template would want, if
saved layouts ever stop being a testing tool.

Each one is a PLAYER ORDER like any other: it goes through `Commands.submit_player_action`,
so the authority grants it rather than a client redrawing a number the server never agreed
to. Which is exactly why they are a **single player tool by default**. Two flags in
`game_config.tres` decide, and `GameConfig.cheats_allowed()` is the one place they are put
together:

| Flag | What it does |
| --- | --- |
| `cheats_enabled` | The master switch. Off and nothing responds at all. |
| `cheats_in_multiplayer` | Whether the master switch still counts once the match is networked. **Off**, so a real match refuses every cheat. |

The check that matters is the **server's**, in `CommandService._cheat_target`, so a client
built with cheats on gets a rejection line rather than gold. Turn the second flag on
deliberately, on the server, when a headless two-client run needs the same shortcuts a single
player run gets — and turn it off again. `multiplayer.md` has the reasoning.

**A load test**, for the question of what a full match costs to run:

```powershell
.\Tools\run_bench.ps1                 # the whole matrix, headless
.\Tools\run_bench.ps1 -Quick          # the same, with short measurement windows
.\Tools\run_bench.ps1 -Only ten       # only the scenarios whose name matches
```

It fills every player's maze with towers, holds every lane at its population cap and
reports what one simulation tick costs against the budget a tick has to fit in. Then it
times the individual scans on their own, so a tick that is too long says WHICH loop spent
it rather than only that something did. `Scripts/Tools/PerfBench.gd` is the harness,
`Scripts/Tools/PerfProbes.gd` is the list of loops it blames, and the scenarios live in
the driver. Reports land in `Reports/` as JSON, one per scenario, so a run before a change
can be held up against the run after it.

The `client` scenarios also report what DRAWING costs, separately from what simulating
costs, and carry two diagnostics for asking why: `shadows=off` and `shadow_distance=<n>`.
Both are set on the running scene and touch no file.

## Layout

```
Docs/       every reference document, and Docs/Findings for written-up investigations
Resources/  resources (.tres) — config, unit stats, abilities
Scenes/     scenes (.tscn)
Scripts/    GDScript
Tools/      build-time tooling that runs OUTSIDE Godot, not part of the game,
            plus the control scripts: run_server, stop_server, run_bench
addons/     godotsteam (GDExtension), log, godot_ai, reload_current_scene
ReferenceFilesFromOtherProjects/   read-only reference material, not part of the build
```

`3DArt/` and `Audio/` are where meshes and sound go. They do not exist yet: nobody has drawn
anything for this project, and every unit in the game is primitive shapes. `2DArt/Icons/` is
the one exception and is not really one — it holds a generated icon per unit type, each a
render of that unit's own primitives, so the command card is not a grid of blank squares.
They are placeholders and the folder says so.

`2DArt/UI/Icons/` is the other picture folder and answers a different question. A unit icon is
a picture of a unit; these are the HUD's own glyphs — the `stat_*` set in the status bar, and
the `ability_*` set for the command card buttons that are not about a unit at all: Move, Stop,
Attack, Sell, Build, Cancel. All of them are flat white silhouettes, because `CommandSlot`
tints the whole texture to say toggled-on.

`Scripts/Tools/` and `Scenes/Tools/` are the tooling that has to run INSIDE Godot, which is
why it is not in `Tools/` with the rest. So far that is one thing:
`Scenes/Tools/icon_gen_3d.tscn`, which bakes a unit's icon by rendering its own model, and so
cannot go headless. It scans the stats folder rather than carrying a roster of its own, so a
creep added tomorrow is baked without anybody editing it — `-- new` bakes only what has no
picture yet. It is kept rather than deleted, unlike `Scripts/Dev`, because every new roster
needs it again.

`Tools/` is build-time tooling that never runs inside the engine, and is not part of the
game; a `.gdignore` keeps Godot out of it. [Tools/ModelGen](Tools/ModelGen/README.md) generates the tower, creep and disc art, the materials
they share and the content that points at them — run it from the project root with
`python Tools/ModelGen/generate.py`. It writes creep PREFABS but not creep stats, which were
authored by hand and stay the authority. [Tools/IconGen](Tools/IconGen/README.md) draws the
`ability_*` action icons the same way, from `python Tools/IconGen/generate.py`. Both tools'
output is checked in and is ordinary hand-editable Godot, so they are a convenience rather
than a dependency.

**Before building placeholder visuals for another roster** read
[PLACEHOLDER_ART.md](Tools/ModelGen/PLACEHOLDER_ART.md). It is the method every roster so far
was built to: what the three readability axes are, how each roster answered them, the
contracts a model must meet, and every trap already paid for.

**None of the visual rules is binding.** They were authored by Claude rather than handed
down — only placeholder visuals were ever asked for — and they exist so a roster added later
still looks like it came from the same game as the ones before it. Change one when it is
wrong; change it in `style.py` and re-generate, so the whole roster moves together rather
than one unit disagreeing with the rest. Section 0 of that file is the long version.

Boot scene is `Scenes/Boot/boot.tscn`. It decides whether this process is a client or a
dedicated server and then gets out of the way — see multiplayer.md §2.

The in-match overlay is one scene, `Scenes/UI/match_hud.tscn`, instanced into `Main.tscn`
as `MatchHUD`. Open it to see the whole HUD composition in one place: nothing draws over
a match that is not a child of it. The row of four squares above the unit panel is
`Scenes/UI/send_bar.tscn`, and it is the only way to reach a creep sender with the mouse —
the senders have no bodies. It binds on the physics tick rather than on a render frame,
because the tick is the beat the world appears on and a headless run barely has render
frames at all. The minimap is one of its children and is the only piece
that reads the world back rather than being told about it — `Scripts/UI/Minimap.gd` walks
`MatchSession`'s live units and frames `GameConfig.map_bounds()`, the same rectangle the
camera pans over.

The options screen is `Scenes/UI/Menus/options_menu.tscn`, and it is a child of the game
menu rather than a screen of its own — so Escape peels one layer at a time and only
`GameMenu` ever has to decide which layer is on top. What it changes lives on
`Scripts/Config/UserSettings.gd`, the one place in the project where a setting is not a
`.tres`: these are written at runtime by whoever is at the machine, so they go to
`user://settings.cfg` instead. Video, Gameplay and Hotkeys do something today; Audio is
remembered and waits for there to be a sound to apply it to. The player's multiplayer NAME
lives in that file too, though it is not set from this screen — the lobby browser asks for
it. It is there for the same reason the rest is: typed at runtime, on this machine, by
whoever is sitting at it.

Hotkeys is the one page with a second file behind it. The command card is a grid and an
ability's key is read off the square it sits on, so there is nothing per-ability to
rebind — what the page offers instead is the short authored list of commands that answer
to a key of their OWN, one `HotkeyAction` .tres each, listed on `ControlsConfig`. An
ability names one in its `hotkey_action` and several may name the same one, which is how
the Cancels are one line and one key rather than three. `ControlsConfig` is also what
refuses a key: the grid's own letters, in either keyboard layout, plus the keys the game
answers wherever you are.

The autoloads, in this order: `Net`, `MatchStart`, `Lobby`, `Commands`, `Replication`.
They are autoloads rather than scene nodes because Godot routes an `@rpc` by node path, and
a client and a server do not share one.

## Addons

- **[godotsteam](https://codeberg.org/godotsteam/godotsteam)** — GDExtension. Loads on its
  own; it is deliberately *not* in `[editor_plugins]`. Currently inert: `project.godot` has
  `steam/initialization/app_id=0` and `initialize_on_startup=false`, and no game code calls
  it. Steam is distribution and identity, never transport — multiplayer.md §10.
- **Log** — the debugging logger. Use it instead of `print`.

## License

Not chosen yet.
