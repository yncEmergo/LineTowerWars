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

**The content is placeholder.** The towers and creeps in the game are a test set — four
towers and six creeps, unbalanced, chosen to have something to shoot and something to send.
They are all being replaced by the real Warcraft III Line Tower Wars roster, which is written
up in full in [unit_data.md](unit_data.md) and is the next major piece of work.

**The map is a fixed 6 x 2 grid of twelve lane slots**, whoever turned up. A 1v1 fills two of
them and the other ten are black ground, which the camera and the minimap both still cover.

What is deliberately not built yet: client-side prediction, bandwidth optimisation, an end
screen, player colours, creep unlock timing, the technology system, and anything past a 1v1.
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
addons/     godotsteam (GDExtension), log, godot_ai, reload_current_scene
ReferenceFilesFromOtherProjects/   read-only reference material, not part of the build
```

`2DArt/`, `3DArt/` and `Audio/` are where textures, meshes and sound go. They do not exist
yet, because there is no art at all so far — everything in the game is a primitive.

Boot scene is `Scenes/Boot/boot.tscn`. It decides whether this process is a client or a
dedicated server and then gets out of the way — see multiplayer.md §2.

The in-match overlay is one scene, `Scenes/UI/match_hud.tscn`, instanced into `Main.tscn`
as `MatchHUD`. Open it to see the whole HUD composition in one place: nothing draws over
a match that is not a child of it. The minimap is one of its children and is the only piece
that reads the world back rather than being told about it — `Scripts/UI/Minimap.gd` walks
`MatchSession`'s live units and frames `GameConfig.map_bounds()`, the same rectangle the
camera pans over.

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
