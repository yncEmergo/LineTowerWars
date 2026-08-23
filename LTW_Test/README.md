# Line Tower Wars (working title)

A standalone 3D remake of the Warcraft III custom map **Line Tower Wars**: a PvP tower
defence for 2–15 players where each player defends their own lane and spends gold to send
creeps into everyone else's.

Built with **Godot 4.7**, targeting PC (keyboard & mouse).

## Status

Pre-alpha. The current and only milestone is a **1v1 prototype**. Free-for-all with 3+
players is out of scope until that works.

**It is networked and playable.** A dedicated server hosts lobbies and runs the match; two
clients join, build, send creeps at each other, steal lives and finish with a placement.
The server is the only machine that simulates — clients send orders and draw what comes
back, so two views cannot disagree.

What is deliberately not built yet: client-side prediction, bandwidth optimisation, an end
screen, player colours, creep unlock timing, and anything past a 1v1. See
[multiplayer.md](multiplayer.md) for what is decided and what is next, and `game_rules.md`
for the rules that exist but are not implemented.

## Documentation

Read them in this order. Each one is the authority on its own subject, and where two
disagree the more specific wins.

| File | Contents |
| --- | --- |
| [game_rules.md](game_rules.md) | The game design: economy, creeps, towers, lives, win condition. **The authority on rules.** Says which of them are built. |
| [CLAUDE.md](CLAUDE.md) | Code conventions, naming, the resource/reference architecture, and the engine gotchas that have already cost a debugging session. |
| [multiplayer.md](multiplayer.md) | The multiplayer decisions (D1–D26), the architecture they imply, the roadmap, and what each step actually took. The long one. |
| [server.md](server.md) | How to start, stop and aim the dedicated server. Controls only. |

`claude_notes.md` is a stale duplicate of CLAUDE.md and should be ignored.

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
2DArt/      textures
3DArt/      meshes
Audio/      sound
Resources/  resources (.tres) — config, unit stats, abilities
Scenes/     scenes (.tscn)
Scripts/    GDScript
addons/     godotsteam (GDExtension), log, godot_ai, reload_current_scene
ReferenceFilesFromOtherProjects/   read-only reference material, not part of the build
```

Boot scene is `Scenes/Boot/boot.tscn`. It decides whether this process is a client or a
dedicated server and then gets out of the way — see multiplayer.md §2.

Five autoloads, in this order: `Net`, `MatchStart`, `Lobby`, `Commands`, `Replication`.
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
