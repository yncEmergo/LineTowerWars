# Findings

Investigations. Something that was measured, chased down or ruled out, written up so the next
person does not pay for it twice.

A finding is **not** a reference document. `game_rules.md` says how the game works and is kept
true; a finding says what was true on one day, on one machine, and is never updated afterwards.
That is the whole distinction, and it is what lets these files carry numbers when nothing else
in `Docs/` may.

## Index

| File | What it covers |
| --- | --- |
| [2026-08-29-performance.md](2026-08-29-performance.md) | First load test of the simulation and the renderer. Where a tick goes, what drawing costs, what was fixed and what is still open. |
| [2026-09-03-server-tick-overrun.md](2026-09-03-server-tick-overrun.md) | Stutter on mass creep spawns in the first remote match: the server misses its tick. Where a creep tick actually goes, what was wrong about the first three guesses, and the three fixes that came out of it. |
| [2026-09-04-log-info-in-the-creep-tick.md](2026-09-04-log-info-in-the-creep-tick.md) | Where the unattributed half of a creep's tick went: one `Log.info` on the leak path — and why that dev-PC number does not transfer to the server. Also profiles the tower tick (clean) and the spawn path (pathfinding, not instantiation). |
| [2026-09-04-staggered-creep-movement.md](2026-09-04-staggered-creep-movement.md) | Moving each creep every Nth tick: built, measured at ~16% off the worst tick, and reverted because it looked terrible — and why that was the replication seam rather than the rate. Also the run-to-run variance of the rented box, and two hypotheses ruled out. |
| [2026-09-04-input-delay.md](2026-09-04-input-delay.md) | Why an order took 300-400 ms after the lockstep cutover, and why almost none of it was the network. What the primary sources actually say about lockstep latency, the off-by-one worth a whole tick, and a damping scheme that measured four times worse and was reverted. |
| [2026-09-05-lockstep-review.md](2026-09-05-lockstep-review.md) | A read of the whole multiplayer system against the primary sources on lockstep. What the cutover did not actually do to the server's CPU, four bugs reachable by inspection - a disconnect that desyncs, two owners of the pause, an invisible stall, transcendental maths on the simulation path - and what the field does that this does not. |
| [2026-09-05-lockstep-hardening.md](2026-09-05-lockstep-hardening.md) | Acting on that review after verifying it - two of its findings were wrong. Four silent desyncs closed, the server actually made a relay, turn redundancy proven by disabling the reliable path, and the client tick budget measured at last: a 1v1 has 2.3x headroom, twelve players is 2x over. Also why a single latency median on this link is worth nothing. |
| [2026-09-05-lockstep-review-2.md](2026-09-05-lockstep-review-2.md) | A second, independent read after the hardening pass. The model is right; the edges are not. A third connection to the server freezes the running match for ever, the turn stream is broadcast to peers who are not in it, a disconnect is not turn-synchronised, and a client's turn numbers are unvalidated. Plus where the input delay actually goes on a good link, and why relay batching was under-ranked. |
| [2026-09-05-lockstep-review-2-response.md](2026-09-05-lockstep-review-2-response.md) | Closing that review. A third connection froze any running match permanently; the turn-synchronised drop the review suggested DEADLOCKS and why; the jitter margin measured against time-actually-held rather than a stall count, halving input latency. |

## Writing one

Name it `YYYY-MM-DD-subject.md` and add a row above. The date is part of the filename because
it is part of the claim.

Cover these, in whatever order suits the work:

- **What was asked**, in one line.
- **How it was measured**, naming the tool, so the numbers can be reproduced rather than
  trusted. A finding whose numbers cannot be regenerated is an opinion.
- **What was found**, with the numbers, and clearly separating what was MEASURED from what was
  DERIVED or INFERRED. Say which machine.
- **What was changed**, with before and after.
- **What is still open**, as concrete next steps rather than aspirations.
- **Traps**, if the work turned any up — but if a trap is general rather than about this one
  investigation, it belongs in `../../CLAUDE.md` instead, and the finding should say so and
  link it.

## What not to do with one

**Do not update it.** If the numbers change, that is a new finding with a new date. An edited
finding is worse than a stale one, because the date at the top stops being true and nothing
says so.

**Do not cite its numbers anywhere else.** A finding's numbers are safe here precisely because
the date is attached. Copied into `README.md` or a docstring they become an undated claim about
now, which is exactly what the no-live-values rule exists to prevent. Link to the finding
instead.

**Do not let it replace a code comment.** If the work produced a rule the code has to keep
following, that rule goes in a docstring next to the code, and the finding explains why. The
code is what someone reads while changing it.
