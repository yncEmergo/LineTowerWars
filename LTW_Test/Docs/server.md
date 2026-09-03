# Running the server

How to start, stop and aim the dedicated server. **Controls only** — what the server *is* and
why it exists is `multiplayer.md`; the rules are `game_rules.md`.

**Keep this file updated as the server gains controls.**

---

## The one-line version

In the VS Code terminal (it is PowerShell), from the project folder:

```powershell
.\Tools\run_server.ps1      # start it
.\Tools\stop_server.ps1     # stop it, from any terminal
```

**Ctrl+C** also stops it, if you started it in the terminal you are looking at.
`.\Tools\stop_server.ps1 -List` shows what is running without touching it.

Starting a second server on the same port is refused with a message rather than
allowed to fail deep inside ENet. Two servers on DIFFERENT ports is fine, so
`.\Tools\run_server.ps1 -Port 7778` skips that check.

**Claude starts and stops the server as part of its own work** — stopping it before
changing server code and starting it again afterwards — so there should normally be one
running and ready to test against. `.\Tools\stop_server.ps1 -List` is how you check.

---

## What you should see

```
Starting the LTW dedicated server (headless). Ctrl+C to stop.

Godot Engine v4.7.x.stable.official.<hash> - https://godotengine.org
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
| Normal run, no window | `.\Tools\run_server.ps1` |
| Watch the log in a window | `.\Tools\run_server.ps1 -Windowed` |
| A different port | `.\Tools\run_server.ps1 -Port 7778` |
| Two servers at once | run the second with `-Port 7778` |
| Godot lives somewhere else | `.\Tools\run_server.ps1 -Godot "C:\path\to\Godot.exe"` |
| Stop it | `.\Tools\stop_server.ps1` |
| See what is running | `.\Tools\stop_server.ps1 -List` |

`-Windowed` gives you the same log in a window instead of the terminal — occasionally handy,
but the terminal is the better place for it.

### Without the script

The script only assembles this:

```powershell
& $env:GODOT --path . --headless -- --server
```

The **`--` separator is required**. Godot treats an unrecognised argument before it as an
engine argument and refuses to start, so `--server` has to come after it.

### Telling the script where Godot is

Where the editor lives is a **per-machine** detail, not a project setting — the repo is
developed on more than one PC and they do not agree on the path or the patch version. So the
script never hardcodes yours. It looks in three places, in order:

1. the `-Godot` argument
2. the `GODOT` environment variable
3. a legacy `Desktop\Godot 4.7.1.exe` fallback, kept only so an already-working machine that
   never set `GODOT` does not break

**Set `GODOT` once per machine** and the fallback stops mattering:

```powershell
# permanent, survives reboots — run once per PC, then reopen the terminal
[Environment]::SetEnvironmentVariable('GODOT', 'C:\path\to\Godot.exe', 'User')

# or just this terminal session
$env:GODOT = "C:\path\to\Godot.exe"
```

Point it at the **real `.exe`**, not a `.lnk` shortcut — PowerShell's call operator cannot
launch a shortcut.

Anything that inherits the environment — the Godot editor, a terminal, the MCP server — only
sees the variable if it was **started after** it was set.

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

## Testing across two PCs

Two machines in different buildings, no rented server and no router configuration:
**Tailscale**, a free VPN mesh that gives each PC a permanent address and connects them
directly. This is the DEV LOOP only — testers on a public download cannot be asked to
install it, and that is the point at which a publicly reachable server starts being worth
paying for. Nothing set up here is wasted when that happens: it is the same address list.

**Why not a port forward.** A PC behind a router has no address the other one can dial, so
the router has to be told to send UDP 7777 inwards. That is a router login, an address that
changes every time the ISP reconnects, and — on DS-Lite or cable, which is most German
connections — a carrier-grade NAT that makes it impossible outright rather than merely
tedious. Tailscale has none of those three failure modes.

### Setting a machine up

Once per PC and never again. Both lines are PowerShell.

```powershell
winget install --id tailscale.tailscale --accept-source-agreements --accept-package-agreements --silent
& "C:\Program Files\Tailscale\tailscale.exe" up --hostname=ltw-home
```

`up` prints a login URL and waits. Open it, sign in with **the same account on both
machines** — the account is what puts them on one network — and the command returns by
itself. An agent cannot do this step: it is a browser sign-in and needs a human.

**The hostname is a convention worth keeping**: `ltw-office`, `ltw-home`, and `ltw-<place>`
for a third, so `tailscale status` reads as a sentence instead of as two Windows machine
names nobody chose.

Read the machine's own address back with:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" ip -4
```

It is a `100.x.y.z` address and it is permanent for as long as that machine stays on the
tailnet. `tailscale status` lists every machine and whether it is currently reachable.

### What the project needs to know

The addresses a client dials live in `Resources/Config/network_config.tres`, and **that file
is the authority** — this document deliberately does not repeat them, because a copy here is
the one that would go stale. Add the new machine's `100.x` address to the list there. The
client tries each candidate in turn and takes the first that answers, so either PC can be the
server on any given day and neither needs a rebuild to swap roles.

### The firewall, on whichever PC is running the server

Windows blocks unsolicited incoming traffic. Tailscale adds rules for its own traffic on
install, but the game's port is the game's problem. In PowerShell **as Administrator**, on
the server machine only:

```powershell
New-NetFirewallRule -DisplayName "LTW dedicated server" -Direction Inbound `
  -Protocol UDP -LocalPort 7777 -Action Allow -Profile Private,Public
```

**UDP, not TCP** — ENet is UDP (`multiplayer.md` D5), so a TCP rule allows nothing and a TCP
reachability test proves nothing. The client machine needs no rule: it makes an outbound
connection, which Windows permits by default.

**Do not assume Godot's own rule covers it, and this is the trap worth reading twice.**
Windows offers to create a rule the first time Godot opens a socket, and the rule it makes is
for THAT EXECUTABLE on whichever profile the machine was on at the time — in practice the
Wi-Fi network, which is *Public*. Tailscale's adapter is classified **Private**. So the
existing "Godot Engine" rule can be enabled, inbound, allow, UDP, and still not apply to a
single packet arriving over Tailscale, because it is scoped to the wrong profile. Nothing
reports this: the server logs `Listening on port 7777` exactly as it always does and the
other machine simply never gets an answer.

Check both halves before believing a rule exists:

```powershell
Get-NetConnectionProfile | Select-Object Name,InterfaceAlias,NetworkCategory
Get-NetFirewallRule -DisplayName "LTW dedicated server" | Select-Object Enabled,Direction,Action,Profile
```

The first says which profile Tailscale is on, the second says which profiles the rule covers.
They have to overlap. The rule above names `Private,Public` so that they always do.

A rule on the PORT rather than on the executable is also what survives the move to an
exported build, which is a different `.exe` that Godot's own rule knows nothing about.

### Checking it works, before blaming the game

In this order, stopping at the first that fails:

| Check | How | Passing means |
| --- | --- | --- |
| Both on the tailnet | `tailscale status` | the other machine is listed and not `offline` |
| The network reaches it | `tailscale ping ltw-home` | packets arrive. It also says `direct` or `via DERP` — relayed still works, it just adds latency |
| The server is accepting | the `Listening on port` line in the server terminal | the game is up, not just the machine |

A `tailscale ping` that answers while the game still cannot connect is the firewall rule
missing, nearly every time.

---

## Settings

Defaults live in `Resources/Config/network_config.tres` — port, addresses, max peers, connect
timeout, and the protocol version. The command line overrides the first two per run; edit the
resource to change what "normal" means.

The one that matters when the server moves off this machine is `server_addresses`, the LIST a
client dials through in order, taking the first that answers. The server itself does not use
it. `--address` collapses that list to the one address named, which is what a deliberate
one-off test wants.

`protocol_version` is the other one worth knowing about: a client stating a different number
is refused by the server with a message naming both builds, rather than being let in to
desync. Bump it whenever two builds stop being able to play together — the property's own
comment says what counts.

---

## When it does not work

**`Failed to open the port: Could not open the server port`**
Something already holds it — usually a server you forgot to Ctrl+C. Find it:

```powershell
Get-Process | Where-Object { $_.ProcessName -like "*odot*" }
```

Simpler: `.\Tools\stop_server.ps1`, which finds it by command line rather than by name — matching
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
