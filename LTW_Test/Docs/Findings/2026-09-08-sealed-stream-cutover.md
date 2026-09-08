# The sealed turn stream: what the cutover actually bought

**2026-09-08.** Phase 4 of `netcode-rework.md`, built and measured behind
`NetworkConfig.sealed_stream`, which still defaults to **off**.

## The claim being tested

Under the old gate a peer may not simulate turn N until it holds a word from EVERY other peer, so
one machine hitching freezes everybody — the thing playtest 1 measured. Under the sealed stream the
relay seals one authoritative turn per tick from whatever has arrived and a peer waits only for the
relay, so a machine that hitches should pay for its own hitch and nobody else should pay anything.

**That asymmetry IS the design**, so it is the thing that had to be measured.

## The measurement

Paired and alternating against the flag, same commit, one relay and two rendered clients. The
`join` peer blocks its own main thread for 900 ms every 5 seconds — `OS.delay_msec`, not a skipped
frame, so the engine really does miss its ticks the way a slow content load does. The number that
matters is the OTHER peer's.

| run | flag | healthy peer held | hitching peer held | healthy peer turns |
| --- | --- | --- | --- | --- |
| off2 | off | **5.10 s** | 3.45 s | 462 |
| off3 | off | **5.40 s** | 3.50 s | 457 |
| on1 | on | **0.85 s** | 1.20 s | 548 |
| on2 | on | **0.75 s** | 1.10 s | 549 |

Six hitches of 900 ms is 5.4 s of freeze on one machine, and under the old gate the *other* player
paid essentially all of it. Under the sealed stream they pay 0.75-0.85 s — **all of which is a
single stall on turn 0** while the relay waits for both worlds to be built. Nothing after match
start.

The wedged-peer run is the same statement without the arithmetic: a peer whose game loop stops dead
at 10 s cost the healthy peer **nothing at all**, while itself accumulating 360 unplayed seals.
That case used to be an eight-second freeze for everybody, ended only by the silent timeout.

## What was checked besides the headline

A green run and a run that never exercised the thing look identical, so each of these carries its
own positive control.

| scenario | result | what proves it ran |
| --- | --- | --- |
| clean 1v1 | both peers identical, 548 turns | `sealed: true`, 56 orders applied per side |
| planted desync | caught on **both** peers | `desyncs: 1`, deliberately corrupted one world |
| third peer connects mid-match | match unaffected | browser got a lobby list **and zero seals** |
| relay-side player drop | survivor erased the leaver | `drops_seen: 1` |
| hopelessly behind | left cleanly at the ceiling | `held 101 > cap 100`, server saw the leave |
| clock drift, 5 minutes | none | lead stayed 0 for 5900 turns |

## The bug the measurements could not see

**`inject()` stamped `slot = 0` onto the order dictionary, which silently disabled every player
drop.** The relay's sort key and the order's payload slot are different numbers that happen to be
written next to each other: the tuple's leading `0` sorts a server order before every player's,
while the dictionary's `slot` says who the order is ABOUT. For `PLAYER_LEFT` — the relay's only
injected order — that is the slot of the player who LEFT, and `_apply_player_left` returns on its
first line if it reads 0.

So the leaver's maze would have stood, on every peer, for the rest of the match, with nothing
logged on any of them. During the technology draft it would have hung the match outright, which is
the exact failure `_announce_drop` exists to prevent.

**Every run above passed while this was live**, including the one that dropped a peer. The reason
is worth keeping: the survivor's match carries on identically whether or not it processed the drop,
so nothing observable distinguished them. The probe now connects `MatchStart.player_dropped` and
reports `drops_seen`, which is the control that would have caught it — and it read 0 before the fix
and 1 after.

Two smaller ones from the same pass, both real:

- **the checksum window was half the legal backlog.** A peer may trail by `max_sealed_turns` (400)
  before giving up, but checksums were kept for `max_peer_lag_turns` (200) — so a peer between the
  two had every report refused and was never compared against anybody again. A divergence detector
  that switches itself off on exactly the machine most likely to be diverging.
- **`tree.paused` is never released when a match scene goes away.** Reaching the give-up ceiling
  means this peer is stalling, and a stall holds the whole tree, so leaving while held returned to
  a frozen main menu. Nothing had reached it before because every previous exit happened to release
  first, which is not a property worth resting the whole application on. `MatchSession._exit_tree`
  now clears its own holds.

## Traps paid for

**A LEFTOVER `--server` IS A STALE BUILD, and its refusal reads exactly like a code bug.** The
first run failed with the client refused for being on "different code", against a server that had
been running since before the change existed. The harness now kills any stray server and **asserts
the new one actually listened** before launching a client — assert the effect, not the command.

**THE CONTENT WARMER CRASHES A HEADLESS CLIENT.** It loads eight resources at a time on worker
threads, and under `--headless` those threads reach Godot's dummy rendering driver, which does not
survive it: "Initializing already initialized RID", "Parameter mem is null", then a segfault. One
of two identical clients died and the other finished, which is what a race looks like. Real clients
have a real renderer and are unaffected — which is why this was invisible until the netcode test
loop, which is headless by design, started running the load screen. It now loads on the main thread
when `DisplayServer.get_name()` is `headless`: same resources warmed, no workers, no crash.

**A DROP THAT ARRIVES AFTER THE LAST TURN IS NOT A DROP THAT FAILED.** The first `drops_seen` run
read 0 and looked like the fix had not worked. The relay had injected the order into turn 552 and
the peer's run ended at turn 550. Separately, the wedged peer kept sending orders from its render
frame, so it never looked silent and was never given up on — a fair description of that machine,
and a useless simulation of one that has died.

## What this does NOT establish

**Both peers shared one machine's clock.** Drift comes from two different crystals, so the
five-minute zero-drift result rules out Godot's own tick scheduling as a source and says nothing
whatever about two real PCs. That is the same shape as `CLAUDE.md`'s own rule about a test topology
that cannot falsify its assumption, and it is why the phase 5 decision below is provisional.

Also untested: any match longer than five minutes, more than two players, a real internet link with
real packet loss, and cross-machine determinism — which the cutover makes harder to test, because
peers are now legitimately seconds apart rather than turn-locked.

## Phase 5, decided against a threshold stated first

The threshold was written down **before the run**, so the measurement could refute it rather than
be interpreted afterwards:

> A servo is needed if a healthy peer's lead drifts by more than one turn (50 ms) per match minute
> in steady state.

Measured over 5900 turns: the lead held at **0** for the entire run, and the peers' clocks ran at
20.0 turns per second against the relay's 20. Not "under the threshold" — not measurable.

**So no servo, provisionally**, and the plan's instruction is to stop there indefinitely. The
decision is reopened by the two-PC run and by nothing else.
