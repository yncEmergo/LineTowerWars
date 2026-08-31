# Line Tower Wars (working title)

A standalone 3D remake of the Warcraft III custom map **Line Tower Wars**: a PvP tower
defence for 2–12 players where each player defends their own lane and spends gold to send
creeps into everyone else's.

Built with **Godot 4.7**, targeting PC (keyboard & mouse).

## Status

Pre-alpha. The current and only milestone is a **1v1 prototype**. Free-for-all with 3+
players is out of scope until that works.

**It is networked and playable.** A dedicated server hosts lobbies and runs the match; two
clients join, build, send creeps at each other, steal lives and finish with a placement.
The server is the only machine that simulates — clients send orders and draw what comes
back, so two views cannot disagree.

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

**Tiers 1 and 2 of the creep roster are real.** All twenty-four of them, at the source game's
own numbers, plus the Timber Wolf that only ever arrives inside a Sheep pack. They unlock one
at a time on the match clock, cost population that is now enforced, and come in three kinds:
ordinary creeps that walk the maze, flyers that ignore it entirely, and attackers that go after
the towers and are the only creeps their owner can command. A Boss steals two lives.

**Tier 2 brought three things the roster had never needed.** A creep with MANA, which banks a
point per hit taken and spends the lot on a heal — mana had been a tower-only thing until then.
A creep that SHOOTS, lobbing at a random tower nearby on a clock of its own, which is a second
attack running alongside its own and the only ranged thing any creep has. And the other two
halves of a SPELL RESISTANCE — a share off every harmful effect's clock and a share off a
chill's bite — which had been written down since before anything in the game applied either.

**One tier 3 creep is real too, the Ancient Wendigo**, built out of order because a tier 1
creep dies to a single shot from anything above the cheapest towers - so there was nothing on
the field a real tower's damage, rate or on-hit effects could be measured against. It brought
the first armour that is not a constant: Hardened Skin starts it absurdly high and wears off
as the creep is hit, down to a floor it never falls below. It is sent from a **Tier 3 sender** of its own, since a
tier is exactly one command card and the source game gives each one a building. Tiers 3 and 4
are otherwise still only written down, in [unit_data.md](Docs/unit_data.md) section 6.

**The send buildings no longer exist as buildings.** They used to stand on a strip above the
creep spawn; that strip and its models are gone. Each tier's sender is reached through a row of
four squares over the unit panel, which selects it and puts its creeps on the panel. A sender is
still an ordinary unit underneath — an order names a unit over the wire and the server checks
its card — it simply has no body, so nothing clicks one, boxes one, draws it on the minimap or
flies the camera to it. It can still be put in a control group, which is how it is reached by
keyboard.

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
Core on the same cell and refunding everything above the Core's own price. Six
pieces of six abilities are approximated or left out, and [game_rules.md](Docs/game_rules.md) lists
all six rather than leaving them to be found.

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
share — so each change is opted into per element rather than applied to all of them at once, and
`Tools/ModelGen/style.py` names which elements are in. Fire came first and is where the
called-down meteor, the burning ground and the worldspace mana bar came from; Ice brought the
one shot in the game that does not home, a spike that flies in a straight line, pierces
everything in its path and expires on a distance of its own rather than on arriving; and
Lightning brought particle impacts and an arc drawn from the tower to every creep a hit reached,
including the ones an ability chained to; and Void brought towers that convert other towers into
copies of themselves, and the first tower in the roster to carry two named abilities on two
squares; and Holy brought tower AURAS that build up on a creep in steps and drain off again
once it leaves, rather than snapping to full strength the moment it is in range.

**Orders CHAIN, the way they do in any RTS.** Holding shift queues an order behind whatever a
unit is already doing instead of replacing it, and the three that can be chained are the three
that take time: Move, Attack and Build. Each knows for itself when its task is over — a walk
arrives, a tower is STARTED, a named creep dies — and the next one begins. Giving one of those
three without shift wipes the chain; pressing anything else on the card leaves it alone. Shift
also keeps the ability armed, so a row of towers is one press of the button and one click per
tower. What is queued is drawn on the ground: a waypoint for every walk still to come, and a
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

What is deliberately not built yet: client-side prediction, bandwidth optimisation, an end
screen, player colours, technology discs, the rest of creep tiers 3 and 4, and anything past a
1v1.
See [multiplayer.md](Docs/multiplayer.md) §13 for what is not built and why, and
[game_rules.md](Docs/game_rules.md) for the rules that exist but are not implemented.

## Documentation

They live in [Docs/](Docs/); only this file and `CLAUDE.md` stay in the root, because a git
host looks for the first by name and Claude Code loads the second. Read them in this order.
Each one is the authority on its own subject, and where two disagree the more specific wins.

| File | Contents |
| --- | --- |
| [game_rules.md](Docs/game_rules.md) | **The RULES**: how the game works — economy, mazing, sending, damage resolution, lives, win condition. Says which of them are built. Holds no numbers; points at unit_data.md for every one. |
| [unit_data.md](Docs/unit_data.md) | **The NUMBERS**: every tower, creep, disc and technology of Warcraft III Line Tower Wars 12.4a, whose balance the prototype copies. Costs, stats, upgrade paths, tech requirements, and what is still unknown. Reconstructed from `ReferenceFilesFromOtherProjects/LineTowerWarsData/`. |
| [CLAUDE.md](CLAUDE.md) | Code conventions, naming, the resource/reference architecture, and the engine gotchas that have already cost a debugging session. |
| [multiplayer.md](Docs/multiplayer.md) | What the networked build is, where each part of it lives, and the decisions (D1–D26) behind it. The long one. |
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
game; a `.gdignore` keeps Godot out of it. [Tools/ModelGen](Tools/ModelGen/README.md) generates the tower and creep models, the materials
they share and the content that points at them — run it from the project root with
`python Tools/ModelGen/generate.py`. It writes creep PREFABS but not creep stats, which were
authored by hand and stay the authority. [Tools/IconGen](Tools/IconGen/README.md) draws the
`ability_*` action icons the same way, from `python Tools/IconGen/generate.py`. Both tools'
output is checked in and is ordinary hand-editable Godot, so they are a convenience rather
than a dependency.

**Before building placeholder visuals for another roster** read
[PLACEHOLDER_ART.md](Tools/ModelGen/PLACEHOLDER_ART.md). It is the method all three rosters
were built to: what the three readability axes are, how each roster answered them, the
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
remembered and waits for there to be a sound to apply it to.

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
