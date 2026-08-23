# Multiplayer

Working reference for the multiplayer build. Rules live in `game_rules.md`, conventions in
`CLAUDE.md`. This file holds the **decisions**, the architecture they imply, and the order
of work. Read it before writing networking code.

**Status, 2026-08-23.** 26 decisions, all made, §1. **Phase 0 and Milestones 1-3 are
complete**, apart from two steps the roadmap itself defers: 3.3 (spawn-and-extrapolate) and
3.7 (latency feel). Both are optimisations, and both now have something real to be measured
against rather than guessed at.

**Two players can play each other, start to finish.** A server hosts the lobby list; the host
presses Start and everyone watches the same five second countdown; all three machines - both
clients and the headless server - build the same match from the same seed, proven by
checksum rather than by inspection. From there orders travel to the server as INTENT, the
server is the only machine that simulates, and both clients draw what it sends. Towers,
creeps, gold, income, stock, lives, value and placement all replicate. A leak steals a life,
a disconnect erases the leaver's maze, and the last player standing ends the match.

**What that costs, and it is deliberate:** the client predicts nothing (D17), so an order
takes a round trip before anything moves, and the server sends the WHOLE world twenty times a
second. Both are phase A choices. The first is 3.7's problem, the second is 3.3's.

**Where to start reading**, whichever of these you need:

| Looking for | Go to |
| --- | --- |
| What is decided and must not be re-opened | §1, D1-D26 |
| The API surface, with real checked signatures | §2 → *What Milestone 3 left you to build on* |
| How the whole thing is meant to work | §5 |
| What is genuinely still open | §1 → *Still open* |
| What each step actually took, and what it cost | §12 |
| Starting and stopping the server | `server.md`, not this file |

**Next, when it is wanted: 3.3.** Nothing is blocked on it.

---

## 1. Decisions

| # | Decision | Date | Notes |
| --- | --- | --- | --- |
| D1 | **No physics engine, anywhere.** All gameplay is plain maths. | 2026-08-21 | Now a hard rule in `CLAUDE.md`. Already true in the current code — see §11. |
| D2 | **Server-authoritative replication.** The server decides what happened. | 2026-08-21 | Chosen over lockstep and host-authority deliberately, accepting it is heavier for a 1v1 prototype, because ranked play needs it and retrofitting it later would be a rewrite. |
| D3 | **The game server is a headless Godot export of this same project**, in GDScript. | 2026-08-21 | One copy of the simulation, shared by client and server. See §5.2. |
| D4 | **Dedicated server process from day one**, run on localhost during development. | 2026-08-21 | Not a listen server. "Runs on your machine" and "runs in a datacenter" then differ only by an address. |
| D5 | **ENet (`ENetMultiplayerPeer`) is the transport.** | 2026-08-21 | UDP with reliable *and* unreliable channels. Built in. See §6 for why not WebSockets. |
| D6 | **Lobbies live on the server.** | 2026-08-21 | No Steam lobbies, no separate master server. |
| D7 | **No account backend for now.** Rating, elo and match history are deferred. | 2026-08-21 | Will very likely exist later, so nothing may make it harder — see §9. |
| D8 | **Steam is distribution and identity, not transport.** | 2026-08-21 | Integration can be deferred until after the server works. See §10. |
| D9 | **PickleGD: keep the link, do not install yet.** | 2026-08-21 | Not a transport. Likely useful for cold-path payloads, wrong for the hot path. See §7. |
| D10 | **The network session may be a plain autoload**, standing on its own rather than going through `References`. | 2026-08-21 | User's call: `References` is a convenience, not a hard rule, and a global-like entity is exactly what a session that outlives scene changes needs. Unblocks 0.1. |
| D11 | **Simulation tick is 20 Hz**, in a config `.tres`. | 2026-08-21 | Squarely in the RTS band (see §12 0.5). 50 ms, and an exact 3:1 divisor of a 60 Hz render frame. |
| D26 | **A dropped player gets a 10 second hold** before being declared gone, and a DELIBERATE leave skips it entirely. | 2026-08-23 | User's call, from the three sketched in §14.1. Sits on top of the ~5.6 s ENet already takes to notice a hard-killed client, so a crash resolves in about fifteen seconds and a brief hiccup costs nothing. Implementable only because a goodbye and a silence are different messages, not merely different speeds - see 3.6 for what it took to make the goodbye actually arrive. |
| D25 | **Milestone 3 includes the gameplay its own success criterion needs**: the send ring, lives, and life steal on a leak. | 2026-08-23 | User's call. All three were already specified in `game_rules.md` and none is networking, but "see each other's lives drop" is untestable without them, and D14's disconnect rule needs lives that can drain. Built and verified before any command went over a wire. |
| D24 | **Start runs a 5 second countdown**, shown to everyone in the lobby. Nobody may join during it; any player leaving cancels it; the host may cancel it at any point. The browser lists such a lobby as **"Starting..."** and unjoinable. | 2026-08-23 | User's rule. Gives everyone a moment to see the match is about to begin, and makes "who is in this match" final before the handshake rather than during it. Fully specified; §8.1. |
| D23 | **A lobby closes when its host leaves.** Everyone else is returned to the browser with a reason. | 2026-08-23 | User's call, over promoting the next player. The Warcraft III rule, and the simplest one: no succession to define, no "who is host now" to replicate. |
| D22 | **Lobby membership reuses `MatchPlayer`.** A lobby seat is a slot, a display name and a peer id — exactly a `MatchPlayer`. | 2026-08-21 | So a lobby is a proto-`MatchSetup` and pressing Start wraps the list rather than converting it. One serialisable player type, not two. |
| D21 | **One `Lobby` autoload on both sides**, branching on `multiplayer.is_server()`, rather than a separate `LobbyService` and `LobbyClient`. | 2026-08-21 | Godot routes an `@rpc` by NODE PATH: the receiver must sit at the same path on both machines or the call silently goes nowhere. One autoload makes the paths match by construction. Supersedes the two-object shape sketched in §12 → 1.4. |
| D20 | **A client connects when Multiplayer is pressed**, not at boot. | 2026-08-21 | The lobby browser needs a live list, so the connection's lifetime is the browser's. Single player never opens a socket, and the browser is where every failure state in 1.8 already belongs. |
| D19 | **One process runs the lobby and the match** for now. | 2026-08-21 | Splitting them later is an address change, so it is safe to defer. Does not conflict with D16: still one process per match once matches are spawned separately. |
| D18 | **Dev server runs locally in the office**, on the user's own PC for the first tests. | 2026-08-21 | Same code path as anywhere else; the address is one line in `NetworkConfig`. |
| D17 | **Feedback now, prediction later.** No client-side prediction in the first version. | 2026-08-21 | Immediate local feedback only. Prediction revisited much later, as an experiment. |
| D16 | **One server process per match.** | 2026-08-21 | Also the only way to use more than one CPU core — see §14.3. |
| D15 | **Load timeout 60 s**, then start without whoever is missing, provided `min_players` are ready. No area spawns for them. | 2026-08-21 | See §14.2. |
| D14 | **A disconnect erases that player's maze.** The match continues; their lives drain away through normal life steal until they are eliminated normally. | 2026-08-21 | Reuses life steal, elimination and ring-closing exactly as `game_rules.md` already defines them — see §14.1. |
| D13 | **No reconnect. Out is out.** A player who disconnects is gone for that match. | 2026-08-21 | User's call. Simplifies a lot — see §14.1. Does not rule out a short grace period before declaring someone gone, which is a different thing. |
| D12 | **An ability's network id is authored on the ability** (`UnitAbility.ability_id`), never derived from a position in a list. The registry is built from the content itself, never from a hand-kept list. | 2026-08-21, extended 2026-08-23 | User's call, and the right one: adding, removing or reordering abilities cannot renumber anything else, and there is no list to keep in step. **Extended 2026-08-23, user's call: the registry holds EVERY authored ability, orphan or not** - so walking the content graph is no longer enough on its own and a folder scan was added beside it. An ability on nobody's card still owns its number, which is what stops a new one being authored into the same id while its card is still being built. Matters most while content is being made, which is exactly when nothing is on a card yet. |

### Still open

Only genuinely open questions live here. Anything answered has become a decision above, or
is written into §12 where it was built.

- **Where the player stats belong on screen, and what a player is called there.** The panel
  exists top right - name, life, income, value, placement - but `game_rules.md` never placed
  it, and it wants an ANONYMOUS mode where a player is known by their COLOUR instead. That
  needs a game mode selection, which does not exist, and player colours, which are L1. Until
  both land it is the display name in a placeholder layout.
- **The population cap is displayed but not enforced.** `GameConfig.population_cap` is drawn
  in the status bar; nothing refuses a send that would exceed it. Whether it should is a
  rules call.
- **`Scenes/basic_tower_stats.tres` is outside the registry's folder.** It lives in `Scenes/`
  rather than `Resources/UnitStats/`, so the scan never sees it and its `unit_type_id = 14`
  is not reserved against a collision - exactly the hazard the registry exists to remove.
  Moving the file fixes it. It is dead content either way (§11).
- **Whether one server process should host more than one match.** It hosts one, refuses a
  second with a sentence, and frees itself when that one empties - D19 doing its job until
  D16 splits them. Nothing is blocked on it.

---

## Milestone status

Live progress. **Keep this table updated as work lands** — it is the quick answer to "where
are we". The detail behind every line is §12; this is only the score.

Legend: ☐ not started · ◐ in progress · ☑ done · ⊘ blocked / waiting on a decision

### Phase 0 — local groundwork, no networking

Every item verifiable by playing the prototype in single player.

| | Step | Status | Notes |
| --- | --- | --- | --- |
| 0.1 | Session lifetime (network autoload) | ☑ | Settled by D10: a plain autoload, outside `References`. No code needed until Milestone 1 has a peer to own. |
| 0.2 | `MatchSetup` handoff, `Main` consumes it | ☑ | `MatchSetup` + `MatchPlayer` + `MatchSession`. `Main` no longer reads `local_player_id` from config. Falls back to a stand-in when run from the editor. |
| 0.3 | A builder + player state per player | ☑ | Verified: `player_count = 2` builds two lanes and two builders, camera on the local one. |
| 0.4 | Stable unit ids and registry | ☑ | `Unit.unit_id`, claimed in `setup()`, released in `_exit_tree()`. Registry on `MatchSession`, with `claim_unit_id()` ready for server-assigned ids. |
| 0.5 | Fixed simulation tick + render interpolation | ☑ | 20 Hz. The engine's physics tick IS the simulation tick; `Engine.get_physics_frames()` is the tick counter. Interpolation confirmed working and required. Exposed a latent creep-pathing bug — §5.6. |
| 0.6 | One shared match RNG | ☑ | Seeded from `MatchSetup`. All three unseeded lines gone. Generator passed explicitly, fetched via `MatchSession.match_rng()`. |
| 0.7 | Ability ids (`AbilityRegistry`) | ☑ | Id authored on the ability (D12). Registry = the content walk PLUS a scan of the abilities folder, so it holds all 26 including orphans. Both halves proven by falsification. |
| 0.8 | Split simulation from presentation | ☑ | Partial, as planned. A match now builds and runs with every presentation reference null, proven by `Scenes/Server/server_match.tscn`. Found and fixed one real coupling: projectiles. |

### Milestone 1 — lobbies work

**Done means:** two clients and one server; the lobby list is live; create / join / leave
update every client's view; the host can press Start.

| | Step | Status | Notes |
| --- | --- | --- | --- |
| 1.1 | Server entry point + boot dispatch | ☑ | `boot.tscn` is the `main_scene` and dispatches on the `dedicated_server` tag or `--server`. `server_main.tscn` is a status line plus a log view. Both roles verified booting headless from the real `main_scene`, stderr clean. |
| 1.2 | `NetworkConfig` resource | ☑ | Address, port, max peers, connect timeout, `--address` / `--port` overrides. No tick rate, deliberately — see below. |
| 1.3 | `NetworkService` (peer ownership, signals, error enum) | ☑ | The autoload `Net`. Server hosts on boot, client dials when the browser opens (D20). Verified end to end: listen → peer joined → peer left. |
| 1.4 | The `Lobby` autoload (create / list / join / leave) | ☑ | One object both sides (D21). Pushed, not polled. Verified headless with two clients: create, list, join, and host-leaves-closes. |
| 1.5 | `LobbyInfo.to_dict()` / `from_dict()` | ☑ | Carries its roster as `MatchPlayer`s (D22), so a lobby is a match waiting to happen. |
| 1.6 | Server-assigned identity | ☑ | The peer id IS the identity. A display name is sanitised on arrival and never used as a key. |
| 1.7 | Wire the existing lobby screens | ☑ | Browser list and room roster are driven by server pushes. Start became live in 2.1, where it doubles as Cancel. |
| 1.8 | Connection failure states in the UI | ☑ | Connecting, unreachable, refused, dropped mid-lobby. Buttons follow the connection; Refresh becomes Reconnect while offline. All verified in the running game. |
| 1.9 | Leaving, explicit and otherwise | ☑ | Back, Leave, quit, crash and pulled cable. A clean quit is seen in 0.13 s against 5.6 s for a kill. |

### Milestone 2 — load into the same match together

**Done means:** the host presses Start, every client shows a loading screen listing who is
still loading, and the match begins for everyone on the same tick.

| | Step | Status | Notes |
| --- | --- | --- | --- |
| 2.1 | The start handshake, incl. the 5 s countdown (D24) | ☑ | Countdown on the server, announced once a second. Cancelled by the host or by anybody leaving; joining refused while it runs. All four paths verified headless. |
| 2.2 | Loading scene with per-player readiness | ☑ | `match_loading.tscn`, threaded load with a real progress bar, one row per player reading Loading.../Ready. |
| 2.3 | Server loads the match headless | ☑ | Same `MatchSetup`, `server_match.tscn`, `local_slot` 0. It also comes BACK to the entry scene when the last player leaves, so one process serves match after match. |
| 2.4 | Ready-timeout policy | ☑ | Decided (D15) and now built: 60 s, then start without them if `min_players` are ready, and tell the ones left behind. |
| 2.5 | Identical initial world + checksum | ☑ | `WorldChecksum` over setup, areas and the unit registry. Proven by falsification: a one millimetre shift on the clients was caught. |

### Milestone 3 — playable and synchronised

**Done means:** two players on separate machines build, send and see each other's lives
drop, with both views agreeing.

| | Step | Status | Notes |
| --- | --- | --- | --- |
| 3.0 | The gameplay M3 needed: send ring, lives, life steal (D25) | ☑ | Not in the original plan. A leak moves one life from defender to sender and RECYCLES the creep rather than removing it, exactly as `game_rules.md` says. |
| 3.1 | Command layer + server-side validation | ☑ | `Command` + the `Commands` autoload. The slot is taken from the peer id, never from the message. Ownership and the card are checked here; gold, stock and placement are left to the simulation, which already refuses them. |
| 3.2 | Replication phase A (full state broadcast) | ☑ | The whole world at 20 Hz, unreliable, as flat float arrays. Units, players, and send stock. Bandwidth-ugly on purpose. |
| 3.3 | Replication phase B (spawn-and-extrapolate) | ☐ | Deliberately not started. The roadmap recommends shipping phase A first so this is measured rather than guessed. |
| 3.4 | Clients stop being authoritative | ☑ | A client runs NO simulation at all: `MatchSession.is_authority()` gates every gameplay loop. With no prediction yet (D17) there is no third state to hold. |
| 3.5 | Reconciliation and drift detection | ☑ | Nothing to build, and that is a finding rather than a dodge - see §12. The initial-world checksum (2.5) still runs. |
| 3.6 | Disconnect policy | ☑ | 10 s hold, deliberate leave skips it (D26). The maze is erased and the leaver's lives drain away through ordinary life steal (D14). Verified both ways. |
| 3.7 | Latency feel | ☐ | Nothing to do until somebody plays over a real connection: "measure before optimising". |

---

### After Milestone 3 — what the first real play test asked for

Not a milestone. What playing the thing turned up, in one round.

| | Item | Status | Notes |
| --- | --- | --- | --- |
| P1 | Units face their walk direction | ☑ | A replication gap, not a maths one: a client runs no movement code, so it had nothing to turn units with. Yaw joined the snapshot. |
| P2 | Build grid as a builder ability, slot 9 | ☑ | Needed a new idea: `UnitAbility.is_local_only()`, for presentation that must never become a command. Covers every maze at once. |
| P3 | Status bar and player stats panel | ☑ | Gold / population / income countdown across the top middle; name, life, income, value, placement top right. |
| P4 | The match ends | ☑ | Last player standing. Everything an eliminated player owns leaves the field, income stops, nobody can send. No end screen (L2). |
| P5 | Double click a lobby row to join | ☑ | Through the same guarded path as the Join button, refusals included. |

---

### Later, not scheduled

Wanted, decided to be wanted, but not part of any milestone above.

| | Item | Notes |
| --- | --- | --- |
| L1 | Player colours in the lobby | Needed before a minimap can tell players apart, and before the anonymous mode game_rules.md wants. Shape and consequences in §8.1. |
| L2 | An end screen | The match decides itself and stops; players then leave through the in-game menu. Deliberately the smallest thing that works. |
| L3 | Game mode selection | Where anonymity, and anything else chosen before a match, would be picked. Nothing depends on it yet. |

--- | --- | --- |
| L1 | Player colours in the lobby | Needed before a minimap can tell players apart. Shape and consequences in §8.1. |

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
| `Scripts/Multiplayer/NetworkService.gd` | The autoload **`Net`**: owns the one ENet peer, reports through signals and a `Result` enum. |
| `Scripts/Config/NetworkConfig.gd` + `Resources/Config/network_config.tres` | Address, port, max peers, connect timeout, command-line overrides. |
| `Scripts/Util/CommandLineUtil.gd` | Reading launch arguments — both spellings, both arg lists, one place. |
| `Scripts/Multiplayer/LobbyService.gd` | The autoload **`Lobby`**: the registry on the server, the mirror of it on a client, and the start countdown (D24). |
| `Scripts/Multiplayer/MatchStartService.gd` | The autoload **`MatchStart`**: the handshake from "countdown ran out" to "the match exists on every machine". Nothing beyond that. |
| `Scripts/UI/Menus/MatchLoading.gd` + `Scenes/UI/Menus/match_loading.tscn` | The loading screen: a threaded load with a real progress bar, and who is still loading. |
| `Scripts/Game/WorldChecksum.gd` | One number for the world a machine just built, so two machines can compare theirs in one message (2.5). |
| `Scripts/Multiplayer/Command.gd` | One player order on its way to the server: ids and numbers, never object references. |
| `Scripts/Multiplayer/CommandService.gd` | The autoload **`Commands`**: the one road every order takes, and the server-side validation of it. |
| `Scripts/Multiplayer/ReplicationService.gd` | The autoload **`Replication`**: the whole world, every tick, server to clients (phase A). |
| `Scripts/Game/UnitTypeRegistry.gd` | Every KIND of unit by id, so a spawn can be replicated as a number (D12's argument, applied to units). |
| `Scripts/UI/MatchStatusBar.gd` | Gold, population and the income countdown, across the top middle. |
| `Scripts/UI/PlayerStatsPanel.gd` + `PlayerStatRow.gd` + `Scenes/UI/player_stat_row.tscn` | Every player's life, income, value and placement. Placeholder layout - `game_rules.md` does not place it yet. |
| `Scripts/Abilities/ToggleGridAbility.gd` | The builder's grid toggle, slot 9. Local only: presentation never becomes a command. |
| `Scripts/Multiplayer/LobbyInfo.gd` | What one lobby advertises, AND its roster of `MatchPlayer`s. |
| `Scripts/Multiplayer/LobbyIdentity.gd` | Who the local player is. Currently the OS user name. |
| `Scripts/Multiplayer/MatchSetup.gd` + `MatchPlayer.gd` | Who is in a match, which slot is local, the RNG seed. Flat and serialisable. |
| `Scripts/Game/MatchSession.gd` | This match: the setup, the seeded RNG, the unit-id registry, the tick counter, the ability registry. A scene node, held by `References`. |
| `Scripts/Abilities/AbilityRegistry.gd` | Every ability a command can name, built by walking the content graph. |
| `Scenes/Server/server_match.tscn` | A match with no camera, HUD or effects. Proves the simulation stands alone, and IS the scene the server opens for a match. |
| `Scripts/Config/MenuConfig.gd` + `Resources/Config/menu_config.tres` | Scene paths, player counts, title, countdown and load timeout. |
| `Scripts/Config/ContentConfig.gd` + `Resources/Config/content_config.tres` | Where the content this build contains lives. Only the abilities folder so far, scanned so orphans still get ids (D12). |

Phase 0 also changed the game scene itself: every player now gets a builder and a
`PlayerState`, all simulation runs on the 20 Hz tick, every unit carries a network id, and
all randomness comes from one seeded generator. `Main.tscn` gained a `MatchSession` node and
a `GameMenu`. See §12 Phase 0 for the detail.

### What Phase 0 left you to build on

The machinery a networked match needs already exists. Everything after it uses this rather
than inventing a second copy, and still does.

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
right now — which `BuildingStats` overrides to add the Cancel it swaps in. See §11.

**Two world roots, and the distinction is load-bearing:**

- `References.projectiles_root` — projectiles in flight. **Simulation.** Present everywhere.
- `References.effects_root` — impacts, markers, revive lights. **Presentation.** Null on a
  server, and everything that uses it already steps aside quietly.

Anything new that is spawned into the world belongs to one or the other. Getting this wrong
is how the server and the client end up disagreeing about when something died.

**`Main._dedicated_server`** — a bool `@export`, set on `server_match.tscn` and nowhere else.
Forces `local_slot` to 0, so every "is this mine" test answers no, and turns a missing camera
or `ControlsConfig` from an error into the expected state.

*This section once said Milestone 1 would replace it with the `dedicated_server` feature tag.
It did not, and on reflection should not: the tag answers "is this PROCESS a server", which
`Boot` already asks once, while this flag answers "is this SCENE a server's match" - and the
scene is the honest place for that, since it is the thing that has no camera. The two happen
to agree today and need not always.*

**`Scenes/Server/server_match.tscn`** — a whole match with no camera, HUD, controllers or
effects root. Built as the proof for 0.8; it is the scene a server should load for a match.

### What Milestone 1 left you to build on

Every signature below was read off the code, not remembered. Trust this list over a
recollection; if something here is wrong, the code changed and this section did not.

**Two autoloads, in this order in `project.godot`** - `Net` before `Lobby`, because `Lobby`
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

### What Milestone 2 left you to build on

Read off the code, like the section above it. There is one new autoload and one new screen.

**Three autoloads now, in this order in `project.godot`** - `Net`, then `MatchStart`, then
`Lobby`. `MatchStart` sits in the middle because `Lobby` subscribes to its `match_abandoned`
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

### What Milestone 3 left you to build on

**Five autoloads now, in this order** - `Net`, `MatchStart`, `Lobby`, `Commands`,
`Replication`. Every one of them is an autoload for the same forced reason: an `@rpc` routes
by NODE PATH, and the two match scenes have different roots (`/root/Main/...` against
`/root/ServerMatch/...`), so nothing inside a match scene can be an rpc endpoint.

**`Commands`** (`Scripts/Multiplayer/CommandService.gd`) - the one road a player order takes:

```gdscript
Commands.submit(ability: UnitAbility, units: Array, target: AbilityTarget) -> void
```
Signals: `command_applied(Command)`, `command_rejected(Command, String)` - both server side.
Wire: `submit_command` is `@rpc("any_peer", "reliable")`. `Command`
(`Scripts/Multiplayer/Command.gd`) is a RefCounted, not a Resource: it is created, sent and
dropped, never authored.

**`Replication`** (`Scripts/Multiplayer/ReplicationService.gd`) - the world, every tick.
Nothing calls into it; it reads the world on the server and writes it on a client. Wire:
`receive_snapshot` is `@rpc("authority", "unreliable")`. `process_priority = 1000` so it runs
AFTER the match scene and describes the tick that just finished.

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

**`UnitAbility.is_local_only()`** - the one thing an ability can be that is NOT a
command. A build ghost, the selection and the range overlay never left the machine already;
this makes that a property an ability can declare, so the builder's grid toggle gets a card
slot and a hotkey without asking a server that has no grid what it thinks. False by default,
deliberately: an ability that forgets to answer ends up validated by the server, which is the
safe way round.

**Replicated setters, and why they are separate from the ordinary ones:**

```gdscript
Unit.set_replicated_health(value)                  # never kills; removal comes from absence
Unit.adopt(id, player_id, area, world_pos)         # setup(), but with the id handed IN
PlayerState.set_replicated(gold, income, lives)    # no spend/gain rules re-run
SendBuilding.set_replicated_stock(stats, count)
Building.set_replicated_phase(building, selling)
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

**What is still missing, deliberately:**

- **No client-side prediction** (D17). An order takes a round trip before anything moves.
- **No interest management, no quantisation, no spawn-and-extrapolate.** All of §5.4, all of
  3.3, all of it deliberately measured-against rather than guessed at.
- **No win condition.** Lives reach zero and the ring skips that player; `game_rules.md` says
  a match never ends, and it still does not.
- **Projectiles are not replicated.** They are re-simulated locally as presentation, and only
  the server applies their damage.

---

### Local tuning state worth knowing

Not multiplayer, but it will confuse anyone reading the numbers cold:

- `SEPARATION_LIMIT` in `Creep.gd` is **0.0** — creep separation is switched off by the
  user's choice. Creeps may stand inside each other. Worth revisiting now that the waypoint
  bug it was masking is gone (§5.6), but that is a design call.
- `game_config.tres` has `starting_gold = 2000` against a script default of 20. A deliberate
  test value, kept on purpose so building is quick to try. The user knows; it is a one-line
  change whenever it stops being useful. Do not keep flagging it.

**Those seams are no longer stubs.** `set_lobbies()`, `refresh()`, `_on_join_pressed()` and
`LobbyRoom.show_lobby()` all kept their shapes and are driven by server pushes; the list is
sent unprompted, so `refresh()` is a repaint rather than a request.

Two are still seams, on purpose:

- `LobbyIdentity.display_name()` — still the OS user name. One line to change when a real
  identity arrives (Steam, §10). The SERVER already treats whatever it says as untrusted.
- `MenuNavigation.pending_lobby` — kept only so `lobby_room.tscn` can be run on its own from
  the editor. The live path reads `Lobby.current()` instead.

---

## 3. What the game needs from the network

- **2–15 players, free for all, no teams** (`game_rules.md`). Prototype target is 1v1.
- **Very few player commands.** Build, sell, send, move, attack. Handfuls per second.
- **Very many simulated units.** Thousands across 15 lanes in the bad case.
- **Lanes are independent.** A player's creeps only affect that player's lane. Cross-player
  events are *sending* a creep, gold/income, and life loss.
- **PC only.** Single platform.
- **Rating must be trustworthy** — the reason for D2.

---

## 4. Why server-authoritative, and what it costs

Rejected alternatives, recorded so the reasoning is not relitigated:

| Rejected | Why not |
| --- | --- |
| **Deterministic lockstep** | Genre-correct, and this codebase suits it unusually well (§11). But no client can be trusted to report a result, and a desync is unrecoverable. Its bandwidth advantage is largely recovered anyway by §5.4. |
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
the single chokepoint every player order already funnels through (§11). A command is close
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
   This is what makes 15 players affordable; in a 1v1 it barely matters.
3. **Quantisation.** Positions as 16-bit fixed point over the lane's known bounds, not three
   32-bit floats.
4. **Events, not state, for discrete things.** Deaths, damage, life loss and gold changes are
   messages, not fields polled every tick.

**Consequence worth noting:** because the client runs the same simulation as a prediction,
the determinism findings in §11 keep their value. The difference from lockstep is that drift
is *corrected* rather than fatal, so the standard is "close enough", not bit-exact. Much
cheaper to hold.

### 5.5 Fixed tick and prediction

**Built.** The simulation runs at 20 Hz (D11); roadmap 0.5 covers what it took.

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
  the match setup object in §12 comes from.

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
4. If it runs out, the 2.1 start handshake begins.

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

**Player colours.** *Planned, not scheduled.* Every player needs a colour chosen in the lobby,
because a minimap - and anything else showing several players at once - needs them told apart
at a glance. Consequences worth knowing before it is built:

- A colour is per-match identity, so it belongs on `MatchPlayer` next to `slot` and
  `network_id`, and travels in the same `to_dict()`.
- It must be **unique within a lobby**, which means the server assigns and validates it. A
  client asking for a taken colour is refused, exactly like a full lobby.
- The palette is content, so it belongs in a config `.tres`, not in a script.
- Somebody joining needs a free colour by default, or they sit colourless until they pick.

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

## 11. Codebase readiness audit

Measured against the current tree, not assumed.

### One command chokepoint

Every player order — build, sell, send, move, attack — funnels through
**`UnitAbility.execute(unit, target)`**, reached only from
`Scripts/Input/CommandController.gd` in three places (`_execute_on_selection`,
`_issue_default_command`, `_order_attack_on`). Abilities are already stateless and carry
their own behaviour. Turning intent into a network command is one seam, not a sweep.

### The simulation is already physics-free and nearly deterministic

| Hazard | Finding |
| --- | --- |
| Physics engine | **None.** No `intersect_ray`, `move_and_slide` or `direct_space_state` anywhere in `Scripts/`. Every unit is a plain `Node3D`, never a `CharacterBody3D`. Now a hard rule (D1). |
| Seeded RNG | `Scripts/Util/RNGUtil.gd` takes an explicit `RandomNumberGenerator` in **every** function. Built for this. |
| Unseeded RNG | **None left.** The three lines that existed (`AttackStats.roll_damage()` and two `randf_range` in `PlayerArea.random_spawn_point()`) now take the match RNG explicitly. |
| Wall clock | One use, `SelectionController` double-click timing. Input only, not simulation. |
| Unit movement | `MobileUnit._physics_process` — the fixed tick, now 20 Hz. |

Under D2 this need not be bit-exact, only close, since the server corrects drift (§5.4).

### The gaps, and what is left of them

1. ☑ **Gameplay loops on variable frame time.** `Building`, `SendBuilding` and
   `PlayerManager` moved from `_process` to `_physics_process`. All simulation is now on the
   20 Hz tick.
2. ☑ **Match setup handoff.** `MatchSetup` carries the player list, the local slot and the
   seed. `Main` no longer reads either from `game_config.tres`.
3. ☑ **Units are addressable.** `Unit.unit_id`, claimed on setup, released on exit, indexed
   by `MatchSession`.
4. ◐ **One commandable player.** Every player now gets a builder and a `PlayerState`, and
   the camera follows the local one. Still local-only: `SelectionController` picks only this
   client's units, which is correct for a client but wrong for a headless server that owns
   all of them.
5. ◐ **Simulation and presentation are entangled.** `Unit extends Node3D` and still owns
   its model. But nothing in the simulation path *reads* a visual node any more, and a match
   builds and runs with every presentation reference null — which is what the headless
   server actually needs. The deeper split (units that are not `Node3D` at all) remains
   possible later and is not required by anything on the roadmap.
6. ☑ **The ability registry did not contain every ability.** Found while auditing before
   Milestone 3, fixed before starting it - below.

### The ability registry missed four ids, and two of them mattered

Measured, not inferred: at boot the registry held **22** ids -
`1 2 3 4 7 · 21 22 23 24 · 41-46 · 60-66` - while **26** were authored. The four it never saw:

| Id | Ability | Why it was missed |
| --- | --- | --- |
| **5** | Cancel Build | Lives in `BuildingStats.construction_abilities` |
| **6** | Cancel Sell | Lives in `BuildingStats.selling_abilities` |
| 20 | Build Basic Tower | Orphan: referenced by NOTHING |
| 40 | Send Basic Creep | Orphan: referenced by NOTHING |

**5 and 6 were a real bug.** They are live, pressable buttons - the card swaps down to just
Cancel while a building goes up or comes down - and `_walk_stats()` read only
`stats.abilities` and `stats.default_ability`, so it never found them. In 3.1
`ability_for(5)` would have returned null, and a null lookup is exactly what a client running
MISMATCHED CONTENT looks like, so a perfectly legitimate Cancel would have been rejected as a
content mismatch.

**Fixed by asking the stats instead of guessing at their fields.** `UnitStats.card_abilities()`
returns every ability a unit's card can ever show; `BuildingStats` overrides it to add the two
it swaps in. Explicit rather than duck typed, exactly like `UnitAbility.reached_stats()`
already is - a subclass with a card of its own has to say so, or it is invisible.

**20 and 40 are kept, and now registered** (D12 extended, user's call). They are leftovers
from the placeholder tower and creep, on nobody's card - but an orphan still owns its number,
or a new ability written later could be authored into the same one. Since an orphan is by
definition reachable from nothing, no walk can find it: `AbilityRegistry` now also SCANS the
abilities folder, named by the new `ContentConfig`. A folder rather than a list, because a
list is the hand-kept register D12 exists to avoid.

**Why it still walks as well as scans.** The scan finds every ability in a file of its own;
the walk finds any ability defined INSIDE another resource, and anything living outside that
folder. Neither covers the other. The walk runs first, because both mark what they have seen
and a scan that reached a build menu first would stop the walk recursing through it.

**Both halves proven by falsification**, which is the only way a count means anything:

| Registry built from | Ids held |
| --- | --- |
| The walk as it was | 22 |
| The walk, fixed (`card_abilities`) | 24 — recovers exactly 5 and 6 |
| Walk + folder scan | **26** — the scan adds exactly 20 and 40 |

Pointing `abilities_folder` at a folder that does not exist produced two errors at boot and a
visibly shorter registry, rather than a quietly shorter one - which was the thing to check,
since a short registry looks identical to a client running different content.

**The lesson worth keeping: `validate()` could not have caught this.** It checks every
ability the build FOUND, so an ability the build never reaches is invisible to it. A check
only sees what it is given, and this one was being given the wrong set. The scan is what now
makes "every authored ability" a set the check can actually be measured against.

Worth noting separately: `Scenes/basic_tower_stats.tres` is a `.tres` living in `Scenes/`,
against the folder rule in `CLAUDE.md`. Left alone - it is content, not implementation.

---

## 12. Roadmap

Organised around the three milestones. **Phase 0 comes first**, and that ordering is the
most important thing in this section: those changes touch working gameplay code, and
verifying them through a network layer instead of in single player is miserable. If the
fixed tick breaks creep movement, you want to find that out while there is still only one
machine involved.

### Phase 0 — local groundwork, no networking

All of it verifiable by playing the prototype.

**0.1 Session lifetime.** ☑ *Decided (D10), no code needed until Milestone 1.* The menus change scenes with
`change_scene_to_file`, and `References` is per-scene, so anything holding a socket dies on
every transition. The session has to outlive scene changes.
Recommendation: one autoload owning the peer and the session, exposed through
`References.net` so call sites keep the project convention. The project already has an
autoload (`_mcp_game_helper`), and `CLAUDE.md` forbids `@onready` and `$` but says nothing
against autoloads. **This is the one convention deviation and wants an explicit OK.**

**0.2 Match setup handoff.** ☑ *Built.* A `MatchSetup` resource: player list (network id, display name,
slot), which slot is local, RNG seed, match id, tick rate. `Main` consumes it instead of
reading `player_count` / `local_player_id` from `game_config.tres`. Falls back to
synthesising one from `GameConfig` when `Main.tscn` is run directly from the editor, so
single-player iteration is unchanged.

**0.3 A builder and a player state per player.** ☑ *Built.* `Main` used to give a builder only to
`local_player_id`. Every player needs one and the server needs all of them. The camera
focuses the local player's area. First point where the 1v1 layout is genuinely exercised.

**0.4 Stable unit ids and a registry.** ☑ *Built.* A monotonic int assigned at spawn plus a
`Dictionary[int, Unit]` per match, so a command or a state update can name a unit.

**0.5 Fixed simulation tick, 20 Hz** (D11). ☑ Done, and far smaller than this roadmap
assumed — see the note at the end of this step.

*Why 20, since there is no single industry number.* Rate follows genre, not fashion.
Competitive shooters run 60-128 Hz because aim is decided between frames. MOBAs sit around
30. RTS games — the relevant family — run far lower: StarCraft II simulates at roughly 16
steps per second, Warcraft III's lockstep turns are 50-100 ms, Company of Heroes is about
10 Hz. A tower defence has no aiming at all; the player places buildings and sends waves, so
20 Hz (50 ms) is comfortably inside the RTS band and well below the threshold where a build
feels late. It is also an exact 3:1 divisor of a 60 Hz render frame, which keeps the
accumulator from jittering. It lives in a `.tres`, so it is one number to change. Convert `Building._process`, `SendBuilding._process`, `PlayerManager._process`
and `MobileUnit._physics_process` to an explicit `on_tick(dt)`.
**What it actually took.** The roadmap assumed three loops on variable frame time. There
were eight — five were already in `_physics_process`, which is itself a fixed tick, just at
60 Hz. So the whole change was: set `physics/common/physics_ticks_per_second` to 20, and
move the remaining three (`Building`, `SendBuilding`, `PlayerManager`) out of `_process`.

That settles the design cleanly: **the engine's physics tick IS the simulation tick.** There
is no second clock to keep in step, `Engine.get_physics_frames()` is the tick counter for
free, and `MobileUnit`'s original docstring — movement in `_physics_process` "so unit
simulation stays on a fixed timestep, which matters once this becomes a multiplayer game" —
turns out to have been the plan all along.

The tick rate lives in `project.godot` rather than a `.tres`. That is the documented
`CLAUDE.md` exception for settings the engine reads before the game starts; it is now the
second one, after the tooltip delay.

**Render interpolation** is Godot's own (`physics/common/physics_interpolation`), not
hand-rolled. Three presentation scripts animate transforms on the render frame and had to
opt out with `PHYSICS_INTERPOLATION_MODE_OFF`, because an interpolated node moved outside
the tick jitters — `SpinAnimation3D`, `ReviveLight` and `AttackTargetMarker`. Anything
*placed* rather than moved now calls `reset_physics_interpolation()`, or the interpolator
streaks it in from the world origin: creep spawn, projectile launch, and the builder,
building and send building placements.

**Confirmed in play.** Interpolation is doing its job and is required: the builder covers
0.30 units per tick and is visibly stepped without it. Nothing was found jittering, so the
three opt-outs appear to be the complete set.

**It also exposed a latent bug** — creeps oscillating around their waypoints once a tick
covered more ground. That is written up in §5.6, because the lesson generalises to any
future change of the tick rate.

**0.6 One shared match RNG.** ☑ *Built.* Seeded from `MatchSetup`, replacing `AttackStats.roll_damage()`
and the two `randf_range` calls in `PlayerArea.random_spawn_point()`.

**0.7 Ability ids.** ☑ *Built, and better than this said — see D12.* A command has to name an ability in a way both sides agree on. An
`AbilityRegistry`. The roadmap proposed a hand-kept list with the id as the index; what was
actually built is better on both counts (D12). The id is **authored on the ability**
(`UnitAbility.ability_id`), so adding, removing or reordering abilities can never renumber
anything else, and the registry **builds itself by walking the content graph** from the same
two roots `Main` validates, so there is no list to keep in step. Boot validation catches an
unassigned id and two abilities claiming the same one.

**0.8 Split simulation from presentation.** ☑ *Done, partial as planned.*

The audit found that almost everything was already fine. All match geometry comes from
`GameConfig`, never from a mesh — `PlayerArea` only ever *writes* to its zone meshes, sizing
them from the config. Unit models, health bars, selection rings and the build grid are
written to and never read. Impact effects, move markers and revive lights already stepped
aside when `References.effects_root` was null, and a creep's revive is driven by its own
countdown rather than by the light standing over it.

**One real coupling was found, and it mattered:** projectiles were parented to the *effects*
root, and `ProjectileDelivery` resolved the hit **instantly** when that root was missing. But
a projectile's flight time is simulation, not decoration — the target keeps walking while
the shot is in the air and the damage lands on arrival. A headless server would therefore
have killed creeps at a different moment than the client showed, which is exactly the class
of disagreement server authority exists to prevent.

Fixed by splitting the two roots, which is now the standing rule:

| Root | Holds | On a dedicated server |
| --- | --- | --- |
| `References.projectiles_root` | Projectiles in flight — **simulation** | present |
| `References.effects_root` | Impacts, markers, revive lights — **presentation** | null |

`Main` also gained a `_dedicated_server` flag. It forces `local_slot` to 0, so every
"is this mine" test answers no, and it turns a missing camera or `ControlsConfig` from an
error into the expected state rather than a fault.

**Proven, not assumed.** `Scenes/Server/server_match.tscn` builds a whole match — areas,
grid, send building, a builder per player, the economy — with `_effects_root`, `_rts_camera`,
`_unit_panel`, both controllers and the overlay all null, and boots with zero errors. That
scene became the server's match scene in 2.3, unchanged - which is the whole return on this
step.

What is deliberately *not* done: `Unit` still extends `Node3D` and owns its model, so a
headless run still instantiates meshes it never draws. That costs memory and blocks
stripping resources from the server export, and it is not required by anything on the
roadmap. The deeper split stays available.

### Milestone 1 — lobbies work

**Done means:** two clients and one server; the lobby list is live; create / join / leave
update every client's view within a frame or two; the host can press Start.

**1.1 Server entry point.** ☑ *Built.* `Scenes/Boot/boot.tscn` is the `main_scene`. It picks
client or server from `OS.has_feature("dedicated_server")` or a `--server` command-line
argument, so the server can be launched from the editor without an export, and neither the
menus nor the match ever learn the choice was made. `server_main` is a plain Control with a
log view, so running it in the editor actually shows you what the server is doing;
`ServerMain.log_line()` writes to that view AND to stdout, because a headless export has no
view and stdout is the only place it can speak.

`BootConfig` names the server's entry scene and the argument. The CLIENT's entry scene stays
`MenuConfig.main_menu_scene_path`, which was already the one authority on where the menus
start — copying it into a second `.tres` would give a renamed scene two files to be fixed in,
and the editor rewrites neither.

**Two things worth remembering:**

1. **The dispatch has to be deferred by one idle frame.** Calling `change_scene_to_file`
   straight from the root node's `_ready` makes Godot refuse the `remove_child` with *"parent
   node is busy adding/removing children"* — the tree is still adding the boot scene at that
   moment. The scene change happens anyway, but it prints an error on every boot, and a boot
   that prints an error is a boot nobody trusts. `_dispatch.call_deferred()` is the whole fix.
2. **A custom launch argument must follow a `--` separator**, because Godot treats an
   unrecognised argument before it as an engine argument. So it is `godot -- --server`, read
   back through `OS.get_cmdline_user_args()`. `Boot` checks `get_cmdline_args()` too, so an
   argument arriving by another route still works.

`SceneUtil.change_scene()` was added and `MenuNavigation._change_scene` now delegates to it —
two callers, one requirement, and one of them boots the process.

**Verified**, both roles, run headless from the real `main_scene` with no scene argument and
no editor involved: `role: client` reaching `main_menu`, and `role: server` reaching
`server_main` and logging its boot to stdout with no window. Empty stderr in both.

**1.2 `NetworkConfig` (`.tres`).** ☑ *Built.* Port, address, max peers, connect timeout, and
`--address` / `--port` overrides so a second server or a differently-aimed client needs no
edit and no rebuild. The address is the single line that changes when the dev server leaves
this machine (D18).

Two things it deliberately does NOT hold, against the original sketch of this step:

- **No tick rate.** The simulation tick IS the engine's physics tick, set in `project.godot`
  and read back through `MatchSession.tick_seconds()` (D11). A copy here would be a second
  place to change it and a first chance for the two to disagree.
- **No `max_players`.** `max_peers` is *total connections to the server process*, across
  every lobby and match it runs at once (D19). `MenuConfig.max_players` is seats in ONE
  lobby, 2-15 per `game_rules.md`. Same-sounding, different numbers; naming them apart is
  what stops one being used for the other.

**1.3 `NetworkService`.** ☑ *Built.* Owns the one `ENetMultiplayerPeer` and is the only thing
that ever assigns `multiplayer.multiplayer_peer`. Every entry point returns a `Result` rather
than a bare bool — the template's one genuinely good idea. Signals: `status_changed`,
`hosting_started`, `connected_to_server`, `connection_failed`, `disconnected_from_server`,
`peer_joined`, `peer_left`.

**It is the autoload `Net`, not `NetworkService`.** Godot refuses an autoload whose name
collides with a global class, and `CLAUDE.md` wants the class named after its file. So the
type stays `NetworkService` and the singleton is `Net`, which is also how it reads at a call
site: `Net.join()`, `Net.is_server()`.

**The template's bug is not copied.** It kept an `is_busy` flag that a failed host never
cleared, so one failure bricked the object for the whole session (§13). There is no such
flag: `_status` is the only state, every failure path runs through one `_teardown()` that
puts it back to `OFFLINE`, and the guards read that directly.

**A connect timeout is not optional.** ENet reports an unreachable host by saying nothing at
all — `create_client()` SUCCEEDS against an address with nothing behind it and the connection
simply never completes. Without the timeout the browser would sit on "Connecting..." for
ever. It counts down in `_process`, not `_physics_process`, and that is deliberate: it is a
wall-clock timeout on a socket, not simulation, and it has to keep counting on a machine
whose match has not started.

**Peer ids are large random numbers, not 2, 3, 4.** Godot 4 generates a random id per client
(`1695440927` in testing); only the server is reliably `1`, which is why that one is a named
constant. Nothing may assume ids are small, sequential, or ordered by join time — relevant to
1.6, which makes the peer id the player id.

**Wiring, both ends:** `ServerMain` hosts on boot and logs every arrival and departure.
`LobbyBrowser` dials when it opens and hangs up on Back (D20), so single player never opens a
socket. The browser's status line is real now; its rows are still placeholders until 1.4.

**Verified end to end**, two headless processes on one machine:

```
SERVER                                    CLIENT
Listening { port: 7777, max_peers: 32 }
										  Connecting { address: 127.0.0.1, port: 7777 }
										  Connected to the server { peer_id: 1695440927 }
Peer joined 1695440927
Peer 1695440927 disconnected              (killed)
```

Also verified: a client with no server times out after its configured 5 s and says so,
rather than hanging.

**1.4 The `Lobby` autoload** — the registry of open lobbies, and create / list / join /
leave / start. Godot's high-level `@rpc`, reliable channel. Cold path, no optimisation.
**Superseded by D21:** this was originally sketched as a `LobbyService` on the server and a
separate `LobbyClient` on the client. That does not work as written, because Godot routes an
`@rpc` by node path — the receiving node has to sit at the SAME path on both machines, and
two differently-named nodes silently never receive. So it is one autoload present on both
sides, branching on `multiplayer.is_server()`: the server half owns the registry, the client
half raises the signals the existing screens already have seams for.

**What was built.** `Scripts/Multiplayer/LobbyService.gd`, the autoload **`Lobby`**. Requests
go up (`request_create`, `request_join`, `request_leave`), pushes come down (`receive_list`,
`receive_lobby`, `receive_closed`, `receive_refusal`).

**Pushed, not polled.** The server sends the list whenever it changes, so Refresh is a
repaint rather than a request and a lobby created anywhere appears everywhere without anyone
asking. `refresh()` and `set_lobbies()` kept their shapes; only what drives them changed.

**Success has no "yes".** The server never answers a create or a join with an acknowledgement.
It simply says which lobby you are now in, and the browser navigates on that. One code path
covers create, join, and being put back into a lobby after a reconnect, because all three end
as "you are in this lobby now".

**The mirror image: leaving and being thrown out are also one path.** Both end as "you are in
no lobby", and only the message differs. That is why D23 needed no special handling in the
room screen - the host leaving closes the lobby on the server, and every other client simply
learns it is out.

**Ordering that matters, and cost a bug.** `receive_closed` emits the REASON before it emits
the change of lobby. The screen listening for "you are out" reacts by changing scene, so the
reason has to be in hand before that fires or it is lost. `MenuNavigation.pending_notice`
carries it across, the same trick `pending_match` already used.

**1.5 `LobbyInfo` serialisation.** ☑ *Built.* `to_dict()` / `from_dict()`, since Godot cannot
send a custom `Resource` over RPC. The roster travels with it as `MatchPlayer` dictionaries
(D22), and slots are renumbered 1..n on every change so a lobby is always a legal basis for a
`MatchSetup` - which is what Milestone 2 will need.

This was the first real cold-path payload, so it is the point §7 said to revisit PickleGD at.
Verdict unchanged: `to_dict()` for these two types was a few dozen obvious lines, and a
reflective serialiser would have added a dependency to save them.

**1.6 Server-assigned identity.** ☑ *Built.* The peer id IS the identity: it comes from the
transport, the client cannot forge it, and it is what every lobby is keyed by. A client sends
its display name once on connecting and it is treated as decoration - `LobbyIdentity.sanitise()`
strips control characters, clamps the length and substitutes a fallback for an empty result.
A name is never a key, and nothing is ever looked up by it.

**1.7 Wire the existing screens.** ☑ *Built, finished in 2.1.* The browser lists what the server pushed;
the room shows the live roster with the host marked and the local player marked "(you)",
which matters when two client windows on one machine look identical. The placeholder rows and
`MenuConfig.placeholder_lobby_count` are gone, exactly as their own comments promised.

Start was deliberately disabled here and said why, because a button that lies about starting
a match is worse than one that admits it cannot. It went live in 2.1, where it also became
Cancel for the five seconds of the countdown. Solo testing is unaffected throughout - the
main menu's Play still goes straight to the prototype.

**Verified end to end, headless, no editor involved:** a server and two clients; one creates,
the other sees it appear and joins, both see the roster as `1:Name(host), 2:Name`; killing
the host produces `Lobby closed { reason: The host left the lobby. }` on the server and
`Out of the lobby` plus a list back to zero on the survivor.

**1.8 Connection failure states.** ☑ *Built.* Connecting, unreachable, refused, timed out,
dropped mid-lobby.

**The status line is never guessed at** - it is derived from `Net.status()` whenever anything
changes, so it cannot drift from what is true. Failure messages are more specific than the
state that produced them: a timeout says *"The server did not answer - is the server running
at 127.0.0.1:7777?"*, naming the address it tried, because "connection failed" tells a player
nothing they can act on.

**Buttons follow the connection, not just the selection.** Create and Join are disabled while
offline rather than left clickable so the player can discover the problem by pressing them.
The status line says what is wrong; the buttons say what is possible.

**Refresh becomes Reconnect while offline.** Without it a failed connection is a dead end
short of leaving the screen and coming back, which is a poor thing to ask of somebody whose
server was briefly down.

**Being dropped mid-lobby is not a separate case**, and that is the part worth keeping. Losing
the server emits exactly what being thrown out emits - same signals, same order, reason before
the change of lobby - so the room screen needs no code for it at all. It already knew how to
stop being in a lobby.

**Verified in the running game, not reasoned about:** with no server the browser showed the
timeout message with Create and Join disabled and the button reading *Reconnect*; starting a
server and pressing it reconnected and re-enabled them; creating a lobby and then killing the
server put the client back in the browser reading *"Lost connection to the server."*

**1.9 Leaving, explicit and otherwise.** ☑ *Built.* Back, Leave, quit, alt-F4, crash, pulled
cable. The server already treated a vanished peer as a departed one, and a lobby whose host
left already closed (D23); what 1.9 added is the polite case.

**A clean exit hangs up on the way out**, in `NetworkService._notification`, so other players
see somebody leave immediately instead of waiting for ENet to give up on a silent peer.
Measured: **0.13 s for a clean quit against 5.6 s for a kill.**

It is deliberately best effort and nothing depends on it. A crash cannot run shutdown code,
which is why the server must treat silence as departure regardless - this only makes the
common case fast, it does not make the uncommon case work. It also does NOT go through the
normal teardown, because by then half the listeners are themselves leaving the tree; all that
matters is that the socket says goodbye.


### Milestone 2 — load into the same match together  ✅ DONE

**Done meant:** the host presses Start, every client shows a loading screen listing who is
still loading, and when all are ready the match begins for everyone on the same tick. All of
that now happens, and the initial worlds are proven identical rather than assumed to be.

**2.1 The start handshake — built exactly as it was written.** The sequence in the plan
survived contact unchanged:

```
host presses Start
  -> server validates (host, enough players, not already starting, no match running)
  -> server LOCKS the lobby and announces countdown_started(5s)      <- D24
  -> [ any player leaves     -> countdown cancelled, lobby unlocks, stop ]
  -> [ the host may cancel   -> same, the same button says Cancel ]
  -> [ nobody may join while the countdown runs ]
  -> countdown reaches zero
  -> server builds MatchSetup, assigns match id and RNG seed
  -> server to all clients:  match_starting(MatchSetup)
  -> each client loads the game SCENE and reports it loaded
  -> server waits for ALL, with the D15 timeout
  -> server to all clients:  match_start(FINAL MatchSetup)
  -> everyone builds the world and begins
```

**One change to the plan, and it is load-bearing: loading is not building.** The plan had the
loading screen build the world and then report ready. It cannot, because of D15. If the
server may start without a client that never answered, then "no player area spawns for a
missing player" is only true when nothing has been placed by the time we know who is missing.
So the loading screen gets the `PackedScene` into memory - the slow part - and the world is
created afterwards, from the roster that arrives WITH the go signal. That roster is final and
can be shorter than the one announced.

**Where the countdown lives, and why it is not in `MatchStart`.** It manipulates lobby state
only - the lock, the cancel-on-leave, the "Starting..." row - so it stayed in `LobbyService`,
which owns all of that already. Cancel-on-leave in particular falls straight out of
`_remove_from_lobby`, where the leaving peer is already in hand. `MatchStart` begins at the
message the countdown sends and knows nothing about lobbies. The one thing crossing back is
`match_abandoned`, so a lobby whose match ended can stop reading "In progress".

**The countdown is announced once per whole second**, only when the number changes, to
everyone in the lobby. Nobody counts on their own clock, which is the whole point of D24: two
clients cannot show different numbers, and a client cannot start early by lying.

**Splitting `MatchStart` out of `Lobby` was not optional.** gdlint caps a class at 20 public
methods and `LobbyService` lands on exactly 20 with the countdown in it. That is a coarse
signal but it happened to point the right way: the two objects answer different questions.

**2.2 The loading scene.** `Scenes/UI/Menus/match_loading.tscn`, through
`ResourceLoader.load_threaded_request`, so the bar moves and the window keeps answering
rather than showing one frozen frame. The per-player list fell out of the handshake exactly
as predicted and cost almost nothing: the server already knows who has reported loaded, so it
broadcasts that list and the screen redraws. Rows are the lobby's own `LobbySlot` prefab,
which grew a `show_status()` - the same row saying a different thing about the same player.

**2.3 The server loads the match too, and 0.8 paid off.** `server_match.tscn` opened first
time with no camera, no HUD and no effects root, and reported `Match ready` with
`local_slot: 0`. Nothing needed changing for it. That is the whole return on the work done in
0.8.

**One thing 2.3 needed that was not in the plan: the way back.** A server that changes scene
into a match and stays there can host one match per *process*, which means restarting it
between every test. So when the last player of a match disconnects (D13 - out is out, so an
empty match is an over match) the process returns to `server_main.tscn` and unlocks the
lobby. `ServerMain` therefore may not assume it is running for the first time: it now finds
the socket already open and says so instead of reporting a failure to host.

**2.4 The timeout, built.** 60 s, then start with whoever is ready provided `min_players`
are, and - not in the plan - **tell the ones being left behind**. A client that hung long
enough to be dropped may well come back, and leaving it watching a loading bar for ever is
not a policy, it is a hang. Below `min_players` the whole thing is abandoned and everybody
goes back to the lobby with a reason.

**2.5 The checksum, and it works.** `WorldChecksum` walks the setup, the areas and the unit
REGISTRY - not the scene tree, because the registry is keyed by the id both machines call a
unit by, so ids handed out in a different order show up as a mismatch rather than hiding
behind identical positions. Positions are quantised to a millimetre first: a checksum over
raw floats compares bit patterns rather than places.

`local_slot` is deliberately excluded. It is the one field of a setup that is SUPPOSED to
differ per machine, and a server plays no slot at all.

**Proven by falsification**, which is the only way a checksum result means anything: shifting
one player area by 0.001 on the clients only made both clients report the same wrong number
and the server report the right one, and the mismatch was logged per peer. Reverted
immediately after.

**What the first end-to-end run actually found:** one bug. `server_main.tscn` had no
`BootConfig` on its `References`, so the server knew every path except the one to its own
match scene. It failed loudly at the point of use, which is exactly what the path-not-
PackedScene rule is for.

**Cost:** one new autoload, one new screen, one new util, and about a dozen lines each in
`LobbyService`, `LobbyRoom`, `MenuNavigation` and `Main`. Nothing in the simulation changed.

**Verified in the running game, by the user**: the countdown on both screens showing the same
number, the button reading `Cancel Start (n)` for the host and `Starting...` for everybody
else, the browser row dimming to "Starting...", and both windows landing in the match with
each camera on its own builder.

**The one thing that could not be judged: the loading screen.** With both instances on one PC
it goes past in well under a second, and two local clients load at the same speed, so
"waiting for Bob..." never actually appears. Seeing it properly needs a deliberate delay on
one client, or a second machine. Worth doing before trusting the readiness list, and worth
knowing that the D15 timeout has therefore only been exercised in code, not by a real slow
client.

**What is deliberately still true at the end of it:** the match is NOT synchronised. Both
players see two lanes built from one seed and then diverge from their first tick, because no
command goes anywhere yet. That is Milestone 3.


### Milestone 3 — playable and synchronised  ✅ DONE, except 3.3 and 3.7

**Done means:** two players on separate machines build, send and see each other's lives drop,
with both views agreeing. They do.

**3.0 The gameplay the milestone assumed (D25).** Not in the plan, and found by reading the
success criterion against the code: **lives were never implemented** (`PlayerState` said
"lives later"), a creep reaching the end just vanished, and a send went into your OWN lane -
`game_rules.md` said so explicitly. All three were already specified there, so this was
implementation rather than design, but it had to be built before any of the networking could
be judged.

- **The ring** lives on `PlayerManager`, which already holds everything per-player, and is
  resolved on EVERY send rather than cached. That is what lets the ring close over an
  eliminated player with nothing to invalidate.
- **A life is stolen, not lost.** `PlayerState.steal_life_from()` moves one, in one method,
  because half a steal would quietly destroy or invent a life.
- **A leak RECYCLES the creep** rather than removing it: same health, next maze in ring order,
  which in a 1v1 is the same maze again. Only a creep with nowhere to go is despawned - a
  single-lane run, which is what keeps solo testing working unchanged.

Verified before anything networked: two lanes, one send, lives 100/100 → 103/97 with the pool
conserved, and the same three creeps walking round again to leak a second time.

**3.1 The command layer.** `CommandController` no longer calls `ability.execute()` anywhere;
every order goes through `Commands.submit()`. Offline it applies at once, on a client it is
sent, on the server it is validated and applied. One road, three answers.

**The one line that makes it safe:** the sender's slot is taken from the peer id the transport
supplies and OVERWRITES whatever arrived in the message. Everything else follows from it - the
worst a modified client can do is issue orders as itself.

**What the server checks, and what it deliberately does not.** It checks the two things only
it can: that the player owns each unit, and that the ability is really on that unit's card. It
does NOT re-implement gold, creep stock, placement legality or the maze-blocking rule, because
running the same `ability.execute()` over its own authoritative world already refuses all of
them. A second copy of those rules would be a second place for them to drift.

**The card is a TREE, not a list**, and getting that wrong rejected every build order in the
first live test. `current_abilities()` answers the top row; Build sits there as a submenu
holding the four towers, so an ordinary "build a sniper tower" names an ability that is
nowhere in that row. The check walks submenus, with a seen-set, because a card that referred
back into itself would otherwise be an infinite descent rather than a refused order.

**3.2 Replication, phase A.** The whole world, every tick, unreliable.

Being COMPLETE is what makes it simple: a snapshot that carries everything needs no spawn
message, no despawn message and no reconciliation. A unit in it exists, a unit not in it is
gone, and a client that missed a packet is corrected 50 ms later. That is also why it is
unreliable - re-sending a stale world would be worse than skipping it.

Sent as flat `PackedFloat32Array`s with a fixed stride rather than an array of dictionaries,
which would spend more bytes on key names than on values twenty times a second. A float32 is
exact on integers to 16.7 million, far past any id this game hands out.

**A spawn has to say WHAT was spawned**, and that needed the same answer D12 gave for
abilities: an authored `UnitStats.unit_type_id`, with a `UnitTypeRegistry` scanned out of the
folder named by `ContentConfig`. A resource path would have been forty bytes per unit per tick
and would have turned a renamed file into a silent desync.

**Two things fell out of writing it that the plan did not mention:**

- **A building's grid cell is derived, not sent.** `place()` puts a tower at its footprint's
  world centre, so snapping that centre back gives the cell - and the client's grid has to
  know, or its build preview would draw a green ghost on an occupied square.
- **`Building._exit_tree()` never called `super()`**, so every tower ever sold kept its entry
  in the unit registry. Harmless while nothing walked the registry; replication walks it every
  tick. A pre-existing bug found by giving old code a new reader.

**3.4 Clients stop being authoritative — completely.** With no prediction in the first version
(D17) there is no half-owned state to hold, so the honest implementation is that a client runs
NO simulation at all: `MatchSession.is_authority()` gates every gameplay `_physics_process`,
and the world is moved by snapshots.

**One deliberate exception, and it is presentation.** Attacks and projectiles still run on a
client - towers aim and shots fly - but `Unit.take_damage()` refuses to apply anything unless
this machine is the authority. So the shooting is visible and the outcome is the server's. A
client tower may briefly aim at a different creep than the server chose; that is cosmetic, and
it is the shape 3.3 turns into real prediction.

**3.5 Reconciliation — nothing to build, and that is the finding.** Drift is what happens when
two machines simulate the same thing and disagree. Under 3.4 only one machine simulates, so
there is nothing to reconcile and nothing that can drift. The initial-world checksum from 2.5
still runs and still proves both clients built the same world. **This step comes back the
moment 3.3 does**, because that is what puts a simulation back on the client.

**3.6 The disconnect policy (D13, D14, D26).** A 10 second hold, on top of the ~5.6 s ENet
already takes to notice a hard-killed client; a deliberate leave skips it. `MatchStart` says
WHO is gone, `PlayerManager` erases their maze, and everything after that is rules that
already existed - creeps walk straight through, each leak steals a life for whoever sends into
that lane, and the leaver is eliminated the ordinary way. Verified end to end: lives went
101/99 in the survivor's favour with no elimination code anywhere.

**Making the goodbye actually arrive took a measurement.** A deliberate leave behaved exactly
like a crash, and the reason is that an rpc does not travel when it is CALLED - it is handed
to ENet, which transmits on the multiplayer poll at the top of the next frame. Closing the
socket in the same frame threw the goodbye away. Flushing the ENet host did not help; waiting
two frames - one complete poll cycle - did. That ordering now lives in
`MatchStart.leave_match()` so no caller can get it wrong.

**Added after the first play test, and worth knowing why:**

- **Yaw is in the snapshot.** Units on a client walked the maze facing whichever way they
  spawned, because a client runs no movement code (3.4) and so has nothing to turn them with.
  One float per unit; the alternative - deriving facing from the position delta between
  snapshots - is cheaper but jitters when a unit stops.
- **Value and placement ride with gold, income and lives.** Both are computed by the
  authority. Value is WALKED over a player's buildings rather than accumulated, because a
  running total needs correcting on every sale, refund and destroyed tower, and one missed
  hook makes it wrong for the rest of the match. Same reasoning for the population count.
- **The match now ends.** A player at zero lives is eliminated, given a placement counting
  down from the number still playing, and has everything of theirs taken off the field - the
  same `erase_player()` a disconnect uses (D14). With one player left the income clock stops
  and nothing more can be sent. There is no end screen; players leave through the in-game
  menu.
- **`erase_player()` removes, it does not kill**, and the difference is load-bearing. It
  frees the nodes rather than calling `_die()`, so no death passive fires - a Skeleton does
  not get back up - and no bounty is paid to whoever owns the lane a creep happened to be
  standing in. Somebody leaving a match is not a kill and must not pay like one. It walks the
  UNIT REGISTRY rather than the player's own area, because the creeps they sent are standing
  in somebody else's lane and are still theirs.

**3.3 and 3.7 are deliberately not done.** The roadmap recommends shipping phase A before
phase B so the optimisation is measured against something real, and 3.7 says "measure before
optimising" in as many words. Both now have something to be measured against.

**What is still true and worth knowing:**

- **An order takes a round trip.** Nothing moves until the server answers (D17). On localhost
  that is invisible; at 80 ms it is what 3.7 exists to judge.
- **Bandwidth is ugly and known.** Roughly 36 bytes per unit per tick, whole world, 20 Hz.
  Fine for a 1v1 on a LAN, and nowhere near fifteen players. That is 3.3.
- **A client sees no unit it has no content for.** A snapshot naming an unknown
  `unit_type_id` is reported and skipped rather than guessed at, which is what a mismatched
  build looks like.


### After Milestone 3 — the first play test

Everything here came from playing the game rather than from the plan, which is the point of
recording it separately.

**Units did not face where they walked**, and the cause was not the facing maths - `Creep`
had always called `_face_direction`. A client runs no movement code (3.4), so it had NOTHING
to turn a unit with, and every creep walked the maze facing whichever way it spawned. Yaw
joined the snapshot. The lesson generalises: anything a client can SEE but does not compute
has to be sent, and the list of those grows every time simulation is moved off the client.

**The build grid became a builder ability** in card slot 9, and needed a genuinely new idea
to do it properly. Routing it through `Commands` would have asked a server with no grid, no
camera and no selection to decide something it cannot see - so `UnitAbility.is_local_only()`
now marks presentation that must never become a command. It is the line multiplayer.md
already drew around the build ghost and the range overlay, made into something an ability can
declare. False by default, deliberately: an ability that forgets ends up validated by the
server, which is the safe way round.

It also covers EVERY maze rather than only your own, on the user's call - where a tower can
go is worth reading in an opponent's lane, and half the board in a different state would be a
second thing to keep track of.

**Two UI panels replaced three labels.** Gold, population and the income countdown across the
top middle; name, life, income, value and placement top right, for every player rather than
just the local one - a life is STOLEN rather than lost, so a readout showing one half of that
describes half the event.

**Value and population are WALKED, not accumulated**, and for the same reason: a running
total needs correcting on every sale, refund, destroyed tower, death, leak and recycle, and
one missed hook makes it wrong for the rest of the match. Both are cheap enough to compute
from scratch and cannot drift.

**The match ends now**, in the smallest form that works: a player at zero lives is eliminated
and given a placement counting down from the number still playing, everything they own leaves
the field, and with one player left the income clock stops where it is and nothing more can
be sent. There is no end screen (L2); players leave through the in-game menu.

**`erase_player()` removes, it does not kill**, and that distinction is the whole of it. It
frees the nodes rather than calling `_die()`, so no death passive fires - a Skeleton does not
get back up - and no bounty is paid to whoever owns the lane a creep happened to be standing
in. Somebody leaving a match is not a kill and must not pay like one. Proven with Skeletons
on purpose: five units gone, and the other player's gold never moved.

It also walks the UNIT REGISTRY rather than the player's own area, because the creeps they
sent are standing in somebody else's lane and are still theirs. That incidentally closed the
oddity §14.1 recorded as harmless - a leak stealing a life FOR a player on their way out.

**Double clicking a lobby row joins it**, taken from the event's own `double_click` flag so
it uses the player's system setting, and routed through the same path as the Join button so
every refusal reason still applies.

**One test lied, and it is worth knowing why.** The first double-click run reported the row
as `disabled`, which looked like the guard being wrong. It was not: a lobby left over on a
long-running server was genuinely 2/2 with a match in progress, so refusing it was correct
and the test had simply never exercised the case. Restarting the server made it pass. A
negative result only counts if the test reached the right state.

---

### Testing all of this on one PC

**No, you do not need to export a build.** Godot runs as many instances of the project as
you like straight from the editor, each with its own command line and its own feature tags.

**Debug → Customize Run Instances…**

- Tick *Enable Multiple Instances* and pick a count.
- Each instance gets its own **Launch Arguments** and its own **Feature Tags**.
- Press Run (F5) and they all start together.

The feature tags are the part that matters here, because `OS.has_feature("dedicated_server")`
is exactly what the boot dispatch in 1.1 keys on. Give instance 1 the `dedicated_server`
tag and it boots as the server; leave the others alone and they boot as clients. **The same
line of code selects client or server in the editor and in a real exported build**, with no
`if OS.is_debug_build()` special case anywhere.

**Setting the tag is two clicks, and missing them is the obvious first mistake.** Ticking
*Enable Multiple Instances* is NOT enough - it gives you N identical clients. Each instance's
tag field has its own **override checkbox**, and the tag is ignored until it is ticked:

> Debug → Customize Run Instances… → select **Instance 1** → tick **Override Main Feature
> Tags** → type `dedicated_server` in that instance's Feature Tags field.

What the editor stored is readable at `.godot/editor/project_metadata.cfg` under
`[debug_options] run_instances_config`, which is the quickest way to check the tag really
landed:

```
run_instances_config=Array[Dictionary]([{ "features": "dedicated_server",
										  "override_features": true }, { ... }])
```

**How the tag actually reaches the game, which is worth knowing:** not as a command-line
flag - there is no such engine flag, verified against the binary. The editor passes it to the
child process in the environment variable **`GODOT_EDITOR_CUSTOM_FEATURES`**, and the engine
folds it into its custom features so `OS.has_feature()` answers true. Proven by launching the
project with only that variable set and no arguments at all: it booted as the server with
`Feature tag dedicated_server: true`.

That is also how a dev server gets launched from a plain shell or a service script later,
with no editor and no export preset:

```
GODOT_EDITOR_CUSTOM_FEATURES=dedicated_server  godot --path <project> --headless
godot --path <project> --headless -- --server        # or the argument, same result
```

**The boot line is the verification**, and it carries the evidence rather than just the
verdict, because "role: client" alone cannot tell an absent tag from a misspelled argument:

```
[Boot] Boot dispatching { "role": server, "scene": res://Scenes/Server/server_main.tscn,
						  "tag": true, "args": [], "headless": false }
```

**Or run the server from a terminal instead**, which is what `server.md` documents and the
better loop in practice: F5 restarts every editor instance, so an editor-hosted server dies
and restarts on every client iteration, while a terminal one just keeps running. That leaves
only two editor instances, both plain clients with no tags.

A 1v1 test entirely inside the editor is three instances:

| Instance | Feature tags | Launch arguments | Boots as |
| --- | --- | --- | --- |
| 1 | `dedicated_server` | — | the server |
| 2 | — | — | client A |
| 3 | — | — | client B |

Worth knowing:

- Support a `--server` launch argument as well as the feature tag. The tag is the clean
  answer, but an argument is what you need to start a second server on a different port, or
  to point a client at a non-default address while testing.
- The client's server address belongs in `NetworkConfig` (1.2) with a command-line override,
  so instance 3 can be aimed somewhere else without editing a resource.
- Windows will ask about the firewall the first time something listens on a port. Allow it
  for private networks.
- Three instances plus the editor is a lot of windows. Godot remembers per-instance window
  positions, so it is worth arranging them once.
- Once it works on one PC, a second machine on the same LAN is only a matter of pointing its
  client at the first machine's address — the code path is identical.
- **What one PC cannot show you is anything about TIME.** Two local clients load at the same
  speed and talk over a 0 ms link, so the loading screen flashes past, "waiting for Bob..."
  never appears, and every ordering bug that needs latency to show up stays hidden. A second
  machine, or an injected delay (§14.5), is the only way to see those.

### Most likely to be underestimated

- **1.8**, the connection failure states. Usually larger than the happy path.
- **0.5**, render interpolation. Invisible in a plan, extremely visible in the game.
- **3.5**, drift. The bug class that only shows up in real matches on real machines.
- **2.4 and 3.6**, the two policy decisions that are cheap now and structural later.

In the event, 2.1 and 2.2 came in about as estimated and the surprise was elsewhere: the
ORDER of loading and building (§12 → Milestone 2), and the server needing a way back out of a
match scene. Neither was visible in the plan.

---

## 13. The reference template — adopt / avoid

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

## 14. Settled questions, and the detail behind them

All of §14 is now answered. Kept because the reasoning is worth having when the code gets
written, and because a few small details underneath are still open.

### 14.1 Disconnects (D13, D14)

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
  **Measured while building 1.3: ENet itself takes about 5.6 s** to report a client that was
  hard-killed on localhost, with no cooperation from the dying process. So roughly five
  seconds of grace already exist for free, and any hold we add is *on top* of that, not
  instead of it. **A deliberate Leave was then measured at 0.13 s** - 43x faster - because
  1.9 closes the peer on the way out, so the server hears a goodbye rather than waiting for
  silence. That is what makes "a deliberate Leave skips the hold" implementable rather than
  merely desirable: the two cases are already distinguishable by how fast they arrive.
- **Whether the towers are refunded, recycled or simply deleted** when the maze is erased.
  Deletion is simplest and nobody is left to receive gold.

### 14.2 The loading screen timeout (D15)

Wait **60 seconds**. Then start without whoever has not reported ready, provided at least
`min_players` are. **No player area spawns for a missing player** — they were never in the
match, rather than being in it and immediately dead.

Falls out of the design already built: `MatchSetup` carries the player list, so the server
simply builds it from the players who made it. Nothing downstream needs to know that
somebody was dropped.

One consequence worth remembering, because it will look like a bug otherwise:
**starting lives depend on the player count.** The formula in `game_rules.md` is
`max(25, 200 / players)` rounded to the nearest 5. A four-player lobby that starts as three
gives everyone 65 lives instead of 50. That is correct — the pool is shared — but the lobby
will have shown one number and the match another.

### 14.3 One process per match (D16)

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

### 14.4 Feedback now, prediction later (D17)

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

### 14.5 Where the dev server runs (D18)

Locally in the office, on the user's own machine for the first tests, moving later if
needed. The address is one line in `NetworkConfig`, so nothing about the code changes when
it moves.

The one thing a local server hides is **latency**: at 0 ms, every ordering and timing bug
stays invisible and then appears for real players at 80 ms. Worth injecting artificial delay
and packet loss before trusting a build — on Windows a tool such as *clumsy* can do this to
a local connection.

### 14.6 Answered elsewhere

- ~~Simulation tick rate~~ — 20 Hz, D11 and §5.5.
- ~~The session autoload~~ — D10.
- ~~How a command names an ability~~ — D12.
