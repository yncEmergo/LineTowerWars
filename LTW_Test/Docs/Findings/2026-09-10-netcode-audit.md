# A full adversarial audit of the netcode

**2026-09-10.** The whole networking layer, audited adversarially the day after the sealed stream
went live on real hardware - and a day on which roughly a third of `LockstepService` was deleted
and its catch-up servo was rewritten four times.

Eight independent lenses hunted for bugs. Every finding then had to survive two separate attempts to
refute it - one asking whether the code really does that, one asking whether the state is reachable
- before it counted. A completeness critic then named what the hunt had missed. The chase agents for
those gaps and the final ranking step died at the account's spend cap, so ranking and round two were
done by hand; nothing else was lost.

31 distinct findings were reported. 17 survived refutation, collapsing to **eight distinct bugs** -
one of them found independently by six of the eight lenses. Round two added six more: one caught by
the harness while verifying round one, two named by the critic, and three the verifiers had refuted
as not-bugs but which were worth fixing anyway. **All fourteen are fixed, and every fix that a run
could prove was proven by one.**

## The critical one: a lobby browser could end any match with one packet

`report_turn_checksum` accepted a checksum from any connected peer. Every other `any_peer` ingress on
the relay already refused a sender with no slot; this one did not. So anybody who had merely pressed
Multiplayer - connected, in no match - could report a checksum for turn 0, which is always compared,
and `_compare_turn` would announce a desync to both players. **A desync is unrecoverable by design,
so this was a one-packet way to destroy any match on the server.** `MatchStartService.report_checksum`
had the same hole behind a match id, which is `match-1` and not a secret.

Both now refuse non-members, and `report_turn_checksum` also refuses a turn the relay has not sealed:
an honest peer can only report a turn it ran, and one absurd turn number would otherwise make
`_forget_old_turns` wipe the stored window.

**Proven against a hostile client rather than argued.** The probe gained a `spoof` role that
connects, joins nothing, and forges a checksum every frame across the whole turn range:

| | guard in place | guard removed |
| --- | --- | --- |
| forged checksums sent | 5,509 | 5,509 |
| players' desyncs | **0** | **1 each - match destroyed** |

The second column is what makes the first one mean anything: a forger that never reached a compared
turn would also have produced zero.

## Found by six lenses: the engine was left overclocked after every match

The catch-up servo writes `Engine.physics_ticks_per_second`, a GLOBAL property, and `_restore_rate`
ran only when the NEXT networked match started. A player who left mid-catch-up - which is exactly
when a player who has just watched their game freeze presses Leave - took the raised rate into the
menu and into any offline match after it, which then ran at up to three times speed.

Now restored in `_physics_process`'s not-live branch, keyed on `_paced_at` so an engine the servo
never touched is never written to. That matters twice over: the determinism bench sets its own rate
with `rate=`, and clobbering it would have blinded the two-rate falsifier. Re-run afterwards, 20 Hz
and 30 Hz are still byte-identical.

## The servo, which had already shipped one bug

- **Its slow-down branch was arithmetically unreachable.** `slack` was
  `maxi(_relay_slack_ms(), buffered + target)` with `buffered` never negative, so `slack` could never
  fall below the target it was compared against. The fix for overshooting was present in the
  comments - which quoted the measured run it prevented - and absent from the arithmetic. The floor
  now applies only when there is a buffered surplus. **Positive control: the next run logged a
  slow-down entry, which had been impossible.**
- **The buffered debt converted at the live engine rate**, so it shrank as the servo sped up: at
  60 Hz a turn read as 16 ms instead of 50, and it eased off on a debt three times larger than the
  number it steered on. Now the authored rate.
- **Its cache was keyed on `_frames`, which stops during a stall** (the critic's), so a stall froze
  the control signal for exactly the interval it was steering through. Now the engine's frame count.

Two 900 ms hitches, same harness:

| | stalls | catch-up entries | slack at the end |
| --- | --- | --- | --- |
| round 1 | 3 | 9 up, **1 down** | -82 ms |
| round 2 | 3 | 8 up, **1 down** | -79 ms |

Slack returns to its pre-hitch baseline rather than parking at the configured lead, which is what the
version shipped the day before did.

## A player who had given up could still play

A peer that falls too far behind gives up, freezes, and shows "the match carried on without you".
But `StallInput` releases the order UI whenever lockstep is the sole holder of the pause - which a
given-up peer is - so that player could keep sending creeps and spending gold in a match they had
been told they were out of. `schedule()` now refuses while given up, and `StallInput` keeps the card
muted.

**Proven by what stopped happening, which is worth keeping as a method.** The probe's
`--drive-while-wedged` pressed 31 times after giving up. A wedged peer's heartbeat is off, so the
relay only hears it through its orders - and the relay then dropped it as silent, which it can only
do if those 31 orders never arrived. No sabotage run was needed.

## The rest

- **`receive_desync` was a bare `rpc()`**, reaching everyone connected, including lobby browsers who
  would record a desync for a match they are not in. Now the roster, and only live sockets.
- **`wire_config` left out `lockstep_enabled`**, which switches the whole protocol between the sealed
  stream and full-world replication. Two builds disagreeing about it would connect and then fail
  however the mismatch happened to. Now part of the handshake.
- **`stalled_seconds()` multiplied a frame count by the live rate**, so a stall taken at 20 Hz read as
  a third of its length during a 60 Hz burst - and it is the number `CLAUDE.md` says tuning must use.
  Now accumulated in seconds, frame by frame.
- **The seal echo kept counting after give-up** - found by the harness, not the audit. `_absorb_seal`
  refuses everything then, so every echoed turn looked like a repaired loss, and a given-up peer
  reported `echo: [1204, 0]`: over a thousand repairs with nothing dropped. `echo` is the one field
  that reports real packet loss, so it cannot be allowed to lie. Now `[0, 0]`.
- **`MatchSession.hold` called `Log.info` twice per stall** (the critic's). Under the sealed stream a
  stall is frequent, `Log.info` is ~10 ms on Windows, and the resume call lands on the very frame the
  world starts moving again. Debug for the lockstep holder; the draft stays at info.
- **`Net.flush()` had lost both its callers** with the old path, so every seal and order waited for the
  end of its frame. Restored on the seal broadcast and in `schedule()`. *This restores the behaviour
  from before the deletion; the latency it saves has not been re-measured.*
- **The relay re-picked the same dead peer every timeout** and logged "gone silent" about it for the
  rest of the match, because `_departed` had become write-only. The drop itself was always
  idempotent, so this was noise rather than a correctness bug. Three warnings a run became one.
- **Dead code from the deletion**: `TURN_SLACK`, `MEASURE_EVERY_FRAMES`, `_stamped`,
  `_jitter_margin_ms`; doc comments that the variable deletion had left attached to the WRONG
  declarations, or floating with no declaration under them at all; and runs of up to sixteen blank
  lines where functions used to be.

## What held

Reported, then refuted by both of its verifiers: that `submit_order` seals unvalidated payloads; that
losing the relay mid-match strands a client in a zombie world; and that `_seal_clock_may_start`'s
timeout re-opens the hole B2 closed. Three more were refuted as not-bugs and acted on anyway, because
being right about severity is not the same as being right to leave something: the lost flush, the
dead code and the `_departed` log spam.

## What this audit could not check

- **Every `@rpc` rides ENet channel 0**, so the seal - the one thing every peer's clock waits on -
  shares a reliable ordered channel with lobby-list broadcasts, and a large enough broadcast could
  head-of-line block it. Plausible and unmeasured; moving the seal to its own channel is a protocol
  change.
- **`WorldChecksum` hashes `stats.resource_path`.** Exported build against exported build is proven
  clean, twice. The editor against an exported build is not, and if the two report different paths
  that is a false desync in any mixed test. Cheap to settle: one exported client and one run from
  source in the same match.
- **The determinism bench drives the offline path**, so it cannot see the seal's ordering at all. The
  two-peer harness covers that, on one machine and loopback.
- **The echo was proven against a seal lost after delivery**, not against the reliable channel's
  head-of-line blocking it exists to beat, which the injector cannot produce. Real loss on a real
  link remains unmeasured; the health line now reports it honestly.
- **Five config knobs configure nothing**: `adaptive_delay`, `fixed_delay_turns`, `min_delay_turns`,
  `max_delay_turns` and `jitter_margin_ms` belonged to the deleted delay chain, and `SessionLog` still
  reads and logs them. Left deliberately: removing an export that `SessionLog` reads is precisely the
  runtime-error trap that cost the health line a day, and it wants its own pass.
- Everything ran on one machine, with two players, a minute at a time.

## Traps

**A FIX PRESENT IN THE COMMENTS AND ABSENT FROM THE ARITHMETIC.** The servo's slow-down branch carried
a paragraph explaining the exact failure it prevented, with the measured run quoted - and could never
execute. A comment describing a guard is not evidence the guard runs. The positive control is a log
line from inside the branch.

**A GLOBAL ENGINE PROPERTY OUTLIVES THE MATCH THAT SET IT.** Anything that writes
`Engine.physics_ticks_per_second` or `tree.paused` owns putting it back on EVERY road out, and "when
the next match starts" is not a road - the player may never start one.

**A GUESSABLE ID IS NOT MEMBERSHIP.** `report_checksum` checked a match id, and match ids are
sequential.

**A COUNTER THAT KEEPS COUNTING AFTER ITS SUBJECT HAS STOPPED LIES LOUDEST.** The echo counter was the
one field meant to report real loss, and a peer that had stopped playing made it report a thousand
phantom repairs.

**A CACHE KEYED ON A CLOCK THAT STOPS FREEZES EXACTLY WHEN IT IS NEEDED.** `_frames` stops during a
stall, and the servo's signal went stale for precisely the interval it was steering through.

**DELETING A VARIABLE LEAVES ITS DOCSTRING ON THE NEXT ONE.** Removing `var` lines left their `##`
blocks sitting above unrelated declarations, or above nothing. Delete the block with the line, or the
file starts describing things that no longer exist as if they were the variable below.

**GODOT PRINTS EVERY WARNING TWICE** - once through `Log`, once as the engine's own `WARNING:` echo - so
`grep -c` on a warning counts double. "2" nearly read as the `_departed` fix not working, when it was
one warning printed twice.

**PROOF BY WHAT STOPPED HAPPENING.** When the thing under test is a refusal, look for its downstream
consequence. The give-up fix needed no sabotage run, because the relay dropping a peer whose only link
was its orders is evidence the orders stopped.

## Not deployed

The server is still on `423b915`, before both this audit and the catch-up fix the day before, and a
client cannot be built right now: `build_client.ps1` refuses a dirty tree, another session's
uncommitted work is in it, and building with `-Force` would stamp this commit onto a pack containing
changes the commit does not. `wire_config` also changed, so an old client and a new server will refuse
each other - cleanly, by name. Deploy and rebuild together, once the tree is clean.
