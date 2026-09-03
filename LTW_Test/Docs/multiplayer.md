# Multiplayer

What the networked build IS, and where each part of it lives. Rules are `game_rules.md`,
numbers are `unit_data.md`, conventions are `CLAUDE.md`, and starting the server is
`server.md`. Read this before writing networking code.

**Two players can play each other, start to finish.** A dedicated server hosts the lobby
list; the host presses Start and everyone watches the same countdown; all three machines -
both clients and the headless server - build the same match from the same seed, proven by
checksum rather than by inspection. From there orders travel to the server as INTENT, the
server is the only machine that simulates, and both clients draw what it sends. Towers,
creeps, gold, income, stock, lives, value and placement all replicate. A leak steals a life,
a disconnect erases the leaver's maze, and the last player standing ends the match.

**What that costs, and it is deliberate:** the client predicts nothing (D17), so an order
takes a round trip before anything moves, and the server sends the WHOLE world twenty times
a second. Both are phase A choices, both are listed under *What is deliberately not built*
at the end, and both now have something real to be measured against rather than guessed at.

**Where to start reading**, whichever of these you need:

| Looking for | Go to |
| --- | --- |
| What is decided and must not be re-opened | §1, D1-D29 |
| The API surface, with real checked signatures | §2 |
| How the whole thing is meant to work | §5 |
| What is genuinely still open | §1 → *Still open* |
| Why a settled question was settled that way | §11 |
| Starting and stopping the server | `server.md`, not this file |

*This file once also carried the milestone plan that built all of the above, step by step.
That plan is done, and the process behind it stopped being worth reading the moment it was:
what a reader needs now is what exists. The decisions it produced are §1, the lessons that
outlived it are in `CLAUDE.md`, and the rest is in the git history.*

---

## 1. Decisions

| # | Decision | Date | Notes |
| --- | --- | --- | --- |
| D1 | **No physics engine, anywhere.** All gameplay is plain maths. | 2026-08-21 | Now a hard rule in `CLAUDE.md`, and already true of the code before it was written down. |
| D2 | **Server-authoritative replication.** The server decides what happened. | 2026-08-21 | Chosen over lockstep and host-authority deliberately, accepting it is heavier for a 1v1 prototype, because ranked play needs it and retrofitting it later would be a rewrite. |
| D3 | **The game server is a headless Godot export of this same project**, in GDScript. | 2026-08-21 | One copy of the simulation, shared by client and server. See §5.2. |
| D4 | **Dedicated server process from day one**, run on localhost during development. | 2026-08-21 | Not a listen server. "Runs on your machine" and "runs in a datacenter" then differ only by an address. |
| D5 | **ENet (`ENetMultiplayerPeer`) is the transport.** | 2026-08-21 | UDP with reliable *and* unreliable channels. Built in. See §6 for why not WebSockets. |
| D6 | **Lobbies live on the server.** | 2026-08-21 | No Steam lobbies, no separate master server. |
| D7 | **No account backend for now.** Rating, elo and match history are deferred. | 2026-08-21 | Will very likely exist later, so nothing may make it harder — see §9. |
| D8 | **Steam is distribution and identity, not transport.** | 2026-08-21 | Integration can be deferred until after the server works. See §10. |
| D9 | **PickleGD: keep the link, do not install yet.** | 2026-08-21 | Not a transport. Likely useful for cold-path payloads, wrong for the hot path. See §7. |
| D10 | **The network session may be a plain autoload**, standing on its own rather than going through `References`. | 2026-08-21 | User's call: `References` is a convenience, not a hard rule, and a global-like entity is exactly what a session that outlives scene changes needs. Unblocks 0.1. |
| D11 | **Simulation tick is 20 Hz**, in a config `.tres`. | 2026-08-21 | Squarely in the RTS band. 50 ms, and an exact 3:1 divisor of a 60 Hz render frame. See §5.5. |
| D30 | **The public server runs on a RENTED machine, and a deploy is MANUAL.** Pushing changes nothing; the server keeps running the commit it has until it is told otherwise. | 2026-09-03 | User's call, forced by circumstance: the developer's building has a managed connection with no address that can be dialled from outside, so hosting at home cannot reach a tester at all - see `server.md`. Manual rather than automatic on purpose. A restart ends any match in progress (D19), and a `protocol_version` bump (D29) locks out every tester who has not taken the new build, so WHEN that happens has to be a decision rather than a side effect of pushing. Supersedes D18. |
| D29 | **A build states its `protocol_version` on connecting, and the server refuses one that disagrees.** | 2026-09-03 | Bumped by hand, in `NetworkConfig`. Needed the moment a build exists that somebody else has a copy of: two versions of this project cannot otherwise be told apart until they have already gone wrong together, because the server simulates and the clients draw, so a disagreement surfaces as refused orders or a world that quietly differs - never as "you need to update". Lives on `Net` rather than `Lobby`, though `Lobby.register_player` is also a first message, because it gates the CONNECTION: a peer refused there never reaches `Lobby`, and anything added later that talks earlier is covered without being changed. `WorldChecksum` stays underneath it - a version catches two builds that were never meant to meet, the checksum catches two that agree on their version and still built different worlds. |
| D28 | **A client dials a LIST of addresses, taking the first that answers**, rather than one authored address. | 2026-09-03 | User's requirement, from the shape of the dev loop: two PCs in different buildings take the server in turns, and whichever is not hosting has to find the one that is without being rebuilt or told which. Sequential, cheapest-first - 127.0.0.1 leads, so a player on the same machine as the server connects instantly. The cost is that each dead candidate is paid in full at `connect_timeout_seconds`, which is why that number came down: a dead candidate is now the common case rather than the failure case. Parallel probing would cost one round trip instead of N timeouts and is the upgrade if the list ever grows past a handful. `--address` still collapses the list to one, so the headless probes and `run_server.ps1` are untouched. |
| D27 | **Developer cheats are refused in a NETWORKED match** unless the server's own config deliberately allows them. | 2026-09-02 | User's call. A cheat is a real player order the authority grants (§2), so the master switch alone would let one player in a real match hand themselves the gold to end it - and the file that refuses it is the SERVER's, not the one they are looking at. A second flag rather than a flat refusal, because the networked build has to be testable: a headless two client run needs the same shortcuts a single player run gets. `GameConfig.cheats_allowed(Net.is_online())` is the one place the two are put together. |
| D26 | **A dropped player gets a 10 second hold** before being declared gone, and a DELIBERATE leave skips it entirely. | 2026-08-23 | User's call, from the three sketched in §11.1. Sits on top of the ~5.6 s ENet already takes to notice a hard-killed client, so a crash resolves in about fifteen seconds and a brief hiccup costs nothing. Implementable only because a goodbye and a silence are different messages, not merely different speeds - `MatchStart.leave_match()` in §2 is what makes the goodbye actually arrive. |
| D25 | **The send ring, lives and life steal are part of the networked build**, not a separate gameplay task. | 2026-08-23 | User's call. All three were already specified in `game_rules.md` and none is networking, but "see each other's lives drop" is untestable without them, and D14's disconnect rule needs lives that can drain. Built and verified before any command went over a wire. |
| D24 | **Start runs a 5 second countdown**, shown to everyone in the lobby. Nobody may join during it; any player leaving cancels it; the host may cancel it at any point. The browser lists such a lobby as **"Starting..."** and unjoinable. | 2026-08-23 | User's rule. Gives everyone a moment to see the match is about to begin, and makes "who is in this match" final before the handshake rather than during it. Fully specified; §8.1. |
| D23 | **A lobby closes when its host leaves.** Everyone else is returned to the browser with a reason. | 2026-08-23 | User's call, over promoting the next player. The Warcraft III rule, and the simplest one: no succession to define, no "who is host now" to replicate. |
| D22 | **Lobby membership reuses `MatchPlayer`.** A lobby seat is a slot, a display name and a peer id — exactly a `MatchPlayer`. | 2026-08-21 | So a lobby is a proto-`MatchSetup` and pressing Start wraps the list rather than converting it. One serialisable player type, not two. |
| D21 | **One `Lobby` autoload on both sides**, branching on `multiplayer.is_server()`, rather than a separate `LobbyService` and `LobbyClient`. | 2026-08-21 | Godot routes an `@rpc` by NODE PATH: the receiver must sit at the same path on both machines or the call silently goes nowhere. One autoload makes the paths match by construction, and supersedes the separate service/client shape this file originally sketched. |
| D20 | **A client connects when Multiplayer is pressed**, not at boot. | 2026-08-21 | The lobby browser needs a live list, so the connection's lifetime is the browser's. Single player never opens a socket, and the browser is where every failure state in 1.8 already belongs. |
| D19 | **One process runs the lobby and the match** for now. | 2026-08-21 | Splitting them later is an address change, so it is safe to defer. Does not conflict with D16: still one process per match once matches are spawned separately. |
| D18 | **Dev server runs locally in the office**, on the user's own PC for the first tests. | 2026-08-21 | Same code path as anywhere else; the address is one line in `NetworkConfig`. |
| D17 | **Feedback now, prediction later.** No client-side prediction in the first version. | 2026-08-21 | Immediate local feedback only. Prediction revisited much later, as an experiment. |
| D16 | **One server process per match.** | 2026-08-21 | Also the only way to use more than one CPU core — see §11.3. |
| D15 | **Load timeout 60 s**, then start without whoever is missing, provided `min_players` are ready. No area spawns for them. | 2026-08-21 | See §11.2. |
| D14 | **A disconnect erases that player's maze.** The match continues; their lives drain away through normal life steal until they are eliminated normally. | 2026-08-21 | Reuses life steal, elimination and ring-closing exactly as `game_rules.md` already defines them — see §11.1. |
| D13 | **No reconnect. Out is out.** A player who disconnects is gone for that match. | 2026-08-21 | User's call. Simplifies a lot — see §11.1. Does not rule out a short grace period before declaring someone gone, which is a different thing. |
| D12 | **An ability's network id is authored on the ability** (`UnitAbility.ability_id`), never derived from a position in a list. The registry is built from the content itself, never from a hand-kept list. | 2026-08-21, extended 2026-08-23 | User's call, and the right one: adding, removing or reordering abilities cannot renumber anything else, and there is no list to keep in step. **Extended 2026-08-23, user's call: the registry holds EVERY authored ability, orphan or not** - so walking the content graph is no longer enough on its own and a folder scan was added beside it. An ability on nobody's card still owns its number, which is what stops a new one being authored into the same id while its card is still being built. Matters most while content is being made, which is exactly when nothing is on a card yet. |

### Still open

Only genuinely open questions live here. Anything answered has become a decision above, or
is described as built in §2.

- **Where the player stats panel belongs on screen.** It exists top right - name, life,
  income, value, placement - but `game_rules.md` never placed it, so the layout is a
  placeholder. What a player is CALLED there is settled: ordinarily the display name, and in
  an ANONYMOUS match their colour, which is a lobby setting (§8.2).
- **Whether one server process should host more than one match.** It hosts one, refuses a
  second with a sentence, and frees itself when that one empties - D19 doing its job until
  D16 splits them. Nothing is blocked on it.

---

## 2. What exists right now

Boot scene is `Scenes/Boot/boot.tscn`, which dispatches on role and is never seen.

```
boot  ──dedicated_server tag / --server──▶  server_main  (──▶ server_match, later)
   │
   └──otherwise──▶  main_menu

main_menu  ──Multiplayer──▶  lobby_browser  ──Create Lobby──▶  lobby_room
	│                              │                                │
	└──Play Prototype──▶ Main.tscn └──Back──▶ main_menu             └──Leave──▶ lobby_browser
																	│
						Start ──▶ 5 s countdown ──▶ match_loading ──▶ Main.tscn
```

The server's own two scenes swap the same way, and BOTH ways: `server_main` opens
`server_match` when a match starts, and comes back to `server_main` when the last player of
it leaves.

| File | Role |
| --- | --- |
| `Scripts/Boot/Boot.gd` + `Scenes/Boot/boot.tscn` | The `main_scene`. Picks client or server, then gets out of the way. |
| `Scripts/Config/BootConfig.gd` + `Resources/Config/boot_config.tres` | The server's entry scene path and the `--server` argument. |
| `Scripts/Server/ServerMain.gd` + `Scenes/Server/server_main.tscn` | The server process: a status line and a log view. `log_line()` writes to both the view and stdout. |
| `Scripts/UI/Menus/MainMenu.gd` | Play / Multiplayer / Quit. |
| `Scripts/UI/Menus/LobbyBrowser.gd` | The lobby list and the create dialog. |
| `Scripts/UI/Menus/LobbyRoom.gd` | Player slots and the host's Start button. |
| `Scripts/UI/Menus/LobbyListEntry.gd` / `LobbySlot.gd` | Row and slot prefabs. |
| `Scripts/UI/Menus/MenuNavigation.gd` | Every scene change, in one place. |
| `Scripts/UI/Menus/GameMenu.gd` | In-match menu: resume, options, leave, quit. Esc / F10. |
| `Scripts/Multiplayer/NetworkService.gd` | The autoload **`Net`**: owns the one ENet peer, reports through signals and a `Result` enum. Walks the address list until something answers (D27), and is where a build states its version and a wrong one is refused (D28). |
| `Scripts/Config/NetworkConfig.gd` + `Resources/Config/network_config.tres` | The address LIST, port, max peers, per-address connect timeout, the protocol version, command-line overrides. |
| `Scripts/Util/CommandLineUtil.gd` | Reading launch arguments — both spellings, both arg lists, one place. |
| `Scripts/Multiplayer/LobbyService.gd` | The autoload **`Lobby`**: the registry on the server, the mirror of it on a client, and the start countdown (D24). |
| `Scripts/Multiplayer/MatchStartService.gd` | The autoload **`MatchStart`**: the handshake from "countdown ran out" to "the match exists on every machine". Nothing beyond that. |
| `Scripts/UI/Menus/MatchLoading.gd` + `Scenes/UI/Menus/match_loading.tscn` | The loading screen: a threaded load with a real progress bar, and who is still loading. |
| `Scripts/Game/WorldChecksum.gd` | One number for the world a machine just built, so two machines can compare theirs in one message. |
| `Scripts/Multiplayer/Command.gd` | One player order on its way to the server: ids and numbers, never object references. |
| `Scripts/Multiplayer/CommandService.gd` | The autoload **`Commands`**: the one road every order takes, and the server-side validation of it. |
| `Scripts/Multiplayer/ReplicationService.gd` | The autoload **`Replication`**: the whole world, every tick, server to clients (phase A). Plus the one channel that is NOT the whole world: the status effects of the units clients have asked to be told about. |
| `Scripts/Combat/StatusEntry.gd` | One debuff as anything that draws one reads it, and as it crosses the wire: kind, source ability, magnitude, seconds left, stacks. |
| `Scripts/Game/UnitTypeRegistry.gd` | Every KIND of unit by id, so a spawn can be replicated as a number (D12's argument, applied to units). |
| `Scripts/UI/MatchStatusBar.gd` | Gold, population and the income countdown, across the top middle. |
| `Scripts/UI/PlayerStatsPanel.gd` + `PlayerStatRow.gd` + `Scenes/UI/player_stat_row.tscn` | Every player's life, income, value and placement. Placeholder layout - `game_rules.md` does not place it yet. |
| `Scripts/Abilities/ToggleGridAbility.gd` | The builder's grid toggle. Local only: presentation never becomes a command. |
| `Scripts/Multiplayer/LobbyInfo.gd` | What one lobby advertises, AND its roster of `MatchPlayer`s. |
| `Scripts/Multiplayer/LobbyIdentity.gd` | Who the local player is. Currently the OS user name. |
| `Scripts/Multiplayer/MatchSetup.gd` + `MatchPlayer.gd` | Who is in a match, which slot is local, the RNG seed. Flat and serialisable. |
| `Scripts/Game/MatchSession.gd` | This match: the setup, the seeded RNG, the unit-id registry, the tick counter, the ability registry. A scene node, held by `References`. |
| `Scripts/Abilities/AbilityRegistry.gd` | Every ability a command can name, built by walking the content graph. |
| `Scenes/Server/server_match.tscn` | A match with no camera, HUD or effects. Proves the simulation stands alone, and IS the scene the server opens for a match. |
| `Scripts/Config/MenuConfig.gd` + `Resources/Config/menu_config.tres` | Scene paths, player counts, title, countdown and load timeout. |
| `Scripts/Config/ContentConfig.gd` + `Resources/Config/content_config.tres` | Where the content this build contains lives. Only the abilities folder so far, scanned so orphans still get ids (D12). |

In the game scene itself: every player has a builder and a `PlayerState`, all simulation
runs on the 20 Hz tick, every unit carries a network id, and all randomness comes from one
seeded generator. `Main.tscn` holds a `MatchSession` node and a `GameMenu`.

### The match itself: session, setup, unit ids

**`MatchSession`** — a node in the match scene, reached as `References.match_session`. Owns
everything true of *this* match:

```gdscript
session.begin(setup)          # called by Main before anything is built
session.setup()               # the MatchSetup
session.rng()                 # the one seeded generator for the match
MatchSession.match_rng()      # static: the same generator, without holding the session
MatchSession.tick_seconds()   # static: seconds per simulation tick
session.tick()                # simulation ticks since the match began, from 0
session.local_slot()          # which slot this machine plays; 0 on a server
session.is_local_player(slot)
session.player_count()
session.display_name_for(slot)
session.abilities()           # AbilityRegistry
session.register_unit(unit) -> int      # hands out the next id
session.claim_unit_id(unit, id) -> bool # adopts a SERVER-CHOSEN id; use this on clients
session.unit_for(id) -> Unit            # null once it has died - callers must expect that
session.unregister_unit(id)
```

**`MatchSetup`** (`Scripts/Multiplayer/`) — who is in the match. Flat and serialisable on
purpose; Godot cannot send a custom `Resource` over RPC, so it already has `to_dict()` and
`from_dict()`, as does `MatchPlayer`. Fields: `match_id`, `players: Array[MatchPlayer]`,
`local_slot`, `rng_seed`. Also `player_for(slot)`, `local_player()` and
`has_local_player()` — the last is false on a dedicated server. `validate()` reports
duplicate or out-of-range slots.
`MatchSetup.from_config(config)` stands in a single-player setup when the game scene is run
straight from the editor — keep that path working.

**The handoff into a match** is `MenuNavigation.to_game(from, setup)`, which parks the setup
in the static `MenuNavigation.pending_match`. `Main` collects it with
`take_pending_match()`, which **clears it**, so a later direct run cannot inherit the last
lobby's players. The server will build a `MatchSetup` and send it instead; the consuming end
does not change.

**`Unit.unit_id`** — the name both machines call a unit by. Claimed in `Unit.setup()`,
released in `_exit_tree()`. Ids are handed out in spawn order, which two machines spawning
the same things in the same order agree on without being told. Once the server is
authoritative it assigns them and clients adopt them via `claim_unit_id()`, which keeps the
local counter ahead so a locally spawned unit can never collide with one handed down.

**`UnitAbility.ability_id`** — the number a command names an ability by, authored on the
ability itself (D12). `session.abilities().ability_for(id)` resolves it, and returns **null**
for an id this build does not contain — which is what a client running mismatched content
looks like, and must be rejected rather than guessed at.

For that to mean anything, the registry has to hold EVERYTHING this build contains, so it is
built two ways: the walk of the content graph, and a scan of `ContentConfig.abilities_folder`
that catches abilities on nobody's card. A unit's own contribution to the walk is
`UnitStats.card_abilities()` — every ability its card can ever show, not just the ones on it
right now — which `BuildingStats` overrides to add the Cancel it swaps in.

That two-way build is not belt and braces: the walk finds abilities defined INSIDE another
resource, the scan finds abilities in a file of their own that are on nobody's card, and
neither covers the other. An orphan still owns its number, which is what stops a new ability
being authored into the same id while its card is still being built.

**Two world roots, and the distinction is load-bearing:**

- `References.projectiles_root` — projectiles in flight. **Simulation.** Present everywhere.
- `References.effects_root` — impacts, markers, revive lights. **Presentation.** Null on a
  server, and everything that uses it already steps aside quietly.

Anything new that is spawned into the world belongs to one or the other. Getting this wrong
is how the server and the client end up disagreeing about when something died.

**`Main._dedicated_server`** — a bool `@export`, set on `server_match.tscn` and nowhere else.
Forces `local_slot` to 0, so every "is this mine" test answers no, and turns a missing camera
or `ControlsConfig` from an error into the expected state.

*A feature tag would look like a replacement for this flag and is not: the tag answers "is this PROCESS a server", which
`Boot` already asks once, while this flag answers "is this SCENE a server's match" - and the
scene is the honest place for that, since it is the thing that has no camera. The two happen
to agree today and need not always.*

**`Scenes/Server/server_match.tscn`** — a whole match with no camera, HUD, controllers or
effects root. It proves the simulation stands alone, and IS the scene the server loads for a
match.

### The connection and the lobby: `Net`, `Lobby`

Every signature below was read off the code, not remembered. Trust this list over a
recollection; if something here is wrong, the code changed and this section did not.

**`Net` comes before `Lobby` in `project.godot`**, because `Lobby`
subscribes to `Net`'s signals in its `_ready`. Both are named differently from their classes
because Godot refuses an autoload that collides with a global class name.

**`Net`** (`Scripts/Multiplayer/NetworkService.gd`) - owns the one `ENetMultiplayerPeer` and
is the ONLY thing that ever assigns `multiplayer.multiplayer_peer`:

```gdscript
Net.host(port_override := 0) -> Result      # server; opens the listen socket
Net.join(address := "", port := 0) -> Result # client; OK means "started", not "connected"
Net.leave() -> void                          # safe when already offline
Net.status() -> Status                       # OFFLINE | CONNECTING | CONNECTED | HOSTING
Net.is_online() -> bool                      # CONNECTED or HOSTING
Net.is_server() -> bool                      # HOSTING only; false while offline
Net.peer_id() -> int                         # 0 while offline
Net.peer_ids() -> PackedInt32Array           # server side; empty on a client
NetworkService.describe(result) -> String    # static; a Result as a showable sentence
NetworkService.SERVER_PEER_ID                # 1
```
Signals: `status_changed(Status)`, `hosting_started()`, `connected_to_server()`,
`connection_failed(Result)`, `disconnected_from_server()`, `peer_joined(int)`,
`peer_left(int)`.
`Result` is `OK, ALREADY_ONLINE, NO_CONFIG, BAD_CONFIG, HOST_FAILED, CLIENT_FAILED, REFUSED,
TIMED_OUT`.

**`Lobby`** (`Scripts/Multiplayer/LobbyService.gd`) - one object on both machines, branching
on `multiplayer.is_server()` (D21). Client-facing:

```gdscript
Lobby.lobbies() -> Array[LobbyInfo]   # what the browser should list
Lobby.current() -> LobbyInfo          # the lobby WE are in, or null
Lobby.is_in_lobby() -> bool
Lobby.is_host() -> bool               # may press Start
Lobby.create(lobby_name: String, max_players: int) -> void
Lobby.join(lobby_id: String) -> void
Lobby.leave() -> void
```
Signals: `lobby_list_changed(Array[LobbyInfo])`, `current_lobby_changed(LobbyInfo)`,
`request_refused(String)`, `lobby_closed(String)`.
Wire, both directions: `register_player`, `request_create`, `request_join`, `request_leave`
are `@rpc("any_peer", "reliable")`; `receive_list`, `receive_lobby`, `receive_closed`,
`receive_refusal` are `@rpc("authority", "reliable")`.

**`LobbyInfo`** - now carries its roster, so a lobby is a match waiting to happen (D22):

```gdscript
lobby_id: String   lobby_name: String   host_id: int      # host_id is a PEER id
max_players: int   is_in_progress: bool  ping_ms: int     # ping is never measured yet, so -1
members: Array[MatchPlayer]                               # join order, slots 1..n

LobbyInfo.from_dict(d) / lobby.to_dict()
lobby.player_count() / is_full() / is_joinable() / host_name()
lobby.member_for(peer_id) / has_member(peer_id)
lobby.add_member(player) / remove_member(peer_id) / renumber_slots()   # server side only
lobby.players_text() / status_text() / ping_text()
```

**Three patterns worth not re-deriving:**

1. **Success has no "yes".** The server never acknowledges a create or a join. It says which
   lobby you are now in, and the screen navigates on that. One path covers create, join, and
   anything later that puts a player into a lobby.
2. **The mirror: leaving and being thrown out are one path.** Both end as "you are in no
   lobby"; only the message differs. That is why D23, and losing the connection entirely,
   needed no code in the room screen.
3. **A reason is emitted BEFORE the change it explains.** Whoever hears "you are out of a
   lobby" reacts by changing scene, so a reason sent afterwards is lost.
   `MenuNavigation.pending_notice` / `take_pending_notice()` carries it across, exactly as
   `pending_match` already did.

**Smaller things that now exist:**

```gdscript
CommandLineUtil.has_flag(flag) -> bool                 # both spellings, both arg lists
CommandLineUtil.value_for(key, fallback := "") -> String
CommandLineUtil.int_for(key, fallback) -> int
SceneUtil.change_scene(from, path, owner_name := "") -> bool
LobbyIdentity.sanitise(raw, max_length := 32) -> String   # run on the SERVER, on arrival
References.boot_config / References.network_config
```

---

---

### Getting into a match: `MatchStart`, the countdown, the loading screen

**`MatchStart` joins them in `project.godot`**, between `Net` and
`Lobby`. It sits in the middle because `Lobby` subscribes to its `match_abandoned`
in `_ready`, and it subscribes to `Net`'s signals in its own.

**`MatchStart`** (`Scripts/Multiplayer/MatchStartService.gd`) - everything between "the
countdown ran out" and "the match exists on every machine", and nothing beyond it:

```gdscript
MatchStart.is_busy() -> bool                 # server: a match is running in this process
MatchStart.begin(setup: MatchSetup) -> void  # server: announce it and start waiting
MatchStart.setup() -> MatchSetup             # the match being loaded or played, or null
MatchStart.ready_ids() -> PackedInt32Array   # who has finished loading
MatchStart.report_loaded() -> void           # said by the loading screen
MatchStart.report_world_checksum(sum: int)   # said by Main, both roles, 2.5
```
Signals: `match_starting(MatchSetup)`, `readiness_changed(PackedInt32Array)`,
`match_cancelled(String)`, `match_abandoned(String)` - the last one server side only.
Wire: `report_ready`, `report_checksum` are `@rpc("any_peer", "reliable")`;
`receive_match_starting`, `receive_readiness`, `receive_match_start`,
`receive_match_cancelled` are `@rpc("authority", "reliable")`.

**`Lobby` gained the countdown** (D24), which is a lobby rule and stayed there:

```gdscript
Lobby.start()         # the host asks; the server checks the claim
Lobby.cancel_start()  # the same button for those five seconds
```
Signals: `countdown_changed(seconds_left: int)`, `countdown_cancelled(reason: String)`.
Wire: `request_start`, `request_cancel_start` any_peer; `receive_countdown(seconds_left,
reason)` authority - ONE message describing the whole state of the countdown, with a
negative count meaning "stopped, and here is why". A second rpc would have been two events
where there is only one fact, and `LobbyInfo.ping_ms` already uses a negative sentinel.

**`LobbyInfo.to_match_setup(id, seed)`** - the conversion D22 promised. Members are COPIED,
because the lobby carries on existing after the match starts and renumbering its slots must
not reach into a running match. `local_slot` is left at 0: it is the one field that differs
per machine, and each machine is told its own when the setup is sent to it.

**`MenuNavigation` gained two ways out of the menus**: `to_match_loading(from)`, and
`to_server_scene(from, path, setup)` for the server's own two scenes. The server's paths are
ARGUMENTS rather than read from `BootConfig` inside, because the way back is called from a
match scene, where `References` answers for the match and has never heard of a `BootConfig`.

**`WorldChecksum.of(setup, areas, session)`** (`Scripts/Game/`) - one number for the world a
machine just built. Walks the setup, the areas and the UNIT REGISTRY, quantising positions to
a millimetre. `local_slot` is deliberately not in it, being the one field that is supposed to
differ. `MatchSession.unit_ids()` was added for it, ascending, because a dictionary's own
order has no business deciding whether two worlds match.

**`MenuConfig`** grew `match_loading_scene_path`, `start_countdown_seconds` (5) and
`load_timeout_seconds` (60); **`BootConfig`** grew `server_match_scene_path`, and
`server_main.tscn` now wires a `BootConfig` into its `References` - it had none, which is the
one bug the first end-to-end run found.

**Three things worth not re-deriving:**

1. **Loading is not building.** The loading screen gets the PackedScene into memory and says
   so; the world is created afterwards, from the roster that comes back with `match_start`.
   That order is forced by D15: "no player area spawns for a missing player" can only be true
   if nothing was placed before we knew who was missing.
2. **The server comes back.** When the last player of a match disconnects, the process
   returns to `server_main.tscn` and the lobby is unlocked. Without it, one match per server
   process meant one match per *run*, which is unbearable while testing. `ServerMain` no
   longer assumes it is running for the first time.
3. **A match id travels with every answer.** `report_ready` and `report_checksum` both carry
   it, so a late answer about a match that is already over cannot count towards the next one.

---

---

### Playing a match: `Commands`, `Replication`, authority

**The autoloads, in this order** - `Net`, `MatchStart`, `Lobby`, `Commands`,
`Replication`. Every one of them is an autoload for the same forced reason: an `@rpc` routes
by NODE PATH, and the two match scenes have different roots (`/root/Main/...` against
`/root/ServerMatch/...`), so nothing inside a match scene can be an rpc endpoint.

**`Commands`** (`Scripts/Multiplayer/CommandService.gd`) - the one road a player order takes:

```gdscript
Commands.submit(ability: UnitAbility, units: Array, target: AbilityTarget) -> void
Commands.submit_player_action(action: Command.PlayerAction, tech_id: int = 0) -> void
```
The second is the same road for an order given to NOBODY - a Research Center press. It names
no units and no ability, so the two checks that make a unit order safe (does this player own
the unit, is the ability on its card) have nothing to check: the whole of the question is
WHO sent it, and the server already answers that by overwriting the slot from the peer id.
Everything past it is refused by `TechManager`, which is where the rules live, exactly as a
build order's rules live in the area it would be placed in.

**The DEVELOPER CHEATS travel this same road**, and that is the point of them: a cheat is a
`PlayerAction` like a Research Center press, so the AUTHORITY grants it and a client's press
takes the round trip every other order takes. Adding the gold where the key was pressed would
have redrawn a number the server never agreed to.

Which means a cheat is a real order that a real server really applies, so it is refused in a
NETWORKED match by default: `GameConfig.cheats_allowed(Net.is_online())` wants a second flag
on top of the master switch, and the server checks it in `_cheat_target` whatever the client
asking was built from. The point is not that a cheat could be forged - it cannot, the slot is
overwritten from the peer id - but that one player with a permissive local build and a
permissive server could hand themselves the gold to end a match. Turning it on is a decision
made on the SERVER, deliberately, for a headless test. What the cheats DO is in the root
README under Running it.

One of them changes nothing and still takes this road: the cheat that SAVES a maze to a file
only reads the world, but the world worth reading is the authority's - a client's towers are a
drawing of it. So in a deliberately cheat-enabled networked test the file lands on the
SERVER, next to its own logs, and not on the machine the key was pressed on.

Signals: `command_applied(Command)`, `command_rejected(Command, String)` - both server side.
Wire: `submit_command` is `@rpc("any_peer", "reliable")`. `Command`
(`Scripts/Multiplayer/Command.gd`) is a RefCounted, not a Resource: it is created, sent and
dropped, never authored.

**`Replication`** (`Scripts/Multiplayer/ReplicationService.gd`) - the world, every tick.
Nothing calls into it; it reads the world on the server and writes it on a client. Wire:
`receive_snapshot` is `@rpc("authority", "unreliable")`. `process_priority = 1000` so it runs
AFTER the match scene and describes the tick that just finished.

A unit record carries its MANA and its MAXIMUM mana alongside its health. Mana is what most
of the elemental roster's abilities run on - fill up by attacking, then spend the lot - so a
client that could not see the bar would be watching a tower fire for no reason it could read.
The maximum is sent rather than looked up because one tower in the game lowers its own.

The SAME TWO FIELDS carry a creep's pool, for the creeps whose trait runs on one. They are
the same question asked of a different kind of unit and only one kind ever answers on a given
record, so nothing on the wire grew when creeps gained mana.

It also carries the PROGRESS of whatever countdown a building is running, and one flag saying
whether a morph is an upgrade or a return to an Elemental Core. Both are there for the same
reason the mana is: a client that told a tower to sell would otherwise watch it stand there
doing nothing for the whole countdown. One number covers construction, selling and morphing
because a tower only ever runs one of them at a time, and it is written straight into the
same elapsed clocks a single-player run uses, so every reader gets the server's answer through
exactly one path. It puts the RISING MODEL back on a client too, which had only the two ends
of that movement before.

A record also carries the BANKED DAMAGE a tower's passives have added to it for good, and
which option a CYCLED ability on it is set to. Both are there on the mana's reasoning taken one
step further. The banked damage is bought by KILLING, which only ever happens on the server, so
a client that was not told would draw its own Alchemist's damage line and its stack bar at zero
for a whole match. The choice is a setting the player themselves changed on their own tower,
like the Prioritize flag beside it, and a card that went on drawing the old answer would read
as a button that does nothing. One field each, for the tower rather than per ability: no tower
carries two passives that bank or two abilities that cycle.

One spare BIT of that flags field says whether a player has this unit in a fight, and it is
there for the builder alone - the one unit that never picks its own targets, so the one unit
whose swing a client cannot work out for itself. It has to be sent because an attack ordered
onto a UNIT draws no marker, and the order chain a client is given is only the drawing half of
the real one: without the bit, a builder hammering a creep on the server stands with its arm
down on both clients. Nothing on the wire grew for it, since the flags int was already there.

What a morph is turning INTO is still not sent, so a client draws no upgrade preview and its
panel pictures the tower rather than what it is becoming. That is a whole unit type per record
for one icon, and the countdown, the name and the bar are all right without it.

**ORDER CHAINS ride down in a block of their own**, self-describing like the technology one
and for the same reason: a chain is a different length for every unit and gets shorter as it is
worked through. Only the tasks that DRAW something are in it - a walk still to be made, a tower
ordered and not started - because the block exists to put markers on the ground and nothing
else reads it. An attack aimed at one creep is a task like any other and puts nothing on the
floor, so no client is ever told about one; what it would draw is the ring that already blinks
on that creep, locally, the moment the order is given.

That is what keeps it affordable next to the rest of phase A. A queue exists only on a unit
somebody has ordered, which in a match is one builder and a handful of attacker creeps, and
only the builder's chain of towers is ever more than a couple of entries long. A chain that is
finished simply stops being in the block, exactly as a dead unit stops being in the unit
records - absence IS the message, so there is no "order done" event to lose.

The QUEUE ITSELF is simulation and lives only on the authority: a client never advances a task,
never decides one is finished and never starts the next. What it has is a mirror of the drawing
half, and `OrderQueue.orders()` answers which of the two this machine may read - the same shape
`ActiveAbilityState.cooldown()` has for a tower's ability clock. A `Command` grew one bit to go
with it, `queued`, which says the player was holding shift; like everything else in a command it
is INTENT, and what it means is decided by the server against its own world.

**WHAT IS ON A UNIT rides its own channel**, not the unit record - the watched-unit block in
§5.4, which is the one thing in phase A that is not "the whole world every tick". A client
names the unit its panel is showing and is told that unit's effects and no others.

What goes into it is `Unit.status_entries()`, and it is VIRTUAL rather than a cast to `Creep`,
which is what it used to be. That cast quietly kept three whole systems off the wire: what a
technology disc lends a tower, what a creep curses one with (`TowerStatus`), and the armour a
packmate's aura grants a creep. All three were real on the server and invisible to both
clients - so a client drew the range circle of a tower standing in a Primal disc at the
tower's own reach, around a tower that really did have the longer one. Anything that grows a
fourth kind of effect overrides that one method and is replicated for free.

**Folding those records back into a number is the UNIT's job, never the reader's.**
`armor_value()`, `attack_speed_ratio()`, `attack_damage_ratio()` and `attack_range_bonus()`
each answer from the live objects on the authority and from the replicated entries on a
client, so the panel, the range overlay and the barrels cannot disagree about the same tower.
The panel used to carry that branch itself, which worked only while it was the only reader.

**`MatchSession.is_authority()`** - static, and the single question every simulation loop
asks:

```gdscript
static func is_authority() -> bool   # !Net.is_online() || Net.is_server()
```
True for a solo run and for the server, false on a client. **Anything new that advances the
world must ask it**, or a client will simulate something the server also simulates and the
two will disagree.

**`UnitStats.unit_type_id` + `MatchSession.unit_types()`** - the same shape as `ability_id`
and the ability registry (D12), for the same reasons. `UnitTypeRegistry.stats_for(id)` returns
null for a type this build does not contain, which is a mismatched build and must be refused.

**`TechDefinition.tech_id` + `MatchSession.techs()`** - a third namespace on the same pattern,
for what a Research Center press names. Found by SCANNING the folder `ContentConfig` names and
never by a walk: a technology is on nobody's card and is reachable from nothing, so unlike an
ability there is no graph that could lead to one. What each player owns rides in the snapshot
as their slot, the ticks left on their undo window, and the list of ids - self-describing
rather than a fixed stride, because the list is a different length for every player.

**A unit id can CHANGE TYPE, and that is the whole of tower upgrading on the wire.** An
upgraded tower keeps its id on purpose - to every other machine, and to the player's own
selection, it is still the same tower - so the snapshot describes the same id with a different
`unit_type_id` and the client rebuilds it from the new prefab. It cost no wire format change
at all, because the type id was already in every record for the spawn path.

The order that rebuild happens in is load bearing, and it is the same order the authority uses
in `Building._complete_upgrade()`: the replacement enters the tree first, the swap is
ANNOUNCED while the old node is still standing, only then does the old node leave, and only
then does the replacement adopt the id and the grid cells. Announcing it afterwards lets
`tree_exiting` empty the selection and the control groups a moment before anything can put the
replacement where the old tower stood; adopting before the old node leaves marks the cell free
with a tower standing on it, which this client would then draw a green build ghost over.

**`MatchSession.replace_unit(old, new)` / `unit_replaced`** - how that announcement reaches
presentation. A signal rather than a call into the selection, because the two machines reach
it from different directions - the authority from the upgrade itself, a client from the
snapshot noticing the type changed - and neither should have to know what is listening.

**`UnitAbility.is_local_only()`** - the one thing an ability can be that is NOT a
command. A build ghost, the selection and the range overlay never left the machine already;
this makes that a property an ability can declare, so the builder's grid toggle and every
tower's Show Ranges get a card slot and a hotkey without asking a server that has no grid,
no camera and no selection what it thinks. False by default,
deliberately: an ability that forgets to answer ends up validated by the server, which is the
safe way round.

**Replicated setters, and why they are separate from the ordinary ones:**

```gdscript
Unit.set_replicated_health(value)                  # never kills; removal comes from absence
Unit.adopt(id, player_id, area, world_pos)         # setup(), but with the id handed IN
PlayerState.set_replicated(gold, income, lives)    # no spend/gain rules re-run
SendBuilding.set_replicated_stock(stats, count)
Building.set_replicated_phase(building, selling, upgrading)
AttackComponent.set_prioritize_air(value)          # which creep a tower picks IS simulation
AttackComponent.set_fighting_on_command(value)     # the builder's swing, which it cannot infer
```
Each exists because the ordinary method ENFORCES something - you cannot spend what you do not
have, a life must come from somebody, zero health means death - and a value that already went
through those rules on the server must not go through them twice.

**Per-player state and the ring** are both on `PlayerManager`:

```gdscript
PlayerManager.register_area(area) / area_for(slot)
PlayerManager.sends_into(slot) -> int          # right neighbour, skipping the eliminated
PlayerManager.next_maze_after(defender, sender) -> int   # where a leaked creep goes
PlayerManager.erase_player(slot)               # D14, server side
PlayerManager.areas() -> Array[PlayerArea]     # for the things that act on all of them
PlayerState.steal_life_from(victim) -> bool    # one life moves, or nothing does
```

**`MatchStart.leave_match()`** - says goodbye, waits one poll cycle, THEN hangs up. Call this
rather than `Net.leave()` from inside a match, or the goodbye is thrown away with the socket
and the server holds the full grace period for a player who was being polite.

**What is deliberately NOT here** - prediction, phase B replication, projectile
replication, an end screen - is §13, with the reason for each.

### The one remaining stub

Everything else in the menus is real: `set_lobbies()`, `refresh()`, `_on_join_pressed()` and
`LobbyRoom.show_lobby()` are all driven by server pushes, and the list is sent unprompted, so
`refresh()` is a repaint rather than a request. One thing is still a stub, on purpose, and one line that used to be here is no longer one:

- `LobbyIdentity.display_name()` — now a name the player TYPED, kept in `UserSettings` and
  asked for by the browser before it will open a connection (§2, and `game_rules.md` under
  The player's name). The OS user name is only what the prompt suggests. Still one line to
  change when a real identity arrives (Steam, §10), and the SERVER still treats whatever it
  says as untrusted — `sanitise()` runs on arrival and the peer id remains the identity.
- `MenuNavigation.pending_lobby` — kept only so `lobby_room.tscn` can be run on its own from
  the editor. The live path reads `Lobby.current()` instead.

---

### Running a server and clients on one PC

**The setup you actually want is in `server.md`**: a headless server in a terminal, plus
client instances from the editor. F5 restarts every editor instance, so a server tagged
inside the editor dies and restarts every time you iterate on the client, while a terminal
server just keeps running. `CLAUDE.md` covers the scripted headless loop for anything that
has to be repeatable.

What follows is the editor-tagged alternative, kept because the mechanism behind it is worth
knowing and is not documented anywhere obvious.

**No, you do not need to export a build.** Godot runs as many instances of the project as
you like straight from the editor, each with its own command line and its own feature tags.

**Debug → Customize Run Instances…**

- Tick *Enable Multiple Instances* and pick a count.
- Each instance gets its own **Launch Arguments** and its own **Feature Tags**.
- Press Run (F5) and they all start together.

The feature tags are the part that matters here, because `OS.has_feature("dedicated_server")`
is exactly what `Boot` keys on. Give instance 1 the `dedicated_server`
tag and it boots as the server; leave the others alone and they boot as clients. **The same
line of code selects client or server in the editor and in a real exported build**, with no
`if OS.is_debug_build()` special case anywhere.

**Setting the tag is two clicks, and missing them is the obvious first mistake.** Ticking
*Enable Multiple Instances* is NOT enough - it gives you N identical clients. Each instance's
tag field has its own **override checkbox**, and the tag is ignored until it is ticked:

> Debug → Customize Run Instances… → select **Instance 1** → tick **Override Main Feature
> Tags** → type `dedicated_server` in that instance's Feature Tags field.

**How the tag actually reaches the game, which is worth knowing:** not as a command-line
flag - there is no such engine flag, verified against the binary. The editor passes it to the
child process in the environment variable **`GODOT_EDITOR_CUSTOM_FEATURES`**, and the engine
folds it into its custom features so `OS.has_feature()` answers true. Proven by launching the
project with only that variable set and no arguments at all: it booted as the server with
`Feature tag dedicated_server: true`.

---

## 3. What the game needs from the network

- **2–12 players, free for all, no teams** (`game_rules.md`). Prototype target is 1v1.
- **Very few player commands.** Build, sell, send, move, attack. Handfuls per second.
- **Very many simulated units.** Thousands across 12 lanes in the bad case.
- **Lanes are independent.** A player's creeps only affect that player's lane. Cross-player
  events are *sending* a creep, gold/income, and life loss.
- **PC only.** Single platform.
- **Rating must be trustworthy** — the reason for D2.

---

## 4. Why server-authoritative, and what it costs

Rejected alternatives, recorded so the reasoning is not relitigated:

| Rejected | Why not |
| --- | --- |
| **Deterministic lockstep** | Genre-correct, and this codebase suits it unusually well. But no client can be trusted to report a result, and a desync is unrecoverable. Its bandwidth advantage is largely recovered anyway by §5.4. |
| **Host-authoritative** | Fastest to a playable 1v1, but the host has zero latency, can edit the simulation, and their leaving ends the match. Unusable for ranked. |
| **Per-lane authority** | Cheapest by far, and the lanes really are independent, but it trusts the client completely. |

**The cost being accepted:** more work before the first networked match, a server to run and
pay for, and input latency that prediction has to hide. That is the trade for a result the
player cannot forge.

---

## 5. Architecture

### 5.1 Two servers, two different jobs

Separate, and must not be conflated:

1. **Game server** — simulates one match. Authoritative over gold, towers, creeps, damage,
   lives. Headless Godot, GDScript, *the same code the client runs*. Built now.
2. **Meta backend** — accounts, elo, match history, friends. Any language. Deferred (D7),
   and this is where prior WebSocket/HTTP experience transfers directly.

Conflating them makes the match simulation depend on a database, and the account service
depend on the game engine.

### 5.2 Can a server be written in Godot / GDScript? Yes

Godot 4 exports a **dedicated server** build: an export preset carrying the
`dedicated_server` feature tag, run with `--headless`. No window, no rendering, no audio,
running ordinary GDScript. The export preset can strip visual resources so the server build
does not ship meshes and textures.

**Why that is the right choice here, not merely an acceptable one:** the server and the
client run *the same simulation source*. There is exactly one implementation of how a tower
picks a target and how much damage it deals. The alternative — a server in Node, Go or
ASP.NET — means reimplementing the entire tower-defence simulation in a second language and
keeping two copies behaviourally identical forever. For a simulation-heavy game that is a
large and permanent tax. It is perfectly fine for the *meta backend* in §5.1, which
contains no simulation.

C# is available in Godot, but the simulation is already GDScript and there is no reason to
split languages. Keep GDScript.

**Practical shape:** a second entry scene, e.g. `Scenes/Server/server_main.tscn`, selected
at boot by `OS.has_feature("dedicated_server")`. It never loads the menus, the camera or
the HUD.

### 5.3 The command / state loop

```
CLIENT                                  SERVER
──────                                  ──────
player clicks                    ─┐
  ↓                               │
intent: {ability, unit, target}   ├──▶  validate: ownership, gold, stock,
  ↓                               │      placement legality, maze not blocked
predict locally (optional)       ─┘        ↓
  ↓                                      apply to the authoritative sim
render                           ◀──────  broadcast: state + events
  ↓
reconcile against the server
```

**The client sends intent, never state.** It never says "I now have 300 gold" or "this creep
is at X". It says "I pressed build tower here", and the server decides.

That maps almost exactly onto what already exists: `UnitAbility.execute(unit, target)` is
the single chokepoint every player order already funnels through. A command is close
to `{ability_id, unit_id, target}`.

**LTW-specific validation the server owns:** gold and income, creep stock, tower placement
legality, and the maze-blocking rule from `game_rules.md` — a player must not fully wall off
their lane. That one in particular must never be client-side.

### 5.4 Bandwidth: how thousands of creeps stay affordable

This was the one real objection to replication, so the plan is written down rather than
discovered later. Four mechanisms, in order of importance:

1. **Spawn-and-extrapolate.** Do not stream creep positions. Replicate the *spawn event*
   (`type, id, spawn point, tick`) and let every client run the same movement code locally.
   Creep movement is a flow field over a static maze, and the maze only changes when a tower
   is built or sold — which is itself a replicated command. So clients stay in step for long
   stretches, and the server corrects only on events (damage, death, re-route) or on a slow
   heartbeat.
   This is the important one: it recovers most of lockstep's bandwidth profile *while
   keeping server authority*, because the client simulation is a prediction the server may
   overrule rather than a source of truth.
2. **Interest management by lane.** A client needs full detail on its own lane. For other
   players it needs a summary — lives, creep count, income — unless actively spectating.
   This is what makes 12 players affordable; in a 1v1 it barely matters.
3. **Quantisation.** Positions as 16-bit fixed point over the lane's known bounds, not three
   32-bit floats.
4. **Events, not state, for discrete things.** Deaths, damage, life loss and gold changes are
   messages, not fields polled every tick.

**One of these is already here, for one channel.** A unit's STATUS EFFECTS are sent only
for the units clients have said they are looking at: a client names the unit its panel is
showing (`Replication.request_watch`), the server keeps a unit id per peer, and the snapshot
carries the effects of those units alone. That is mechanism 2 in miniature, and it earns the
exception phase A otherwise refuses - a creep in a maze carries several effect records and a
maze carries hundreds of creeps, against at most one unit per player that anybody can be
reading. The client half is dumb in the usual way: what arrived IS the answer, so a unit that
drops off the list has nothing on it any more.

A TOWER rides this channel too, which is worth saying because the interest management has a
consequence there that it does not have for a creep: a tower nobody is looking at answers its
own bare numbers on a client, so its barrels turn on an unbuffed reach while the server shoots
on the real one. Presentation only - the server is the only machine that fires - and it is the
same trade the creep armour line has always made. The complete version arrives with phase B,
when the server names what each tower fired at anyway.

**Consequence worth noting:** because the client runs the same simulation as a prediction,
the simulation's freedom from physics and unseeded randomness keeps its value. The difference from lockstep is that drift
is *corrected* rather than fatal, so the standard is "close enough", not bit-exact. Much
cheaper to hold.

### 5.5 Fixed tick and prediction

**Built.** The simulation runs at 20 Hz (D11).

**The engine's physics tick IS the simulation tick.** Every gameplay loop lives in
`_physics_process`, nothing gameplay-relevant happens on a render frame, and
`Engine.get_physics_frames()` is the tick counter for free — `MatchSession.tick()` offsets
it from the start of the match. There is no second clock to keep in step.

Rendering uses Godot's own physics interpolation, and it is **not optional at this rate**:
the builder covers 0.30 world units per tick, which is visibly stepped raw and smooth
interpolated. Confirmed in play.

How far prediction goes is open. The cheap first version predicts nothing and shows a build
a few tens of milliseconds late, which for a tower defence — where the player places
buildings rather than aiming a rifle — is far more tolerable than in a shooter. Add
prediction where the delay turns out to be felt.

### 5.6 Changing the tick rate is not a free knob

Recorded because it cost a long debugging session, and because it will recur if the rate is
ever changed again.

Going from 60 Hz to 20 Hz tripled the distance a unit covers in one tick, and that broke
creep pathing in a way that looked like a *rendering* fault. A creep advances to its next
waypoint only once it is within `arrive_threshold` of it. Cover more than twice that
threshold in a single tick and it overshoots, turns round, overshoots back, and oscillates
across the waypoint indefinitely:

| creep | step per tick | half-step | vs threshold 0.05 |
| --- | --- | --- | --- |
| everything at speed 2.0 | 0.100 | 0.050 | band empty — fine |
| Spider at speed 2.2 | 0.110 | 0.055 | **trapped band (0.05, 0.06)** |

Only the Spider was faster than the rest, so only the Spider stuttered — which made it look
like a Spider bug rather than a tick-rate one. Fixed by making the arrival test never
smaller than one tick's travel (`Creep._step_reach`), closing the band at every speed and
every tick rate so `move_speed` stays freely tunable.

**The general rule: any gameplay constant expressed as a distance has to be checked against
the distance one tick covers.** Arrival thresholds, separation limits, aura radii and hit
ranges were all tuned when a tick was 1/60 s. `MobileUnit` was already safe because it
clamps its step to the remaining distance; `Creep` was not.

### 5.7 Where the server runs, and how code reaches it (D30)

The dedicated server runs on a rented Linux machine. D4 said that "runs on your machine" and
"runs in a datacenter" differ only by an address, and that turned out to be exactly true:
nothing in the code changed when it moved, and the one edit was a line in `NetworkConfig`.

**What is on that machine.** Three things, and deliberately no more:

- a git **clone** of this repository - complete and independent, not a link to anything
- a Linux build of Godot, pinned to the same version the editor runs
- a `systemd` unit running the same `--headless -- --server` command `run_server.ps1` runs

There is no separate server codebase, no database and no persistent state. That is D3 seen from
the other end: the server IS this project, booted through `server_main` instead of the menu. A
match lives in memory and is gone when it ends, which is also why there is nothing to back up.

**A push does not deploy.** This is the part that surprises anyone expecting a web backend.
Committing and pushing changes nothing about what the server is running; it keeps serving the
commit it already has until somebody runs the deploy. The chain is:

```
editor ──commit──▶ local ──push──▶ origin ──deploy pulls──▶ server clone ──restart──▶ running
```

Two consequences worth holding on to:

- **An uncommitted change cannot reach the server**, however many times it is deployed, because
  the path runs through a commit. A client running local edits against a server without them is
  the ordinary cause of `Initial world DIFFERS from the server` - a version gap, not a
  determinism bug.
- **Git is a middleman used once per deploy, not a live dependency.** The clone is complete, so
  matches keep running whether or not the host is reachable.

**What a deploy does**, in order: fetch, hard reset to the remote branch, re-import, restart.
The reset is deliberate rather than a pull - the checkout is a deploy target that nobody edits
by hand, so the remote always wins and no conflict can ever stop a deploy half way. The
re-import is not optional: a clean checkout has no imported-asset cache and no script class
table, which on a server shows up as the service crash-looping rather than as an error anyone
reads.

**Restarting ends any match in progress.** One process holds the lobby and the match (D19) and
every bit of match state is in memory, so deploying during a playtest disconnects everybody at
once. There is no drain-and-swap and no reconnect (D13) to soften it. Deploy between sessions.

**The developer no longer plays at zero latency**, which D18 named as the one thing a local
server hides. Everyone including the developer now reaches the simulation over a real network,
so an ordering or timing bug that only appears under latency appears for the person who can fix
it rather than only for testers.

**Not built, and the honest gap**: no accounts, no authentication and no persistence, so anyone
holding the address can connect and nothing survives a match. That is D7 deferred, and it
becomes a real question the day a build is public rather than handed to people by name.

**How it is driven** - deploy, read the log, restart - is `server.md`. This section is what it
is; that file is which commands to type.

---

## 6. Transport — ENet (D5)

`ENetMultiplayerPeer`, built into Godot. Clients connect out to `server_address:port`.

**Why not WebSockets**, given that is the familiar tool: WebSockets are TCP, so one lost
packet stalls everything queued behind it (head-of-line blocking) and a 20 Hz state stream
arrives as a stutter. ENet offers *unreliable* channels, where a dropped state packet is
simply superseded by the next one 50 ms later, plus reliable channels for commands and
events — both over one connection. Godot makes ENet no harder to use than WebSockets.

WebSockets stay the right choice later for the **meta backend** (§5.1): proxy-friendly,
browser-friendly, request/response shaped.

**A dedicated server removes the NAT problem.** Clients make outbound connections to a known
address, so there is no port forwarding on the player's side, no NAT punch-through and no
relay. This is the biggest simplification D2 buys, and it is why Steam P2P is no longer
needed as transport (D8).

Later, **Steam Datagram Relay** can front the server to hide its IP and absorb DDoS. That
needs a real appid and is not required to play.

---

## 7. Serialisation, and PickleGD (D9)

**PickleGD is not a transport.** It sits above whichever transport is chosen and answers a
different question: how a custom GDScript class becomes bytes. It does not compete with §6;
the two would be used together. (MIT, targets Godot 4.7.1, and states that unpickling does
not execute arbitrary code.)

Assessment, split by path:

- **Cold path — good fit.** Lobby info, match setup, player profiles, save data. Infrequent,
  the schema will churn, and hand-writing serialisers for them is tedious and bug-prone.
  `LobbyInfo` needs exactly this: Godot cannot send a custom `Resource` over RPC safely, so
  it has to become a `Dictionary` or a byte array first.
- **Hot path — wrong fit.** The per-tick state stream is where the entire bandwidth budget
  lives (§5.4). A reflective serialiser writes field names and type tags; a hand-packed
  format writes only the bits we chose. This is exactly where generic convenience is paid
  for in bytes, every tick, forever.
- **Security.** The server must never trust client bytes. Client→server commands are the only
  untrusted direction, and they are tiny and fixed-shape, so a hand-written parser that
  reflects on nothing is both safer and smaller. PickleGD's class registry is the right
  property to have, but it is not a substitute for the server range-checking every value.

**Verdict:** the link is enough — no need to install it. It is a good tool aimed at a problem
we do not have yet, and it costs nothing to adopt later once there is a real wire format to
measure it against. Revisit when the first cold-path payload is written.

---

## 8. Lobbies (D6)

With a server, lobbies belong on it. That removes the need for Steam lobbies entirely and
means the lobby list is identical on every machine and testable with Steam switched off.

Shape:

- The server holds the lobby registry: create, list, join, leave, start.
- `LobbyBrowser.refresh()` becomes a request to it; `set_lobbies()` renders the reply.
- The lobby list is small and infrequent — a plain reliable channel, no optimisation needed.
- Starting a match hands the lobby's player list to a game-server instance, which is where
  the `MatchSetup` comes from.

Decided (D19): one process does both for now. Splitting later is an address change.

### 8.1 Lobby rules

Rules the lobby itself obeys, as opposed to the match.

**The start countdown (D24) is built**, in `LobbyService`, and behaves exactly as written
below - every branch verified with three headless clients. Pressing Start does not start the
match:

1. The host presses **Start**. The lobby locks: **nobody may join for the next 5 seconds**,
   and the browser must show it as unjoinable rather than merely full.
2. A **5 second countdown** runs, and **every player in the lobby sees it** - not just the
   host. It is the server's countdown, announced to the room, so everyone sees the same
   number and nobody can start early by lying about their own clock.
3. It can be stopped two ways, and both put the lobby straight back to ordinary and open:
   - **Any player leaving cancels it.** Including a joiner, not only the host.
   - **The host may cancel it deliberately**, at any point before it fires. So Start becomes
	 **Cancel** for those five seconds; it is the same button, because there is nothing else
	 the host can usefully do while it runs.
4. If it runs out, the `MatchStart` handshake begins.

A cancelled countdown is not a state to recover from - it simply never happened, and the host
may press Start again immediately. That is literally what the code does: the flag clears, the
lobby is pushed again, and nothing remembers.

Why it earns its keep: it makes *who is in this match* final before the handshake rather than
during it. Without it, somebody leaving between "Start" and "everyone loaded" is a case the
loading screen has to handle; with it, that case mostly stops existing, because the only way
to leave is to cancel the whole thing first.

The host leaving during the countdown needs no rule of its own - the lobby closes (D23).

**What the browser shows while a countdown runs** - decided, and already built. The row reads
**"Starting..."** in the accent colour and is disabled and dimmed, exactly as a full or
running lobby is; when the countdown is cancelled it reverts to an ordinary open row.

Both halves exist now. `LobbyInfo.is_starting` is a flag separate from `is_in_progress`,
because they are different things - a countdown has NOT begun a match and can still be
cancelled back to nothing - and `is_joinable()` refuses both, and `request_join` refuses a
countdown with a sentence of its own. Verified with three lobbies side by side:

```
Open one       | Open         | disabled=false | alpha=1.00
Counting down  | Starting...  | disabled=true  | alpha=0.55
Running        | In progress  | disabled=true  | alpha=0.55
```

**Player colours.** **Built.** Every player has one, chosen from a dropdown on their own row,
because anything showing several players at once needs them told apart at a glance. What the
RULE is is `game_rules.md` under Player colours; what follows is where it lives.

- A colour is per-match identity, so it rides on `MatchPlayer.color_index` next to `slot` and
  `network_id` and travels in the same `to_dict()`. It is an INDEX into the palette rather
  than a `Color`, so what the wire carries cannot disagree with what a machine draws.
- **It is not the slot, and that is the whole point of storing it.** A slot is dealt out by
  the server and re-dealt by `renumber_slots()` and by the lane shuffle; a colour is chosen
  and kept. Anything that indexed the palette by slot drew one player in another's colour the
  moment the lanes were dealt - which is exactly what the old stand-in did.
- The DROPDOWN lists coloured squares rather than colour names, because a colour is a thing
  to recognise rather than to read. The name rides along as each item's tooltip, so it is
  still sayable out loud. The squares are built once from the palette and cached statically -
  Godot has no solid-colour texture and an `OptionButton` item wants a `Texture2D`, and a PNG
  per entry would be twelve assets to redraw the moment somebody edits one hue.
- **Unique within a lobby, so the server assigns and validates.** `LobbyInfo.add_member` hands
  out `first_free_color()` on join, and `request_color` refuses one somebody else holds -
  exactly as it refuses a full lobby, and for the same reason the settings take a round trip:
  the dropdown draws what came BACK, so a refused pick snaps to what that player really has.
  Anybody may change their OWN colour, unlike the settings, which are the host's alone.
- **A NAME is changed the same way and by the same rpc.** `register_player` is sent on
  arrival and again on a rename, because the whole of it is "this is what I am called now" -
  so the second overwrites the first and there is no second path to keep in step. What it
  costs is that a player already sitting in a lobby has to have that roster corrected too,
  since their `MatchPlayer` carries the name every other client is drawing.
- Leaving frees a colour and leaves a GAP rather than renumbering the ones below it, which is
  what makes "picking a colour never moves you in the lobby" true in both directions.
- The palette is content and lives on `PresentationConfig` in a config `.tres`. The dedicated
  server wires it too, which it did not have to before: it is the machine that decides which
  colours exist and whether a request names one.
- **The one place slot and colour meet is `MatchSession.color_index_for`**, which answers what
  a slot chose and falls back to slot order when nothing did - a single player run, or a bare
  test scene. Every reader goes through it, so the minimap and an anonymous match's player
  table cannot disagree.
- NOT BUILT: teams, and any use of a colour on a unit in the world. A colour reaches the
  minimap and the player table and nothing else.

### 8.2 Match settings

**Built.** The host chooses the rules of a match in the lobby, before anybody loads: what
everybody starts with, which creeps are in it, whether the lanes are shuffled, how the
opening technology is dealt, and whether players are named or only coloured. What each of
them MEANS is `game_rules.md` under Match settings; what follows is where it lives.

- `MatchSettings` is a flat, serialisable Resource, next to `MatchPlayer` and for the same
  reason: it rides on a `LobbyInfo` while the lobby is open and on the `MatchSetup` once the
  match begins, and both travel as Dictionaries.
- It is **not a second GameConfig.** `MatchSettings.defaults()` is the one place the two
  meet: a fresh lobby copies the numbers out of `game_config.tres` and the host edits the
  copy. Editing the file still changes what every new match starts from; a match that was
  started carries what was agreed.
- The host's panel calls `Lobby.set_settings()`, which is one request carrying the WHOLE
  block rather than one changed field - ten values on a cold path, and the server never has
  to merge two half-states. The server checks the sender hosts the lobby, refuses it once the
  countdown is running, runs `sanitise()` and pushes the lobby back. So the host's own edit
  takes the same round trip everybody else's copy does, and a clamped value is drawn as the
  clamped one rather than as what was typed.
- `sanitise()` is where the RANKED LOCK is enforced, not the greyed-out controls: a ranked
  block is put back onto the defaults whatever arrived, keeping only the technology mode. The
  clamps beside it are the ordinary distrust, bounded by `MenuConfig` - a lobby rule rather
  than a match one.
- The lane shuffle happens in `LobbyInfo.to_match_setup`, on a generator seeded from the
  match seed, and every machine is TOLD the result. Nothing derives it.

**The technology draft is the one thing here that touches the simulation**, and it is worth
knowing how:

- `StartingTech` is a node in both match scenes, next to `TechManager`, reached through
  `References`. Not an autoload: it receives no rpc of its own, because a draft pick is an
  ordinary player order and travels through `Commands` like a Research Center press.
- **The authority rolls the three Ultimates and clients are told**, in the snapshot, under
  its own key. Both machines COULD derive the same three from the seed and that is exactly
  the second simulation 3.4 forbids - it would agree until it did not, and the symptom would
  be a client drawing three buttons the server refuses two of.
- **Holding the world still is `SceneTree.paused`**, set by `MatchSession.set_paused` on both
  machines - the authority from its own draft, a client from the snapshot that says who is
  left. Every gameplay loop in the project lives in `_physics_process`, so the engine's own
  pause switches all of them off at once and nothing new has to remember to ask.
  - what must keep running says so for itself: `Net`, `Lobby`, `MatchStart`, `Commands` and
    `Replication` all set `PROCESS_MODE_ALWAYS`, because the order that ENDS the pause and
    the snapshot that announces it both travel that way. On the HUD only the draft screen and
    the menu that lets a player leave do, which is what stops a held player from building or
    sending their way past the choice.
  - the MATCH CLOCK is given back what the hold took. The tick counter is the physics frame
    and the engine goes on counting those while nothing is processing them, so without that
    correction a ten second draft would be ten seconds every creep unlock had silently
    already served.
- A player who drops during the draft stops being waited for (D13), so one crashed client
  cannot hold everybody else for the rest of the match.

---

## 9. Backend / rating — deferred (D7)

Not built. What must stay true so it is not painful later:

- **Never trust a client's report of a result.** With D2 the server already computes the
  outcome, so the honest path is free — the result comes from the game server, not a player.
- Keep a **stable player identity** distinct from a display name. `LobbyIdentity` is the one
  place answering "who am I", so there is one line to change. Steam auth tickets (§10) are
  the likely source.
- Have the game server produce a **match record** (players, result, duration) even before
  anything stores it.

---

## 10. Steam — what it is actually for (D8)

The game ships on Steam and nowhere else. With a dedicated server Steam is **not** the
transport, which was the main thing unclear. It provides:

- **Distribution.** The store page and the client build. The whole reason it is here.
- **Identity.** `GetAuthSessionTicket` on the client, validated server-side. How the future
  backend (§9) learns who a player is without us building a login system.
- **Friends, invites, rich presence, overlay.** Nice to have; the lobby list does not depend
  on them because of D6.
- **Steam Datagram Relay**, later, to front the server (§6).

**Sequencing consequence:** none of this is needed to build or test the server. Two machines
on a LAN, or two clients against localhost, exercise the whole architecture with Steam
switched off. Steam integration is a later, separable step — a much better position than the
Steam-P2P plan, where Steam was load-bearing from day one.

The app-480 (Spacewar) debug build still works for testing identity and the overlay when we
get there. `project.godot` is already prepared but inert (`app_id=0`,
`initialize_on_startup=false`), and `addons/godotsteam/` is a GDExtension that loads on its
own.

---

## 11. Settled questions, and the detail behind them

All of these are answered. Kept because the reasoning is worth having when the code gets
written, and because a few small details underneath are still open.

### 11.1 Disconnects (D13, D14)

**No reconnect. Out is out.** And a disconnect **erases that player's maze**; the match
carries on while their lives drain away, and they are eliminated the ordinary way.

The elegance of this is that it invents nothing. It reuses three rules that
`game_rules.md` already defines:

- With no maze, every creep in that lane walks straight to the end.
- Each one that leaks **steals a life for its owner** — the disconnected player's left
  neighbour, the one who sends into that lane.
- When their lives reach zero they are **eliminated**, and **the ring closes** by skipping
  them, exactly as it would for a player who simply lost.

So the leaver's remaining lives are not thrown away, they are handed to whoever was
attacking them. No special elimination path, no separate "player left" state to reconcile
with the win condition. The one genuinely new behaviour is erasing the maze.

Details still open, none of them blocking:

- **Nothing forces the drain.** Lives only leave through leaks, so a leaver whose neighbour
  happens not to be sending sits at full lives until they do. In practice someone is
  always sending, but it is worth knowing this is the mechanism rather than a timer.
- **The leaver's own creeps keep walking** in the next lane along, and a leak would steal a
  life *for* a player who is on their way out. Harmless, and simplest left alone.
- **A grace period is not a reconnect.** D13 forbids rejoining; it does not require
  declaring someone gone the instant a packet is late. A short hold — around 10 s — keeps a
  brief network hiccup from costing a ranked game. A deliberate Leave should skip the hold.
  **Measured: ENet itself takes about 5.6 s** to report a client that was
  hard-killed on localhost, with no cooperation from the dying process. So roughly five
  seconds of grace already exist for free, and any hold we add is *on top* of that, not
  instead of it. **A deliberate Leave was then measured at 0.13 s** - 43x faster - because
  leaving closes the peer on the way out, so the server hears a goodbye rather than waiting
  for silence. That is what makes "a deliberate Leave skips the hold" implementable rather than
  merely desirable: the two cases are already distinguishable by how fast they arrive.
- **Whether the towers are refunded, recycled or simply deleted** when the maze is erased.
  Deletion is simplest and nobody is left to receive gold.

### 11.2 The loading screen timeout (D15)

Wait **60 seconds**. Then start without whoever has not reported ready, provided at least
`min_players` are. **No player area spawns for a missing player** — they were never in the
match, rather than being in it and immediately dead.

Falls out of the design: `MatchSetup` carries the player list, so the server
simply builds it from the players who made it. Nothing downstream needs to know that
somebody was dropped.

One consequence worth remembering, because it will look like a bug otherwise:
**starting lives depend on the player count** (`game_rules.md`, Life steal). A four-player
lobby that starts as three therefore gives everyone MORE lives than four would have. That is
correct — the pool is shared — but the lobby will have shown one number and the match another.

### 11.3 One process per match (D16)

Yes, and more scalable for a reason worth being precise about.

It is not mainly about memory — a Godot process has real baseline cost, and a shared process
would fit more matches per gigabyte. It is about **cores**. Godot runs its simulation on one
thread, so a single process can never use more than one core's worth of matches however
cleverly it schedules them. One process per match is the only shape that uses a multi-core
server at all.

On top of that: a crash takes one match rather than all of them, memory cannot leak between
matches, and each match gets the engine's own `_physics_process` clock as its simulation
tick (§5.5) instead of a hand-rolled scheduler stepping every match in turn.

Cost is startup time and baseline memory per match, both of which the dedicated-server
export reduces by stripping visual resources.

Still open: whether the lobby lives in its own process or shares one with a match. For the
prototype, one process doing both is simplest, and splitting later is an address change.

### 11.4 Feedback now, prediction later (D17)

**Prediction** is the client guessing the server's answer before it arrives — showing the
tower the instant you click, assuming the server will agree. When it disagrees, the client
has to take it back, and that undo is what looks glitchy.

**Feedback** is confirming the input landed without claiming the outcome: the click, a ghost
where the tower will go, the gold greying out. It cannot ever be wrong.

For a tower defence, 60–100 ms on placing a building is close to imperceptible — a shooter
could not tolerate that on aim, but nothing here is aimed. So the first version ships
feedback only, and prediction is revisited if the delay turns out to be felt. The builder's
movement is the likeliest candidate, being the one continuous action a player performs.

Not to be confused with the creep extrapolation in §5.4, which is the client running the
*simulation* ahead of the server for bandwidth reasons. That is needed regardless.

### 11.5 Where the dev server runs (D18, superseded by D30)

Originally: locally in the office, on the user's own machine for the first tests, moving later
if needed. **It has since moved** - the public server runs on a rented machine, see §5.7. The
prediction held exactly: the address is one line in `NetworkConfig` and nothing about the code
changed when it moved.

A local server is still the right thing for developing against, and `run_server.ps1` still
starts one. What changed is which server a handed-out build reaches.

The one thing a local server hides is **latency**: at 0 ms, every ordering and timing bug
stays invisible and then appears for real players at 80 ms. Worth injecting artificial delay
and packet loss before trusting a build — on Windows a tool such as *clumsy* can do this to
a local connection.

### 11.6 Answered elsewhere

- ~~Simulation tick rate~~ — 20 Hz, D11 and §5.5.
- ~~The session autoload~~ — D10.
- ~~How a command names an ability~~ — D12.

---

## 12. The reference template — adopt / avoid

`ReferenceFilesFromOtherProjects/SteamLobbyTemplate/` (ViMayer, MIT), quarantined behind a
`.gdignore` so Godot does not parse it. See `WHAT_THIS_IS.md` there.

Its architecture is **peer-to-peer host-authority**, which D2 rejects, so it is less directly
applicable than it first looked. What survives:

- **The same API over two transports.** Both host paths end with a `MultiplayerPeer` assigned
  to `multiplayer.multiplayer_peer`, so RPCs above it are transport-agnostic.
- **An error enum returned from every entry point**, rather than bare `bool`.
- **`to_dict()` / `from_dict()` for sending a resource over RPC** — the problem §7 covers.
- **One object owning the session**, with the rest of the game listening to its signals. Ours
  would be a `References`-held node, not an autoload.

Confirmed bugs — do not copy:

| Where | Problem |
| --- | --- |
| `host_local_lobby()` | Sets `is_busy = true` and never clears it when `create_server` fails. One failed host bricks the object; every later call returns `CURRENTLY_BUSY`. |
| `join_address()` | Guards on `is_busy` but never sets it. The guard does nothing. |
| `_process_steam_p2p_packets()` | Reads one packet per frame, channel 0 only, while `project.godot` declares 4 channels. |
| `DataPayload._get_packet_data()` | `str()`-ifies every value, so ints and bools arrive as strings. |
| Steam callbacks | `Steam.run_callbacks()` appears **nowhere**. If callbacks are not embedded, `lobby_created` never fires and there is no error. Verify first if Steam is ever wired up. |

Style throughout violates `CLAUDE.md` (`:=`, `and`/`or`, `@onready`, `$` paths, constants in
scripts). Treat as documentation, write our own.

---

---

## 13. What is deliberately not built

Not oversights. Each one is a choice with a reason, and none is blocking.

| | What | Why not yet |
| --- | --- | --- |
| **Replication phase B** | Spawn-and-extrapolate, interest management, quantisation - all of §5.4. The server currently sends the whole world, every unit, twenty times a second. | Phase A shipped first on purpose so this is measured rather than guessed at. Fine for a 1v1 on a LAN, nowhere near 12 players. This is the next thing to do when it is wanted. |
| **Client-side prediction** | An order takes a full round trip before anything moves (D17). | Nothing to do until somebody plays over a real connection: measure before optimising. §11.4 covers why a tower defence tolerates this and a shooter would not. |
| **Projectile replication** | Projectiles are re-simulated locally as presentation; only the server applies their damage. | Cheap and correct as it stands. |
| **Target acquisition on the client** | `AttackComponent` asks `is_authority()` nowhere, so every client runs the full target search for every tower in every lane, exactly as the server does. Only the damage is gated, in `Unit.take_damage` - a client's answer decides where its barrels point and where it spawns a shot, and nothing else. | It falls inside the presentation exception the row above uses, and for the same reason: a client has to know what a tower is shooting to draw it shooting. What is DIFFERENT is the price. Flying a projectile is a few vectors; acquiring a target is a scan of the whole lane, per tower, and it is the largest cost in a loaded tick on either machine. So the client pays a server's simulation bill to draw barrels, most of them in lanes nobody is looking at. The fix is not a gate on its own - a gated client would draw nothing - but the server naming what each tower fired at, which is the same spawn-event shape phase B wants and should land with it. |
| **Rubble replication** | A destroyed tower blocks its cells for a few seconds, and only the authority knows a tower was destroyed rather than sold - the snapshot says a unit is gone, never why. So a client's build ghost can read green over a cell the server refuses for those seconds. | It is a handful of cells for a handful of seconds, and the server refuses the placement anyway, so the cost is one misleading ghost rather than a wrong world. A phase B spawn/despawn event carries the reason for free. |
| **An end screen** | The match decides itself and stops; players leave through the in-game menu. | Deliberately the smallest thing that works. |
| **Player colours on the units themselves** | A colour reaches the minimap and the player table. Nothing in the 3D world is tinted by it, so two players' towers look identical in a lane. | The colour is chosen, replicated and read through one call (§8.1), so this is a materials question rather than a networking one - and it collides with the tower visual language, which spends colour on the ELEMENTS. `game_rules.md` under Presentation is where that has to be settled first. |
| **More than one match per process** | One process hosts one match, refuses a second with a sentence, and frees itself when that one empties - D19 doing its job until D16 splits them. | Splitting is an address change, so it is safe to defer. |
