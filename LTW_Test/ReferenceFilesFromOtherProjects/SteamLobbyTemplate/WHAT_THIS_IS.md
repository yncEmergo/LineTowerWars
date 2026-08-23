# Steam / Local Multiplayer Lobby Template — reference copy

Source: ViMayer, *Godot-Steam-Local-Multiplayer-Lobby-Template* (MIT, see `LICENSE`).
Its original readme is `README.md` in this folder.

## Why it lives here

It is a complete Godot **project**, not an addon. Installing it unpacked its whole tree
into the project root, which is why `README.md`, `LICENSE` and `icon.png` were replaced
and why folders appeared under `Scenes/` and `Scripts/`. Everything it brought was moved
here unchanged.

The `.gdignore` next to this file stops Godot scanning the folder at all, so none of it
is parsed, imported or class-registered. That is what silenced the
`Identifier "Online" not declared in the current scope` error wall: `Scripts/globals/Online.gd`
is `extends Node` with no `class_name`, so the name `Online` only exists when the script is
registered as an autoload — and the installer never merged that `[autoload]` line into our
`project.godot`.

To run it, import this folder as its own separate Godot project (delete the `.gdignore`
first) rather than wiring it into LTW.

## What is worth reading

- `Scripts/globals/Online.gd` — the whole point of keeping this. A compact worked example
  of Steam lobby create / join / invite plus an ENet fallback on the same RPC surface.
  Also shows resource-over-RPC serialisation (`to_dict()` / `from_dict()`).
- `Scenes/steam_friends_list/` — a working friends list and invite popup.
- `Scripts/player_data_resource.gd` — `PlayerData`, the per-peer record.

`Scenes/player_character/` and `addons/JehenoAdvancedFirstPersonController(Modified)/` are
a first-person robot demo. They are here only so the template stays runnable as a project.

## What is NOT worth copying

Its style is a long way from `CLAUDE.md`: `:=` inference, `and`/`or`, `@onready`, `$` node
paths, one-line function bodies, no `References` indirection, and tuning constants
(`STEAM_APP_ID`, `LOCAL_SERVER_ADDRESS`, `LOCAL_SERVER_PORT`, `MAX_PLAYERS`) hardcoded in
the script instead of a config `.tres`. Treat it as documentation, not as code to lift.

It also claims the class names `MainMenuUI`, `Lobby` and `PlayerData` — which is why our
own screens are called `MainMenu`, `LobbyRoom` and `LobbyInfo`.

## What did NOT move

`addons/godotsteam/` stays in the project. It is a GDExtension (the real dependency the
template is built on), it loads on its own, it needs no `[editor_plugins]` entry, and it
produced none of the errors. The `[steam]` section in `project.godot` is registered by it.
