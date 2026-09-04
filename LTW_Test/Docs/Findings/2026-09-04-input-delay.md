# Input delay: 300-400 ms was configuration, not lockstep

**2026-09-04.** Windows dev PC and the rented Hetzner server, `b12e638`.

## What was asked

The lockstep cutover shipped and an order took 300-400 ms to take effect. The assistant's
explanation was that 200-400 ms is inherent to deterministic lockstep and that RTS games hide
it behind acknowledgement sounds. The user, with thousands of hours of Warcraft III at 20-40
ms ping, said flatly that this was wrong and asked for research.

**The user was right.** Both claims were false, the second was invented, and roughly 250 of
the 300 ms was configuration plus a bug. This is written up because the wrong claim was
defended twice before it was checked, and because the reason it survived is still worth
knowing.

## How it was measured

- `LockstepService._report_latency` was added: a wall-clock stopwatch from `schedule()` to the
  turn actually running. It is diagnostic only - the simulation may never read it, because two
  machines do not share a clock.
- `Scripts/Dev/LockstepProbe.gd` drives two headless peers through a real match and issues an
  order a second. Runs both against a local server (loopback) and against the rented server.
- Every number below is the SIMULATED span - click to the world acting. What a player FEELS is
  higher by the input flush, physics interpolation and the present, roughly 50 ms more.

## What was found

### The delay did not depend on the network at all

Old configuration: `ticks_per_turn = 2` (a 100 ms turn), `input_delay_turns = 2`.

| Term | ms | Depends on ping |
| --- | --- | --- |
| `input_delay_turns` x `ticks_per_turn` | 200, fixed | no |
| turn-boundary quantisation | 0-100 | no |
| off-by-one in the tick counter (below) | 50 | no |
| the wire, at 26 ms ping | ~26 | yes, but spent INSIDE the 200 above |

The decisive check needs no research: set the ping to zero and the arithmetic is unchanged.
**A delay that does not move when the network is removed was never a network delay.**

### An off-by-one worth exactly one tick

`_frames` was incremented at the TOP of `_physics_process`, so a turn only passed the
`turn > clock_turn` gate on the tick after the one it belonged to. Every order in the game ran
50 ms later than its own schedule said. Found by measuring 126-134 ms on loopback where the
arithmetic predicted 50-100.

### What the primary sources say

Seven agents on primary sources; the load-bearing ones:

- **Age of Empires** (Bettner and Terrano): the communications turn *"was roughly the
  round-trip ping time for a message"*, adapted continuously by their Speed Control system.
  Turn length tracks the network, frames-per-turn track the slowest CPU.
- **Warcraft III** patch 1.28.4: *"The artificial latency on all Battle.net realms has been
  reduced from 250ms to 100ms."* LAN was 100 ms throughout. WC3 does not schedule turns ahead
  - it flushes whatever arrived on a timer, so command latency is `RTT + uniform(0, 100 ms)`.
- **StarCraft**: same engine, 125 ms on LAN and 500 ms on Battle.net, by configuration alone.
  Remastered shipped Dynamic Turn Rate to choose.
- **Spring/Recoil** has no command-delay constant in the engine at all. **Warzone 2100**
  negotiates to a 100 ms floor. **OpenRA** measured 72 ms click-to-response by one contributor
  after changing one constant. **0 A.D.** sits at 800 ms with a source TODO apologising for it.
- **The acknowledgement-sound claim has no primary source.** The AoE paper was searched
  directly; the only mention of sound in it is a determinism warning about terrain audio.

Counterweight, recorded rather than buried: AoE's own 1997 playtesting found *"250
milliseconds of command latency was not even noticed"*, and Sheldon et al. (NetGames 2003)
found no significant effect on WC3 match outcomes up to 500 ms. Both measure outcomes and
tolerance, not perceived responsiveness, and neither argues the delay is unavoidable.

## What was changed

- `ticks_per_turn` 2 -> 1. A turn is a tick.
- The delay is measured from ENet's own smoothed round trip and variance, which cost no extra
  packets - the match's own traffic is the measurement. The server announces the worst one-way
  it can see; each peer sizes its own delay from that.
- Turns are closed as a RANGE rather than one per tick. This is what makes a moving delay safe
  and it subsumes the old priming special case.
- The off-by-one.
- A peer records its own word for a turn locally instead of waiting for the relay's echo.
  **This one is a correctness fix** - see Traps.
- Command-card and send-bar buttons fire on PRESS. Godot's `Button.pressed` defaults to
  `ACTION_MODE_BUTTON_RELEASE`, so every build and every send was paying the whole click-hold,
  60-120 ms, before the order reached the scheduler. Hotkeys never had it.
- `checksum_every_turns` pinned to 10, because halving the turn length had silently doubled the
  checksum rate on a tick budget that is already tight.

### Before and after

| | before | after |
| --- | --- | --- |
| loopback, 3 processes on one PC | 126-134 (and 250-350 pre-cutover) | min 69, median 69-76 |
| rented server, 26 ms ping | not measured pre-cutover | min 131, median 131 |
| delay chosen | fixed 2 turns | 1 turn on loopback, 2 at 26 ms - it tracks the link |
| desyncs | 0 | 0, over 455-463 turns and 46 orders per run |

## Tried and reverted

**Asymmetric slew on the delay.** Both the AoE paper (*"a consistent 500 msec command latency
was playable, but one that varied was considered jerky and hard to use"*) and Warzone 2100's
`gtime.cpp` argue for damping. Built it - rise at once, fall only after a calm period.
**Measured four times worse: 370 ms mean against 79**, with the delay ratcheting to the ceiling
and staying there. A rise taken immediately plus a fall that must be earned turns one spike
into a permanent tax, and the spikes it was reacting to are an artefact of three headless Godot
processes sharing one desktop's cores. Damping the wrong signal made the wrong signal
permanent. Reverted; the reasoning sits where the smoothing would go.

**A tighter jitter margin**, 20 ms down to 8. Stalls went from 1 per run to 7-8 with no gain in
the median. The margin is earning its keep.

## What is still open

- **A lockstep client's tick budget under load.** Every client now simulates every lane and
  nobody has watched a client's frame time in a loaded match. Biggest open risk in the model.
- **Delay smoothing**, judged against a real connection rather than loopback. If the reading is
  genuinely spiky the fix belongs in the measurement - a decaying peak, or dropping the
  variance term - not in a ratchet on the answer.
- **The remaining gap to WC3.** Felt latency is roughly 180 ms against WC3's ~110 at the same
  ping. What is left is the 20 Hz tick itself and the fact that this schedules turns ahead
  while WC3 flushes on a timer and lets a late order ride the next packet.
- `_report_latency` measures `schedule()` to turn-run, so it under-reports what a player feels
  by roughly 50 ms. Do not use it as the acceptance criterion without adding that back.

## Traps

**A client's own orders reached it only through the server's echo.** `_expected_peers()` never
named the local peer and `_emit` did not record locally, so if the echo ever arrived after the
turn ran, that client alone applied a turn short of its own orders - no stall, no error, caught
only at the next checksum. It was covered purely by accident: the announced worst one-way is
taken across every peer including the receiving one, so the budget always happened to exceed a
peer's own round trip. Anyone tightening that loop would have broken it silently. Fixed by
recording locally, which also removes half a client's own latency.

**`Tools/deploy_server.ps1` reported success while skipping the restart.** Windows PowerShell
5.1 wraps every stderr line from a native executable in an ErrorRecord, and with
`$ErrorActionPreference = "Stop"` that record is terminating - so one ordinary line of git
progress aborted the deploy after `git reset` and before `systemctl restart`. The tree was on
the new commit, the script said so, and the server went on running an hour-old build until a
client was refused for being on "different code". The script now drops the preference around
ssh and PROVES the restart by comparing the service pid before and after. General lesson, so it
is in `../../CLAUDE.md`: **a deploy that checks the files is not checking the process.**
