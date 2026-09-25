# Multi-match: the box steps, as commands

**TEMPORARY.** Written 2026-09-25, when P2, P3 and P4 landed. Delete it when P5 and P6 have
run and `server.md` carries the controls they add.

**This file exists because Claude cannot reach the box.** ssh from a tool call is refused, so
every step below is the owner's to run. They are in order, each with what it is for, what
success looks like, what failure looks like, and when to stop and send the output back.

**Nothing here is urgent.** `NetworkConfig.match_processes_enabled` ships false, so the code
that is already on `main` changes nothing for anybody. The server can be deployed today, or
not, without any of this.

Read `multi-match.md` for what the thing IS. This is only how to run it.

---

## 0. Two gates, before anything else

Both are measurements, not decisions, and both can be done in any order.

### Gate 1: can testers reach a match port?

**What it is for.** Each match listens on its own port, from a range. If a tester's network
lets them reach 7777 but not 7800, the whole shape needs a forwarder on the public port
instead - which changes the lobby's announce and the client's dial. Better to know now.

On the box, open one port and start a throwaway server on it:

```
sudo ufw allow 7800/udp
systemd-run --unit=ltw-porttest --uid=ltw --gid=ltw \
  /opt/godot/godot --headless --path /srv/ltw/LTW_Test --log-file /tmp/ltw-porttest.log \
  -- --server --port 7800
```

`--log-file` is not optional: the test server runs as `ltw` and shares the live lobby's
`user://`, so without it its boot rotates and truncates the lobby's own log.

Then have **a tester on their own network** (not you, not Tailscale) start the game with:

```
LTW.exe -- --port 7800
```

- **Success:** they reach the lobby browser and can create a lobby.
- **Failure:** "could not reach the server". **Stop and send that back** - it means the match
  range is unreachable and P3's announce has to be revised before the release.

Afterwards:

```
systemctl stop ltw-porttest
sudo ufw delete allow 7800/udp
```

### Gate 2: does a Godot process spawn a Godot process on LINUX?

**What it is for.** The Windows half is measured and works. The Linux half was read from the
engine source and never run, and the whole supervisor sits on it. Five minutes.

On the box:

```
sudo -u ltw /opt/godot/godot --headless --path /srv/ltw/LTW_Test --log-file /tmp/spawn.log \
  -- --match-server --match-id spawntest --match-file /tmp/nope.match --port 7801
echo "exit code: $?"
```

- **Success:** exit code **66**, and `/tmp/spawn.log` ends with "There is no match file where
  this process was told to look". That proves the match role boots, reads its arguments, and
  chooses the right exit code on Linux.
- **Failure:** any other code, or a log that stops before `Match process starting`. **Stop and
  send the log back.**

---

## 1. Deploy what is already on `main`

**What it is for.** Getting the P0 fix and everything since onto the box, with the handoff
still switched off. Nothing about matches changes; the loading gate stops starting matches
without players who have gone.

From the project root on your PC:

```powershell
.\Tools\deploy_server.ps1
```

**Check for connected players first** - the script says how many matches a restart is about to
cancel. Stopping the service under a live match makes every client its own authority.

- **Success:** the script asserts the service pid changed, and the journal shows
  `Match processes are OFF, this server runs one match itself (D19)`.
- **That line is the point.** It is the positive control for the switch: if it says ON, the
  shipped `.tres` has been changed and the release has happened by accident.

**Hand out a client build the same day.** `Lobby.request_seat_state` moved D31's rpc hash a
while back, so a server on this commit refuses any older client with "the server is running
different code". `.\Tools\build_client.ps1`, then `Docs/building.md`.

## 2. Install the clean shutdown, once

**What it is for.** D45: a deploy tells the players instead of freezing them. Without this a
restart still freezes a running match, silently.

```powershell
.\Tools\deploy_server.ps1 -InstallShutdown
```

- **Success:** it writes the drop-in, restarts, and asserts the effect by reading the settings
  back. From then on every restart honours D45.
- Run it **after** step 1, never before: the drop-in adds `--shutdown-file`, and the code that
  answers it has to be on the box first.

**It needs three more lines than it currently writes**, and they are the one piece of P5 that
is still code rather than a command: `OOMPolicy=continue`, `RuntimeDirectoryMode=0700` and the
journald rate-limit pair. Ask for them before step 3 and re-run `-InstallShutdown`.

## 3. Measure, BEFORE the release

**What it is for.** The cap and the READY ceiling must come from a load test rather than a
guess (§0 of the plan). On this dev PC a child boots in 1.5-1.8 s; a rented box is slower and
the ceiling has to allow for it.

Start a SECOND server, with the handoff on, on a port nobody is using, as a transient unit so
nothing permanent changes:

```
sudo ufw allow 7900/udp
sudo ufw allow 7800:7899/udp
systemd-run --unit=ltw-mmtest --uid=ltw --gid=ltw \
  -p OOMPolicy=continue -p RuntimeDirectory=ltw-mmtest -p RuntimeDirectoryMode=0700 \
  /opt/godot/godot --headless --path /srv/ltw/LTW_Test --log-file /tmp/ltw-mmtest.log \
  -- --server --match-processes --port 7900 --shutdown-file /run/ltw-mmtest/shutdown
```

Then, with two clients aimed at it (`-- --port 7900`), play one match and read the journal:

```
journalctl -u ltw-mmtest -o cat | grep -E 'Match process spawned|is ready|Handing|Match result'
```

- **Success:** a spawn line, a ready line with `seconds`, a handing-over line, and at the end a
  `Match result` line. **Send the `seconds` value back** - that is what the READY ceiling is
  set from.
- Memory per match, for the cap: with the test server up and no match running, note
  `MemAvailable`; start N matches and note it again. `grep MemAvailable /proc/meminfo`.

Stop it afterwards:

```
systemctl stop ltw-mmtest
sudo ufw delete allow 7900/udp
```

**Leave `7800:7899/udp` open** if gate 1 passed - the release needs it.

## 4. The release

Only after steps 1 to 3. It is one commit: the switch on, the protocol bump, and the values
measured in step 3. Ask for it; it is not written yet, deliberately, because a protocol bump on
`main` would refuse every tester at the next deploy by anybody.

Then `.\Tools\deploy_server.ps1`, and hand out the bumped client build **the same day** (D30).
The deploy stops through ExecStop, so anyone playing is told rather than frozen.

## 5. The proofs that need the real unit

After the release, with nobody playing:

- a deploy with two matches running tells the players of both;
- killing one child leaves the other running:
  `systemctl status ltw-server` then `kill -9 <a child pid>`;
- a real out-of-memory kill of one match process, once under `OOMPolicy=stop` (the unit stops -
  that is the positive control) and once under `continue` (only that match dies). The journal
  shows the OOM line both times;
- `cat /proc/<child pid>/oom_score_adj` reads back as raised;
- a child killed at the READY ceiling is logged as killed, and the journal has no "not a child"
  error.

---

## P6, stage (b): one systemd unit per match

**Not started, and it should not be until stage (a) has run for a while.** What it buys is that
a LOBBY CRASH leaves running matches alone; what it costs is root-level setup on the box. §4 of
the plan has the three mechanisms and the traps in each; the choice between them wants stage
(a)'s measurements, which do not exist yet.

The one thing worth deciding early: whether a lobby crash taking every match with it is
acceptable for now. Today it is, because a lobby crash is not something that has been seen.
