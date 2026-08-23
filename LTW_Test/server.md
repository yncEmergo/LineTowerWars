# Running the server

How to start, stop and aim the dedicated server. **Controls only** — what the server *is* and
why it exists is `multiplayer.md`; the rules are `game_rules.md`.

**Keep this file updated as the server gains controls.**

---

## The one-line version

In the VS Code terminal (it is PowerShell), from the project folder:

```powershell
.\run_server.ps1      # start it
.\stop_server.ps1     # stop it, from any terminal
```

**Ctrl+C** also stops it, if you started it in the terminal you are looking at.
`.\stop_server.ps1 -List` shows what is running without touching it.

Starting a second server on the same port is refused with a message rather than
allowed to fail deep inside ENet. Two servers on DIFFERENT ports is fine, so
`.\run_server.ps1 -Port 7778` skips that check.

**Claude starts and stops the server as part of its own work** — stopping it before
changing server code and starting it again afterwards — so there should normally be one
running and ready to test against. `.\stop_server.ps1 -List` is how you check.

---

## What you should see

```
Starting the LTW dedicated server (headless). Ctrl+C to stop.

Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org
[Boot] Boot dispatching { "role": server, "scene": res://Scenes/Server/server_main.tscn, ... }
[server] Server process started
[server] Process id: 26628
[server] Display server: headless
[server] Simulation tick: 20 Hz
[server] Listening on port 7777, up to 32 peers
```

The line that matters is the last one. **`Listening on port ...` means the server is up.**
Before that line it is not accepting anything.

`"role": server` on the Boot line is the other one to check — if it says `client`, the server
argument did not arrive and you are looking at a game, not a server.

Then, as clients come and go:

```
[server] Peer 1003108492 connected
[server] Peer 1003108492 disconnected
```

A *peer* is one connected program. See `multiplayer.md` §2 for how a peer id differs from a
player slot.

---

## Options

| What you want | Command |
| --- | --- |
| Normal run, no window | `.\run_server.ps1` |
| Watch the log in a window | `.\run_server.ps1 -Windowed` |
| A different port | `.\run_server.ps1 -Port 7778` |
| Two servers at once | run the second with `-Port 7778` |
| Godot lives somewhere else | `.\run_server.ps1 -Godot "C:\path\to\Godot.exe"` |
| Stop it | `.\stop_server.ps1` |
| See what is running | `.\stop_server.ps1 -List` |

`-Windowed` gives you the same log in a window instead of the terminal — occasionally handy,
but the terminal is the better place for it.

### Without the script

The script only assembles this:

```powershell
& "C:\Users\Emergo Entertainment\Desktop\Godot 4.7.1.exe" --path . --headless -- --server
```

The **`--` separator is required**. Godot treats an unrecognised argument before it as an
engine argument and refuses to start, so `--server` has to come after it.

### Telling the script where Godot is

It looks in three places, in order: the `-Godot` argument, the `GODOT` environment variable,
then `Desktop\Godot 4.7.1.exe`. To set it for a terminal session:

```powershell
$env:GODOT = "C:\path\to\Godot.exe"
```

---

## Connecting clients to it

With the server running in a terminal, you only need **client** instances in the editor —
no feature tags, since a plain instance is a client:

> Debug → Customize Run Instances… → *Enable Multiple Instances*, count **2**, no tags.

Press F5, then **Multiplayer** in each window. The status line under the lobby list is the
truth:

| Status line | Meaning |
| --- | --- |
| `Connecting to 127.0.0.1:7777...` | dialling |
| `Connected to 127.0.0.1:7777.` | in |
| `The server did not answer - is the server running at ...?` | nothing listening there |

**This is the better setup than tagging one editor instance as the server**, for one reason:
F5 restarts every editor instance, so a tagged server dies and restarts every time you
iterate on the client. A terminal server just keeps running.

### Aiming a client somewhere else

Same two arguments, on the client:

```powershell
& "C:\path\to\Godot.exe" --path . -- --address 192.168.1.20 --port 7777
```

For an editor instance, put `-- --address 192.168.1.20` in that instance's **Launch
Arguments** in the run instances dialog.

---

## Settings

Defaults live in `Resources/Config/network_config.tres` — port, address, max peers, connect
timeout. The command line overrides them per run; edit the resource to change what "normal"
means.

The one that matters when the server moves off this machine is `server_address`, which is
what clients dial. The server itself does not use it.

---

## When it does not work

**`Failed to open the port: Could not open the server port`**
Something already holds it — usually a server you forgot to Ctrl+C. Find it:

```powershell
Get-Process | Where-Object { $_.ProcessName -like "*odot*" }
```

Simpler: `.\stop_server.ps1`, which finds it by command line rather than by name — matching
on the name alone would also catch the editor and every game window it launched. A server
that has only just been killed can hold the port for a moment longer, which is why the stop
script waits briefly before returning.

**Windows firewall prompt on first run**
Allow it for **private** networks. Without that, nothing off this machine can reach it.

**A client says the server did not answer**
It waited the configured timeout (5 s) and gave up. Either the server is not running, is on
another port, or a firewall is in the way. Check the server terminal for `Listening on port`.

**The Boot line says `"role": client`**
The `--server` argument did not arrive — nearly always a missing `--` separator.

**An editor window stuck on "Game starting..."**
That is the editor's own embedded Game panel, not your game and not the server - the string
appears nowhere in this project. It is Editor Settings -> Run -> Window Placement -> **Game
Embed Mode**; set it to *Disabled* so every instance opens as its own window. Running the
server from a terminal sidesteps it either way.

**A client vanishes but the server does not notice for ~5 seconds**
Expected. A client that closes properly is reported instantly; one that was killed, crashed
or unplugged takes ENet about 5.6 s to give up on. See `multiplayer.md` §14.1.

---

## Matches

The server hosts lobbies and runs matches. When a lobby's host presses Start, the five second
countdown runs **on the server**, and when it fires the process opens the match scene:

```
[server] ... Start countdown { "lobby": lobby-1, "seconds": 5.0 }
[server] ... Match starting { "lobby": lobby-1, "match": match-1, "players": 2, ... }
[server] ... Match announced { "match": match-1, "players": 2, "timeout": 60.0 }
[server] ... Client loaded { "peer": ..., "ready": 2, "of": 2 }
[server] ... Match start { "match": match-1, "players": 2 }
[server] ... Match ready { "players": 2, "local_slot": 0, ... }
[server] ... Initial world agrees { "peer": ..., "sum": 2178113725 }
```

**`Initial world agrees` is the line to look for.** It means that client built the same world
the server did. `Initial world DIFFERS from the server` is a real bug and is logged as an
error, per client.

**One match at a time, and you do not have to restart it.** One process runs the lobby and
the matches for now, so a second Start while a match is running is refused with a message on
the host's screen. When the last player of a match disconnects, the process goes back to
listening by itself:

```
[server] Match over, everybody has left match-1
[server] Back from a match, still listening on port 7777
```

So the loop is: start the server once, play as many matches as you like against it.

**The server is the only machine that simulates.** Clients send orders and draw what comes
back, so the lines worth watching during a match are the ones about orders it refused:

```
[server] ... Command rejected { "command": slot 2, ability 21, units [4], ... ,
                                "why": ability 21 is not on unit 4's card }
```

A rejection is not normally a bug in the client - a tower can be sold while an order for it is
in flight - but a REPEATED one is, and it names the ability and the unit so it can be chased.

**When somebody drops:**

```
[server] Player went quiet, holding { "peer": ..., "seconds": 10.0 }
[server] Player did not come back ...
[server] Player dropped from the match { "peer": ..., "slot": 2, "why": timed out, ... }
[server] Maze erased { "player": 2, "towers": 1 }
```

A player who left through the in-match menu skips the hold and reads `"why": left the match`
instead. Either way the match carries on and their lives drain away through ordinary leaks -
that is the rule (D14), not a bug.

**While a match is running there is no status line and no log view** — the window, if you ran
it with `-Windowed`, belongs to the match scene. Everything still goes to stdout, which is
where you are reading it anyway.
