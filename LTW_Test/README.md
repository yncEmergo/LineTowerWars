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
numbers are copied from Warcraft III Line Tower Wars 12.4a as [unit_data.md](unit_data.md)
records them. The builder places only the cheapest tower of a line and everything above it is
reached by upgrading, so the build menu stays four buttons deep whatever the roster does.
Towers are placeholder primitives, but to a deliberate visual system: shape says which line,
one silhouette change says which branch, and a six step metal ramp says which tier. The
elemental roster answers the same three questions with colour instead — an element owns a
hue, a path owns a silhouette, and the tier ladder is the same shape on its own five prices.
Both systems are written down under Presentation in [game_rules.md](game_rules.md), and they
are what a 3D artist should be handed with the models.

**Tier 1 of the creep roster is real.** All twelve of it, at the source game's own numbers,
plus the Timber Wolf that only ever arrives inside a Sheep pack. They unlock one at a time on
the match clock, cost population that is now enforced, and come in three kinds: ordinary creeps
that walk the maze, a flyer that ignores it entirely, and an attacker that goes after the towers
and is the one creep its owner can command. The Boss steals two lives. Creeps are white spheres
and are waiting on the same artist the towers are. Tiers 2 to 4 are still only written down, in
[unit_data.md](unit_data.md) section 6.

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
pieces of six abilities are approximated or left out, and [game_rules.md](game_rules.md) lists
all six rather than leaving them to be found.

Making that work meant building three things the game did not have: **status effects** on creeps
— chill, stun, paralyze, permanent armour erosion, burning, poison, amplification — **mana** on
towers, and **multishot**. Spell Damage now has something that deals it.

**The map is a fixed 6 x 2 grid of twelve lane slots**, whoever turned up. A 1v1 fills two of
them and the other ten are black ground, which the camera and the minimap both still cover.

What is deliberately not built yet: client-side prediction, bandwidth optimisation, an end
screen, player colours, technology discs, creep tiers 2 to 4, and anything past a 1v1.
See [multiplayer.md](multiplayer.md) §13 for what is not built and why, and
[game_rules.md](game_rules.md) for the rules that exist but are not implemented.

## Documentation

Read them in this order. Each one is the authority on its own subject, and where two
disagree the more specific wins.

| File | Contents |
| --- | --- |
| [game_rules.md](game_rules.md) | **The RULES**: how the game works — economy, mazing, sending, damage resolution, lives, win condition. Says which of them are built. Holds no numbers; points at unit_data.md for every one. |
| [unit_data.md](unit_data.md) | **The NUMBERS**: every tower, creep, disc and technology of Warcraft III Line Tower Wars 12.4a, whose balance the prototype copies. Costs, stats, upgrade paths, tech requirements, and what is still unknown. Reconstructed from `ReferenceFilesFromOtherProjects/LineTowerWarsData/`. |
| [CLAUDE.md](CLAUDE.md) | Code conventions, naming, the resource/reference architecture, and the engine gotchas that have already cost a debugging session. |
| [multiplayer.md](multiplayer.md) | What the networked build is, where each part of it lives, and the decisions (D1–D26) behind it. The long one. |
| [server.md](server.md) | How to start, stop and aim the dedicated server. Controls only. |

## Running it

**Single player**, for iterating on gameplay: open `Scenes/Main.tscn` and press F6. It
stands in a one-player match and needs no server.

**A networked match** needs a server and two clients:

```powershell
.\run_server.ps1        # a dedicated server on localhost, headless
```

then run two client instances from the editor (Debug → Customize Run Instances…, count 2,
no feature tags) and press **Multiplayer** in each. Full detail, including what the log
should say, is in [server.md](server.md).

## Layout

```
Resources/  resources (.tres) — config, unit stats, abilities
Scenes/     scenes (.tscn)
Scripts/    GDScript
Tools/      build-time tooling, not part of the game
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
tints the whole texture to say greyed-out or toggled-on.

`Tools/` is build-time tooling and is not part of the game; a `.gdignore` keeps Godot out of
it. [Tools/ModelGen](Tools/ModelGen/README.md) generates the tower models, the materials they
share and the content that points at them — run it from the project root with
`python Tools/ModelGen/generate.py`. [Tools/IconGen](Tools/IconGen/README.md) draws the
`ability_*` action icons the same way, from `python Tools/IconGen/generate.py`. Both tools'
output is checked in and is ordinary hand-editable Godot, so they are a convenience rather
than a dependency.

**Before building placeholder visuals for another roster** — the elemental towers, the
creeps — read [PLACEHOLDER_ART.md](Tools/ModelGen/PLACEHOLDER_ART.md). It is the method the
tower roster was built to: what the three readability axes are, why colour is reserved for
the ten elements, the contracts a model must meet, and the traps already paid for.

Boot scene is `Scenes/Boot/boot.tscn`. It decides whether this process is a client or a
dedicated server and then gets out of the way — see multiplayer.md §2.

The in-match overlay is one scene, `Scenes/UI/match_hud.tscn`, instanced into `Main.tscn`
as `MatchHUD`. Open it to see the whole HUD composition in one place: nothing draws over
a match that is not a child of it. The minimap is one of its children and is the only piece
that reads the world back rather than being told about it — `Scripts/UI/Minimap.gd` walks
`MatchSession`'s live units and frames `GameConfig.map_bounds()`, the same rectangle the
camera pans over.

The options screen is `Scenes/UI/Menus/options_menu.tscn`, and it is a child of the game
menu rather than a screen of its own — so Escape peels one layer at a time and only
`GameMenu` ever has to decide which layer is on top. What it changes lives on
`Scripts/Config/UserSettings.gd`, the one place in the project where a setting is not a
`.tres`: these are written at runtime by whoever is at the machine, so they go to
`user://settings.cfg` instead. Video and Gameplay do something today; Audio is remembered
and waits for there to be a sound to apply it to, and Hotkeys is a placeholder.

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
