# The relay kept sending to players who had left

**2026-09-06.** Found in the public server's journal, reproduced and fixed the same day.
Numbers below are one dev PC, local server, two headless peers.

## What was wrong

A real match's log carried this, over and over:

```
ERROR: Attempt to call RPC with unknown peer ID: 62048081.
   at: _send_rpc (modules/multiplayer/scene_rpc_interface.cpp:318)
   GDScript backtrace (most recent call first):
       [0] _flush_batches (res://Scripts/Multiplayer/LockstepService.gd:1017)
       [1] _process (res://Scripts/Multiplayer/LockstepService.gd:221)
```

`_flush_batches` sent each match peer its batched turn words with no check that the peer was
still on the end of a socket. The outboxes are filled by `_queue` from `_match_peers()`, which
is the match **roster** — and a roster is never pruned, deliberately: slots and lanes are keyed
to it, and who has left is the turn stream's answer rather than the transport's. So a player
who left stayed a send target for the rest of the match.

It runs on the render frame, and the server is capped at 120 fps, so it fired on every flush
that carried a word.

## Why it was worth fixing before a tester build

Gameplay was unaffected — the loop carries on and the remaining peers still get their batches.
What it cost was the log and the time to write it: a Godot `ERROR` plus a full GDScript
backtrace, tens of times a second, for the remainder of any match somebody leaves. That is the
single most likely event in a first playtest, and the flood would bury any real error next to
it.

## The measurement

Paired, same commit, one variable flipped in place: a local server from the working tree, two
headless peers (`--probe host` / `--probe join`), a match started and played, then the join
peer **hard-killed** so ENet has to time it out rather than being told.

| | turns run by the survivor | stalls | `unknown peer ID` errors |
| --- | --- | --- | --- |
| Before | 977 | 269 | **1356** |
| After | 1245 | 2 | **0** |

Both runs dropped exactly two players from the match and reported no desync, so the drop path
itself is unchanged. The turn and stall columns are **not** a clean comparison — a different
slot was killed in each run — and are here only to show the survivor kept playing.

## The fix

The guard goes at the **send site**, `_flush_batches`, and only there:

- it is the last moment before the send, so it also covers a peer that drops between being
  queued for and being flushed to;
- `_queue` runs several times per turn against this once per frame, so the same guard there
  would allocate a peer list far more often than it would save an array append.

Nothing is logged when a peer is skipped. The departure is already reported once by
`MatchStartService`, and a line here would be the flood being removed.

**Asking `multiplayer.get_peers()` here is not the mistake `CLAUDE.md` warns about.** That
warning is against using the transport's list to answer *who is in this match*, which decides
simulation and has to be identical on every machine. This asks *is there a socket to address* —
the transport's own business, asked only by the relay, deciding nothing about the world.
`_speak_for_the_departed` already reads it the same way for the same reason.

## Left alone

Every other `rpc_id` across the autoloads was swept. They either target `SERVER_PEER_ID`
(client to server), or walk `_expected` / a lobby's own list, both of which **are** pruned when
somebody goes. `_flush_batches` was the only one sending to the unpruned roster.

One thing seen and not chased: the same peer is reported as having gone silent several times
rather than once, in both halves of the measurement. Pre-existing, harmless, and nothing to do
with this.

## Rebuilding the test

The probe is `Scripts/Dev/LockstepProbe.gd`, which needs registering as an autoload to run at
all. Start a local server, then `--probe host` and `--probe join` with `--address 127.0.0.1`,
wait for `Initial world agrees`, kill the join process, and count `unknown peer ID` in the
server's output. Remove the autoload line afterwards.
