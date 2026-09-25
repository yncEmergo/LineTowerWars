# Multi-match: the check pass, to fold into the plan

**TEMPORARY.** Fold every item below into `multi-match.md`, then delete this file, and remove its
mention from that file's handoff section. Do it before any P2 code.

**What this is.** `multi-match.md` was rewritten on 2026-09-25 around a review of its first
version. Three readers then checked the rewrite:
- **completeness:** did every verified finding make it in;
- **correctness:** does it agree with the code and with the other docs;
- **the implementer:** where would the next session have to guess.

Their report is below as they wrote it: each item with its location, the problem, and the exact
replacement text they propose. The ids A1..F22 and V1-1..V3-1 inside it name findings of the
review. Those raw findings stayed on the machine the review ran on; the plan carries what they
established.

**The three readers overlap heavily.** One problem is often reported two or three times, for
example:
- a pending token must hold its seat: completeness C1, correctness C4, implementer I4;
- "held" is used for two opposite things: correctness C7, implementer I3;
- no TOO_LATE after go while `refuse_new_connections` is set: correctness C3, implementer I5;
- D15's clock should start at the announce: completeness C6, correctness C11, implementer I14;
- a queued spawn must count toward the cap: completeness C8, correctness C10, implementer I15;
- the ordered exit: correctness C9, implementer I6;
- the switch, and clients keyed on the announce: completeness C9, correctness C2 and C14,
  implementer I12.

Where they differ, prefer the implementer's version: it is the most complete. Check each item
against the plan as it now stands, since some text has moved.

**Already applied before the push that carried this file:**
- P0's fix and proof: min_players on both paths, the disconnect rather than the drop, the
  four-player proof with a positive control, the probe flags (completeness C2, correctness C5,
  implementer I1 and I2);
- P0's "Left" and the release order in P5: `-InstallShutdown` right after the next deploy, then
  re-run before the switch is turned on; the box steps are the owner's; the measurement comes
  BEFORE the release (completeness C4, correctness C15, implementer I11 and I21);
- the P4 heading: the protocol bump is not committed in P4 (correctness C1, implementer I10);
- the Findings' corrections (completeness C11 to C14, correctness C8's Findings half, and the
  Still open line);
- D13's row: the re-claim exception before the go signal (correctness C13's first half).

Everything else below is still to do.

---


## Reader 1: completeness
VERDICT: Almost ready to implement from, but not yet. Going through every finding: most of the 97 are faithfully in, including A2/B6/C1/D2/F10, where the plan chose never-evict plus a re-claim inside D26's hold, gave its reason in §8, and records the owner's decision correctly in §0, step 6 and the D44 row. Nothing that changes the design was dropped silently. Four major problems block implementation. First, merging A3 into C1 lost C1(b): a pending claim does not hold its seat and a release does not check which peer is leaving, so the plan's own retry rule can put two peers on one seat. Second, the P0 live-bug fix leaves out C3's min_players check, and its proof as written expects a one-player start. Third, A1's 'find the seat through the table' was dropped: MatchStart's D15-abort, go-time and D45 notices all go through `_expected`, which a match process no longer fills before go, so they would reach nobody. Fourth, the P5 release window runs `-InstallShutdown` after the deploy that turns the switch on. Until then there is no run directory and no ExecStop, and the plan contradicts the Findings' 'Still open'. The minor gaps are:
- the wrong-token wording contradicts itself;
- D15's clock starts at the countdown's end rather than at the announce;
- run-file deletion discards the Windows child log and the RESULT;
- what a queued spawn does is unstated;
- two conditions the off switch depends on are unstated;
- the gates were moved with no reason given.

The Findings section states the verified facts accurately, with a few small overstatements: 'None was refuted', '4.7 sources' where most of the engine files were read from master, and a journald fact given without its caveat. It also leaves out the one measured `peer_disconnect_later` variant. After those edits the plan is fit to implement from.

### C1 [major]

**Where:** multi-match.md §2 Step 6, 'Checking' and 'Releasing' bullets: "for a valid token whose seat is unclaimed or held, records `pending[peer] = seat` and completes auth" and "A claim ends: on `peer_disconnected`; on `peer_authentication_failed`". Also the state list "a state: unclaimed, claimed, ready, held (inside D26's hold) or left"

**Problem:** C1(b) and D2 were dropped when A3 was merged in. The seat is re-keyed only on `peer_connected`, and nothing makes a PENDING claim hold the seat. So a second connection that presents the same token before the first is admitted still finds the seat 'unclaimed'. It also gets complete_auth, and two peers end up on one seat. The plan's own retry rule produces this without any attacker: a client whose dial timer fires after the server has accepted it redials with the same token (A2). The release is also unguarded. When the abandoned first connection later times out, its `peer_disconnected` or `peer_authentication_failed` releases the seat that the live second connection holds, and that seat drops into D26's hold while its player is connected.

**Fix:** State list: "a state: unclaimed, pending, claimed, ready, held (inside D26's hold) or left." Add two bullets after 'Claiming': "- **Pending counts as held.** From the moment `auth_callback` accepts a token until that peer is admitted or fails, the seat is `pending` for that peer. A second connection presenting the same token gets SEAT_HELD, exactly as for a claimed seat. - **A release names its peer.** `peer_disconnected`, `peer_authentication_failed` and a hang-up by the match process release a seat only when the departing peer is that seat's pending or current peer. The departure of a superseded or refused connection changes nothing." P2 proof, add: "two connections presenting one token within a round trip: one is admitted, the other reads SEAT_HELD, and the abandoned one timing out does not release the seat."

### C2 [major]

**Where:** multi-match.md §7 P0, 'Fix:' ("the go roster is always `_roster_of_ready()`") and 'Prove it with LockstepProbe, in a three-player load. Kill one player after it reports ready, and another before it does. The go roster must hold neither, and the start must wait for the third player.'

**Problem:** C3's 'checked against min_players on every path' did not reach the P0 fix, although step 6 carries it for the match process. In today's code only the timeout branch checks `_min_players`. The all-ready branch (`_ready_ids.size() >= _expected.size()`) does not. With the fix as written, that branch starts `_roster_of_ready()` even when a single player is left. The P0 proof is exactly that case: three players, two killed, one left, and min_players defaults to 2. So the proof either passes on a one-player online match or contradicts D15. The fix also leaves out A1's re-broadcast of readiness after the drop, so the loading rows keep showing the dropped player as ready.

**Fix:** Replace the Fix sub-bullets with: "- while the gate waits, a drop also clears that player's readiness, and readiness is broadcast again; - the gate is 'every expected peer is ready'; - the go roster is always `_roster_of_ready()`, and on this path too it is checked against `min_players`: below it the match is aborted with D15's sentence, as the timeout path already does." Replace the proof with: "Prove it with LockstepProbe in a four-player load. Kill one player after it reports ready, and another before it does, while a third is still loading. The go roster must hold neither, and the start must wait for the one still loading. Then the same two kills in a three-player load must end in 'Not enough players finished loading.'"

### C3 [major]

**Where:** multi-match.md §2 Step 6, after 'The gate:' (no text covers it), and §7 P2 'Prove' list

**Problem:** A1's line "has_player, drop_silent_peer, _slot_of and the shutdown notice find the seat through the table" was dropped silently. Before go, every recipient list in MatchStart comes from `_expected`: `_abort`'s D15 sentence, `_start_match`'s 'You did not finish loading in time.' loop, `_on_shutdown_started` (which also returns unless `_in_match`), `_on_peer_left` (which returns unless `_expected.has(peer)`), and `_broadcast_readiness`. The plan fills no `_expected` before go ('begin() is not reused'). Reused as it stands, that code tells nobody. A D15 abort and a D45 shutdown during loading then reach the players only as a lost connection, which breaks D45's 'tells the players', and the hold never starts. No P2 proof exercises either path.

**Fix:** Add to step 6 after 'The gate:': "**Everything MatchStart does to 'the players' before go finds them through the seat table**, never through `_expected` or the setup's ids, which a match process does not fill before go. That covers the D15 abort's sentence, the 'You did not finish loading in time.' notice at go, the D45 notice during loading (`_on_shutdown_started`, which today also returns unless `_in_match`), `_on_peer_left`'s hold, readiness broadcasts, `has_player` and `_slot_of`. Each goes to the seats claimed at that moment." Add to P2 Prove: "a D15 abort, and a shutdown file created during loading, each reach every claimed seat with its own sentence, read from the probe's screen line; a match process with no seat claimed exits at the load timeout and writes a RESULT."

### C4 [major]

**Where:** multi-match.md §7 P5 'The release happens in one window: 1. push; 2. the deploy that turns the switch on, together with the bump; 3. `-InstallShutdown`; 4. hand out...', and P0 'Left: running `-InstallShutdown` once, at the release'

**Problem:** The order is wrong, and it contradicts the Findings. `RuntimeDirectory=ltw-server` and the D45 `ExecStop` exist only in the `-InstallShutdown` drop-in. Between steps 2 and 3, the lobby therefore runs with the switch on and without /run/ltw-server, which §4 names as its run directory, so it has nowhere to write a match file. Step 3's install then does `systemctl stop` under the OLD unit, which has no ExecStop, and freezes any match started in between without a word. That breaks D45 at the release, and it undercuts P5's proof 'a deploy with two matches running tells the players of both'. P0 also moved `-InstallShutdown` to the release without saying why, which leaves D45 unhonoured on the box until P5. The Findings' 'Still open' still says "It runs once, right after the deploy that brings the code for it" and "B's first stage adds `OOMPolicy=continue` to the same drop-in" (now three lines).

**Fix:** P0 Left: "- running `-InstallShutdown` once the P0 code is on the box, so every deploy from then on honours D45;". P5: "`-InstallShutdown` is re-run to apply them BEFORE the switch is turned on, and asserts...". Release window: "1. push; 2. `-InstallShutdown` with the new lines (it stops, writes the drop-in, starts, and asserts the effect); 3. the deploy that turns the switch on together with the bump, which now stops through ExecStop and so tells anyone playing; 4. hand out the bumped client build the same day (D30)." In the Findings' Still open, change the OOMPolicy bullet to "B's first stage adds `OOMPolicy=continue`, `RuntimeDirectoryMode=0700` and the `LogRateLimit` lines to the same drop-in."

### C5 [minor]

**Where:** multi-match.md §2 Step 6 'Checking': "ends the connection on the first wrong token, and on any auth message after a claim" versus 'Refusing with a reason': "Every refused auth is answered with a status through `send_auth`: WRONG_TOKEN, ... **The server does not hang up in the same breath**"

**Problem:** D8 was merged in garbled. D8 ended the connection on a wrong token and kept send_auth for the refusals the player must read, and WRONG_TOKEN was not one of those. The plan makes WRONG_TOKEN a read status but keeps 'ends the connection on the first wrong token'. An implementer who disconnects at once loses the status (0 of 6 in the Findings), and P4's proof that 'a wrong token ... ends with its own sentence' then fails.

**Fix:** Replace the bullet with: "- answers the first wrong token with WRONG_TOKEN and accepts no further auth message from that connection, nor any after a claim. One connection claims at most one seat. That connection then ends as every refusal does (below): the client hangs up on reading the status, and `auth_timeout` ends it otherwise."

### C6 [minor]

**Where:** multi-match.md §2 Step 1 match file: "when the countdown ends, which is when D15's clock starts"; Step 6 'The gate': "D15's clock starts when the countdown ends, a time the match file carries"

**Problem:** F11 said the wait is counted from the announce, and the plan counts it from the countdown's end instead. The two differ whenever READY arrives after zero. Step 3 covers exactly that case ('If the countdown reaches zero before READY...'), and with serialised spawns a queued child can be READY long after zero. The time between zero and the announce is then taken out of every player's load window before anybody has been told to load or move. The retry-until-the-load-timeout rule shrinks by the same amount.

**Fix:** Step 1: "- when the countdown ends;". Step 6: "D15's clock starts at the ANNOUNCE, the later of the countdown's end and the child's READY. The match file carries the countdown's end, and the match process starts its clock at the later of that and its own READY."

### C7 [minor]

**Where:** multi-match.md §2 Step 8: "The lobby reaps the child, frees the port, deletes the run files, and logs one line with the match id and the number of matches still running." (Step 1 lists the log among the per-match files.)

**Problem:** V2-1 and E5 were garbled. Both said the lobby 'keeps or deletes' the match log at reap, or keeps the last few. Deleting every run file at reap deletes the log, which on Windows is a child's ONLY output and is what §4 says 'the dev loop and every P2-P4 proof read'. It is gone before the harness can check its positive control. It also deletes the RESULT file, and the plan never says who writes the 'RESULT line' that §4 says tools read from the journal with -o cat.

**Fix:** "The lobby reaps the child, frees the port, logs the RESULT as one journal line carrying the match id (the RESULT line of §4), deletes the match, READY, heartbeat and shutdown files, and keeps the most recent match logs rather than deleting them, since on Windows the log is a child's only output. It then logs one line with the match id and the number of matches still running."

### C8 [minor]

**Where:** multi-match.md §2 Step 1 'Limits on spawning': "Spawns are serialised, one child booting at a time"

**Problem:** D5 and C2(3) are only half in. The plan says spawns are serialised but not what happens to a Start whose spawn has to wait. Is it refused, or queued? Does a queued spawn count toward the cap? When does its READY ceiling start? D5 said 'a countdown that fires meanwhile waits on Starting...', and C2 said the cap is re-checked when the slot is taken. Without this, two Starts pressed while a child boots can both pass the cap, or a queued child can be killed by a ceiling that started before it existed.

**Fix:** Add: "A spawn that has to wait for another child to finish booting is QUEUED. It counts toward the cap from the moment it is queued, its lobby's countdown runs as normal, and at zero the room reads 'Starting the match...' until its child is READY. The READY ceiling counts from the actual spawn, not from the queue."

### C9 [minor]

**Where:** multi-match.md §7 'Off until it ships': "The protocol bump lands in the same commit that turns the switch on ... So a deploy before then changes nothing for multi-match."

**Problem:** V3-1's premise is stated but two things it depends on are not. (1) A deploy between P2 and P5 is harmless only if P2-P4 leave D31's rpc hash and wire_config unchanged. Otherwise every tester is refused as 'different code', switch or no switch. (2) P4 changes what `receive_readiness` means on the client (slots, keyed by `local_slot`), while the in-process path kept alive by the switch still sends peer ids. A client built from main between P4 and the release would draw wrong loading rows against a server running with the switch off. Making the in-process path send slots instead would break the builds already handed out.

**Fix:** Add two bullets: "- P2 to P4 change no `@rpc` signature (D31) and no wire_config field. A change to either would refuse every tester at the next deploy, switch or no switch. - Until P7 the client reads `receive_readiness` as SLOTS only when its announce carried a match port, and as peer ids otherwise. The in-process path keeps sending peer ids, so both the builds already handed out and a build from main work against it."

### C10 [minor]

**Where:** multi-match.md §7 'Gates': "**P4 does not start before the owner's port test** ... stop and bring the owner the choice: a forwarder on the public port, which changes the client side." and "**P5 does not start before the Linux half of the spawn spike**"

**Problem:** F7's gates were moved, from P2 to P4 for the port test and from P3 to P5 for the Linux half, and the plan does not say why. It also narrowed the fallbacks. F7 named a forwarder on the public port OR D44's rejected in-process relay, and said either changes P2 through P4. A forwarder on the lobby's port changes the lobby side (P3) and the announce, not only the client, and the in-process fallback is no longer mentioned.

**Fix:** "**P3 does not start before the owner's port test** has run from the testers' networks. If a tester cannot reach the match range, stop and bring the owner the choice: a forwarder on the public port, which changes the lobby side and the client's dial, or D44's rejected in-process relay, which changes everything from P2 on. P2 may go first, because a forwarder needs match processes too." And: "**P5 does not start before the Linux half of the spawn spike** has run on the box. P3 may land before it only because the switch keeps it off; if the Linux run contradicts §4 (fork, cgroup, `OS.kill`), P3 is revised before P5."

### C11 [minor]

**Where:** Findings 2026-09-25, new section, intro: "Each one is either measured on 4.7.1 ... or read from the Godot 4.7 and systemd sources."

**Problem:** This is stronger than what the verifiers did. Most of the engine files were read from godotengine/godot MASTER, not 4.7: os_unix.cpp (the OS.kill reaping and the raw wait status), scene_multiplayer.cpp, scene_rpc_interface.cpp and enet_multiplayer_peer.cpp. Only one verifier cites a 'saved 4.7 source'. The Linux process facts were never run, and the plan builds code rules on them.

**Fix:** "Each one is either measured on 4.7.1 (Windows, headless, in throwaway projects) or read from source: Godot's master branch for most engine files (4.7 where a copy was saved), which can differ from 4.7.1 in detail, and systemd's man pages and source. The Linux process facts were read, not run."

### C12 [nit]

**Where:** Findings 2026-09-25, new section, intro: "None was refuted."

**Problem:** This overstates the second pass. No finding was refuted as a whole, but 19 of 97 were judged only PLAUSIBLE, several were corrected in part, and four were found by the second pass itself.

**Fix:** "None was refuted outright. 19 of the 97 were judged plausible rather than confirmed, several were corrected in part, and the second pass found four that the first had missed."

### C13 [nit]

**Where:** Findings 2026-09-25, new section, systemd: "journald's stdout stream re-reads its sender when the PID changes, so a forked child's lines carry the child's own `_PID`."

**Problem:** This drops E8's caveat and its version condition, so it reads stronger than the evidence. The plan's '-o cat' rule is safe either way.

**Fix:** Append: "(journald v249 and later; the box runs v259). The last lines a child writes before it exits may lack it, because journald can read them after the child has gone."

### C14 [nit]

**Where:** Findings 2026-09-25, new section, Authentication: "A refusal sent with `send_auth`: followed at once by `disconnect_peer`, arrived 0 times in 6; with the CLIENT hanging up after reading it, arrived 6 times in 6."

**Problem:** This omits the third measured variant, which the A11 and B3 verifiers relied on and the D8 verifier believed unmeasured. A server-side `peer_disconnect_later()` after `send_auth` delivered the reason in the one run that tried it. It is the alternative server-side close that step 6's wrong-token wording needs.

**Fix:** Add a third sub-bullet: "- followed by `peer_disconnect_later()` on the server, arrived in the one run that tried it, and the connection then closed."

### C15 [nit]

**Where:** multi-match.md §8, 'Never evicting a held seat': "A legitimate redial waits until the dead link is noticed."

**Problem:** A2's 'stretch the link at claim' was proposed alongside 'last claim wins', where the length of the stretch never delayed a redial. Combined with never-evict, 'noticed' now means the STRETCHED timeout, past the relay's silence allowance, not ENet's default. Until then every redial reads SEAT_HELD. So the owner's re-claim inside D26's hold only becomes possible after that time, and a link that breaks late in loading reaches D15 first. The plan does not say so.

**Fix:** "A legitimate redial waits until the dead link is noticed. With the link stretched at claim (D41), that is the stretched timeout, past the relay's silence allowance, not ENet's default. A re-claim inside D26's hold is possible only after it, and a link that breaks late in loading reaches D15 first. The load timeout has to stay well above the stretched link timeout plus the hold for the re-claim rule to mean anything."

### C16 [nit]

**Where:** multi-match.md §2 Step 1, match file contents: "- the lobby's pid."

**Problem:** The field has no reader. C14 put it there so that 'a match-server exits when its lobby's pid is gone'. The plan dropped that behaviour and chose E15's (exit at the load timeout with no claim, and stop_server.ps1 stops the rest). On Unix, the obvious check (`OS.is_process_running` on a non-child) logs an engine error on every call, as the plan itself says.

**Fix:** Delete "- the lobby's pid." Or replace it with: "- the lobby's pid, which a stage (a) match process checks through `/proc/<pid>` on each heartbeat, never through `is_process_running`, and exits when it is gone."

### C17 [nit]

**Where:** multi-match.md §4 Stage (b), third option "A lingering user manager for `ltw`", and the later bullets "Instances are named by port ... `systemctl list-units 'ltw-match@*'`", "each with its own D45 ExecStop", "every journal read ... also covers `ltw-match@*`"

**Problem:** Part of E12 was dropped. The generic stage (b) bullets assume the polkit template. Under the user-manager option, units are transient `ltw-match-<port>` under `--user`: `list-units 'ltw-match@*'` finds none of them, a transient unit has no ExecStop unless one is passed, and logs land under `_SYSTEMD_USER_UNIT`, which `-u ltw-match@*` does not read.

**Fix:** Add to the third option: "Its units are transient and named `ltw-match-<port>` under the user manager. The naming, `is-active` and `list-units` lines below then take `systemctl --user` and that name, the D45 stop needs `-p ExecStop=` on the `systemd-run` line, and its logs are read by `_SYSTEMD_USER_UNIT`, not `-u`."

### C18 [nit]

**Where:** multi-match.md §5 'The load test': "memory from N idle match processes ... read as the drop in `MemAvailable`" and "the summary line gains `VmHWM` (the peak) and `RssAnon`"

**Problem:** A8 and E7 were partly dropped. The summary is written only at match end, so a match killed for memory, the case most relevant to a memory cap, leaves no reading. E7's margin for the lobby's own growth is also missing from how the cap is derived.

**Fix:** "...read as the drop in `MemAvailable` as N goes from 0 upward, minus a margin for the lobby's own growth." Add: "During the load test the harness samples each child's `/proc/<pid>/status` (VmHWM), so a match killed for memory still leaves a reading."

### C19 [nit]

**Where:** multi-match.md §7 P5 'Prove' (no line), against §4 "`LogRateLimitIntervalSec` and `LogRateLimitBurst`, set deliberately"

**Problem:** D4's proof was dropped. The rate-limit values are set 'deliberately' but never tested against the flood they exist for. E9's 'Suppressed N messages' rule only fails a load test that has no flood in it.

**Fix:** Add to P5 Prove: "a pending peer flooding one match's port for a whole rate-limit interval does not remove another match's summary line, or the lobby's spawn lines, from the journal."

## Reader 2: correctness
VERDICT: The rewrite is close to fit to implement from, but five major problems need fixing first. I checked its claims about today's code and found them accurate: Boot and CommandLineUtil's exact `--server` match, `_arm_shutdown_file` deleting the file, `begin()` doing both jobs, the count gate, `_drop_peer` not pruning `_ready_ids`, the `--server` filters in the .ps1 scripts, the deploy script's order, `Get-OpenMatches` resetting on 'Listening on port', and the Start button LobbyRoom shows after the countdown fires. The D31 and D44 rows in multiplayer.md are correct, and the new Findings section keeps its dated numbers where the doc rules allow them. I found no counts of code things, live tuning values or hotkeys in the new text. The five majors: (1) P4 puts the protocol bump 'behind the switch', which is impossible and contradicts §6 and §7. (2) The client side is not keyed on the announce, so a client built from main while the switch is off would break the in-process path. (3) `refuse_new_connections` resets a late dial before auth runs, so TOO_LATE and its P2 proof cannot work as written. (4) Step 6 opens the seat claim at admission rather than at the check, which lets two connections claim one seat. (5) P0's fix and proof would start a match below `min_players`. The minor issues are mostly places the rewrite contradicts itself or another doc: 'ends the connection' against 'does not hang up', 'held' used in opposite senses, which `disconnect_peer` is silent, quitting inside `_finish_match`, queued spawns escaping the cap, when D15's clock starts, a respawn's files, and D13, §11.1 and the MenuConfig comment still contradicting the owner's re-claim decision. Each has exact replacement text above. With those edits applied, the plan is coherent enough to implement from.

### C1 [major]

**Where:** §7 Phases, P4 heading: "**P4: the client side** (§6), and the protocol bump, still behind the switch."

**Problem:** This contradicts §7 'Off until it ships' ("The protocol bump lands in the same commit that turns the switch on, at the release (P5)"), §6 ("The bump lands in the same commit that switches match processes on (§7)") and P5 step 2. A bump cannot sit behind the switch, because nothing reads `protocol_version` through it. A bump committed in P4 goes live on the next deploy of main and refuses every tester. That is the D30 decision taken by accident, which is exactly what the switch exists to prevent.

**Fix:** Replace the heading line with: "**P4: the client side** (§6), behind the switch. The protocol bump is NOT committed here: nothing reads `protocol_version` through the switch, so a bump on `main` would refuse every tester at the next deploy. P4's old-build proof runs against a local, uncommitted bump. The bump itself is committed with the switch, in P5's window (§7)."

### C2 [major]

**Where:** §6 Client changes (the whole section), together with §7 "A `NetworkConfig` switch, false in the shipped `.tres`, keeps the lobby on today's in-process path."

**Problem:** The switch gates only the LOBBY. P4's client code lands on main while the switch is off, and P0 still lists "handing out the client build that carries the fixes", which can be built from main at any time. §6 as written makes the client do three things: move at the start of every load, read `receive_readiness` as slots, and hang up on any `receive_match_cancelled`. None of that is right against the in-process path. No port or token is announced, readiness still carries peer ids, and a cancel comes from the lobby itself. A client that hangs up there leaves its lobby: `Lobby._on_peer_left` → `_remove_from_lobby`, which closes the whole lobby if the client was the host. So a D15 abort would dissolve lobbies for players on that build.

**Fix:** Add as §6's first bullet: "**Every client change here is keyed on the ANNOUNCE, never on the switch.** A client takes the move path only when `receive_match_starting` carries a port and a token. Without them - the in-process path, which stays on `main` until P7 - it behaves exactly as today: it does not move, it reads `receive_readiness` as peer ids, and after a cancel it returns to the lobby room still connected. So a client built from `main` at any point before P5 plays against today's server unchanged." Add to P4's regression proof: "a client built from this code plays a probe match and a D15 abort against a server with the switch off, through today's path."

### C3 [major]

**Where:** §2 step 6: "**From the go signal on,** no token is accepted and `refuse_new_connections` is set."; §3: "it sets `refuse_new_connections` from the go signal;"; P2 Prove: "a wrong token, and a token after the go signal, are refused with their statuses, and the client reads them;"

**Problem:** In 4.7, `refuse_new_connections` on a UDP ENet server is honoured in ENetMultiplayerPeer's poll. On the CONNECT event it calls `event.peer->reset()`, before SceneMultiplayer sees the peer and before any auth runs, and it sends nothing back. The ENet socket's own setter is a no-op except for DTLS. So a player who dials after go never reaches `auth_callback` and can never be sent TOO_LATE; their client just sees its own auth time out. TOO_LATE can reach only a connection that was already pending at go, and the P2 proof as written cannot pass. The plan also never says what a token for a `left` seat gets.

**Fix:** Step 6, replace with: "**From the go signal on,** no token is accepted. A connection still pending at go is answered TOO_LATE, and so is a token whose seat is `left`. `refuse_new_connections` is then set, and ENet resets every later dial the moment it connects, before any auth runs. A player who dials after go therefore gets no status: their move retries it as silence and ends with its give-up sentence at the load timeout." P2 Prove, replace with: "a wrong token, a token pending at the go signal and a token for a `left` seat are each refused with its status, and the client reads it; a dial after the go signal is reset by ENet, and the client ends with its give-up sentence." (The alternative, if the owner wants a late player told why: do NOT set `refuse_new_connections`, and answer every auth after go with TOO_LATE, paying the engine ERROR per pending packet that §3 already accepts.)

### C4 [major]

**Where:** §2 step 6, **Checking**: "for a valid token whose seat is unclaimed or held, records `pending[peer] = seat` and completes auth;", read with **Claiming** ("The seat is re-keyed only on `peer_connected`") and **Releasing** ("A claim ends: ... on `peer_authentication_failed`")

**Problem:** The seat's state changes only on `peer_connected`, so between the check and admission the seat still reads unclaimed. A second connection that presents the same token in that window also passes the check and is also completed, and both are admitted. The second `peer_connected` then finds its seat already claimed, and the plan has no rule for that. The natural code re-keys to the newest connection, which is exactly the eviction that §3 and §8 forbid. There is also an internal contradiction: releasing a claim "on peer_authentication_failed" only makes sense if the claim began at the check, while Claiming says it begins at peer_connected. As a result, P2's "a second live claim ... gets SEAT_HELD" is not guaranteed.

**Fix:** Replace Checking's third sub-bullet with: "for a valid token whose seat is unclaimed or held AND has no pending entry, records `pending[peer] = seat` and completes auth. From that moment the seat is TAKEN: any other connection presenting its token gets SEAT_HELD until that pending entry, or the claim that follows it, is released;". Replace Claiming's first sentence with: "The pending entry becomes the claim on `peer_connected`, which fires on admission; only then is the seat re-keyed and its link stretched (D41)." Releasing then reads correctly: a pending entry ends on `peer_authentication_failed`, and a claim ends on `peer_disconnected`.

### C5 [major]

**Where:** §7 P0, "One more live bug": "the gate is "every expected peer is ready"; the go roster is always `_roster_of_ready()`." and "Prove it with LockstepProbe, in a three-player load. Kill one player after it reports ready, and another before it does. The go roster must hold neither, and the start must wait for the third player."

**Problem:** Today's all-ready branch never checks `min_players`; only the timeout branch does. Once drops prune the gate and the roster becomes `_roster_of_ready()`, the all-ready branch can start a match below `min_players`. The proof as written demands exactly that: with two of three players dropped, it expects a start with one player. This breaks D15 ("provided `min_players` are ready") and contradicts step 6's "checked against `min_players` on every path". There is a second gap: after a drop the readiness list is not sent again, so the other loading screens keep showing the departed player as Ready.

**Fix:** Add to the fix list: "- the go roster is checked against `min_players` on EVERY path, and below it the match is aborted with D15's sentence (`_abort`), as step 6 requires of the match process; - the readiness list is sent again after a drop." Replace the proof with: "Prove it with LockstepProbe, in a FOUR-player load. Kill one player after it reports ready, and another before it does. The go roster must hold neither, and the start must wait for the other two. Then run the same kills in a load where they leave fewer than `min_players`: it must end in D15's abort, never in a start."

### C6 [minor]

**Where:** §2 step 6, Checking: "ends the connection on the first wrong token, and on any auth message after a claim." versus **Refusing with a reason**: "Every refused auth is answered with a status through `send_auth`: WRONG_TOKEN, ... **The server does not hang up in the same breath**"

**Problem:** The two bullets contradict each other on the exact behaviour the review measured. An implementer following Checking hangs up on a wrong token, WRONG_TOKEN never arrives (a hang-up at once delivered the reason 0 times in 6), and P2's "a wrong token ... refused with [its] status, and the client reads [it]" fails.

**Fix:** Replace with: "on the first wrong token, answers WRONG_TOKEN and ignores every later auth message from that connection. It does not hang up (see Refusing): the client hangs up on reading the status, and `auth_timeout` closes the connection if it does not. Any auth message after this connection's own check has passed is ignored the same way."

### C7 [minor]

**Where:** §2 step 6: state list "held (inside D26's hold)" and "whose seat is unclaimed or held"; the status "SEAT_HELD" (step 5, step 6, Failure paths, P2); §8: "**Never evicting a held seat**"; P2 Prove: "a second live claim for a held seat gets SEAT_HELD"

**Problem:** "Held" means two opposite things. A seat in the state `held` (inside D26's hold) is one a token MAY claim. SEAT_HELD refuses a claim because a live connection has the seat, and §8 and P2 also use "held seat" in that live-connection sense. Read against step 6's states, P2's proof says a claim on a claimable seat is refused.

**Fix:** Rename the state: "a state: unclaimed, claimed, ready, dropped (inside D26's hold) or left"; "for a valid token whose seat is unclaimed or dropped"; "a dropped link puts the seat in D26's hold (`dropped`)". Rename the status SEAT_HELD to SEAT_TAKEN in step 5, step 6, the Failure paths and P2. §8: "**Never evicting a claimed seat**, rather than letting the last claim win." P2: "a second live claim for a claimed seat gets SEAT_TAKEN;".

### C8 [minor]

**Where:** §2 step 6, Releasing: "in the code that calls `disconnect_peer`, which raises neither signal." (and the Findings' new section: "`disconnect_peer` blocks signals around its own removal, so the code that hangs up must clean up after itself.")

**Problem:** Only `SceneMultiplayer.disconnect_peer` is silent. The project's own hang-up, `Net._disconnect_peer` → `ENetMultiplayerPeer.disconnect_peer(id, false)`, goes through ENet, and so does the `peer_disconnect_later` that step 8 and D45 require. For both, the DISCONNECT event on a later poll raises `peer_disconnected` (or `peer_authentication_failed` for a pending peer). Releasing "in the code" as well would release the claim twice. The second release would treat a close the server made on purpose as a dropped link, and put a seat that should be `left` into D26's hold.

**Fix:** Step 6: "in the code that calls `multiplayer.disconnect_peer` (SceneMultiplayer), which raises neither signal. A close through ENet - `Net._disconnect_peer`, `peer_disconnect_later` - raises `peer_disconnected` (or `peer_authentication_failed`) on a later poll, and the claim is released there, once. A seat the server closes on purpose is marked `left` before the close, so that signal does not put it in the hold." Findings: "`SceneMultiplayer.disconnect_peer` blocks signals around its own removal. A close through ENet (`ENetMultiplayerPeer.disconnect_peer`, `peer_disconnect_later`) still raises them on a later poll."

### C9 [minor]

**Where:** §2 step 8: "**The match process exits on EVERY road into `_finish_match`**, and never goes back to listening."

**Problem:** Two of those roads call `_finish_match()` in the same frame as the `receive_match_cancelled` they exist to deliver: `_abort` (D15's "Not enough players finished loading.") and `_on_shutdown_started` (D45). A quit placed in `_finish_match` destroys the socket before the notice is acknowledged. This is CLAUDE.md's message-before-disconnect trap: those players get a lost-connection line instead of the sentence. Step 8's own "closed with `peer_disconnect_later`" only helps if the exit waits for those closes.

**Fix:** Replace with: "**The match process exits on EVERY road into `_finish_match`**, and never goes back to listening. It exits the way `Net.begin_shutdown` does: every link it has told it is out is closed with `peer_disconnect_later`, and the process quits once those links have closed or the close bound has passed. It never quits inside `_finish_match`, which on the D15-abort and D45 roads runs in the same frame as the cancel it would cut off." Add to P2 Prove: "a D15 abort in a match process delivers its sentence to every admitted client before the process exits."

### C10 [minor]

**Where:** §2 step 1, Limits on spawning: "The cap counts a child from spawn to reap." with "Spawns are serialised, one child booting at a time"; §5: "The cap is the number of match processes, counted from spawn to reap."

**Problem:** Because spawns are serialised, a Start accepted while another child is booting is queued rather than spawned, so it is not counted. Several Starts in that window all pass `_start_refusal`, and the cap is exceeded when the queue drains.

**Fix:** Replace both sentences with: "The cap counts a START from the moment its countdown begins - its child booting, queued behind another boot, or running - until the child is reaped or the start is cancelled. `_start_refusal` checks that count, so a queued start holds its place."

### C11 [minor]

**Where:** §2 step 1, match file: "when the countdown ends, which is when D15's clock starts;" and step 6: "D15's clock starts when the countdown ends, a time the match file carries;"

**Problem:** Step 3 allows the announce to come after zero ("If the countdown reaches zero before READY ..."), and serialised spawns make that likely whenever two lobbies start close together. Every second between zero and the announce is silently taken out of the players' load window. The lobby's "closes a handed-off connection ... when the load window ends" is timed from the same moment. Today D15 counts from the announce: `begin()` resets `_elapsed`.

**Fix:** Step 6: "D15's clock starts at the later of the countdown's end (from the match file) and the child's own READY, which is the earliest the announce can go out;". Step 1: "when the countdown ends; D15's clock runs from then, or from READY if that is later;". Step 4: "the lobby closes it itself if it is still connected when the load window, counted from the announce, ends."

### C12 [minor]

**Where:** §2 step 2, the lobby-poll bullet: "A taken port is respawned once on the next free port", read with step 2 item 4 ("It reads the match file, then deletes it"), which comes before item 7's bind, and step 1 ("Every per-match file ... is named by the match id, so no file can be taken for another spawn's.")

**Problem:** The first child deletes the match file before it tries to bind, so the respawn has no match file unless the lobby writes it again. Both spawns also share one match id, so their files share names. Step 1's "no file can be taken for another spawn's" is therefore false for a respawn: a heartbeat or log left by the failed child is read as the new child's.

**Fix:** Append to the poll bullet: "A respawn first deletes every file the failed spawn left, then writes the match file again, because the first child deleted it on reading. The lobby accepts only a READY whose pid (item 9) is the child it is waiting for." In step 1 write: "so no file can be taken for another match's; a respawn of the same match clears the failed spawn's files first (step 2)."

### C13 [minor]

**Where:** §7 P7: "§11.1, including its "until it lands, one process does both" line;" and multiplayer.md D13's row ("No reconnect. Out is out. A player who disconnects is gone for that match.")

**Problem:** (1) The "Until it lands, one process does both (D19)" line is in multiplayer.md §8 (Lobbies), not §11.1. (2) The owner's binding loading-phase re-claim is recorded only in D44's row. Three places still say the opposite for the loading phase: D13's row, §11.1's bullet "A grace period is not a reconnect. D13 forbids rejoining", and the comment on `MenuConfig.disconnect_grace_seconds` ("This is NOT a reconnect window - out is out"). Neither P2 nor P7 changes them. (3) D30's row still says "A restart ends any match in progress (D19)".

**Fix:** Amend D13's row now, since the decision is already binding, by appending to its rationale: "Before the go signal, a player whose link to the match process breaks may claim their seat again within D26's hold (D44, 2026-09-25); from the go signal on, this row holds unchanged." P2 gains: "the comment on `MenuConfig.disconnect_grace_seconds` gains the loading-phase exception, in the commit that builds the re-claim." Replace P7's bullet with: "- §8, whose 'Until it lands, one process does both (D19)' line goes; - §11.1, whose 'A grace period is not a reconnect' bullet gains the loading-phase re-claim (D44); - D30's row, whose '(D19)' becomes D45;"

### C14 [minor]

**Where:** §7 "Off until it ships": "So a deploy before then changes nothing for multi-match."

**Problem:** This holds only if P2-P4 change nothing that D31 or the wire check reads. The rpc hash (name, arity and mode of every autoload `@rpc`) and `wire_config()` are compared on every connection, whatever the switch says, and §3 already anticipates "A new endpoint goes on another autoload". Any such change landing in P2-P4 refuses every tester at the next deploy of main with "The server is running different code". The switch does not close that door.

**Fix:** Add after that sentence: "That holds only while P2-P4 add, rename or re-arity no `@rpc` and add nothing to `wire_config()`: D31 and the wire check are not behind the switch. A change of that kind that cannot wait lands with the bump, in P5's window."

### C15 [minor]

**Where:** §7 P0: "Left: - running `-InstallShutdown` once, at the release;" versus P5: "`-InstallShutdown` is re-run to apply them" and §7: "at the release (P5)"

**Problem:** §7 defines "the release" as P5, so P0 reads as "install for the first time at P5". That contradicts P5's "re-run" and server.md ("Install the clean shutdown, ONCE, right after the deploy that brings the code for it"). Read that way, D45 is not live on the box until P5, and every deploy before then freezes running matches.

**Fix:** "Left: - running `-InstallShutdown` once, right after the next deploy, which brings the code for it (`server.md`); until then a restart freezes a running match. P5 re-runs it for the new lines;"

### C16 [nit]

**Where:** §2 step 8: "a player sitting on the end panel keeps the heartbeat going."

**Problem:** §4 defines "heartbeat" as the child's heartbeat FILE, which the lobby reads for liveness. Here the word means the player's `submit_alive`. Read together with §4, this sentence says the player keeps the child's liveness file fresh.

**Fix:** "a player sitting on the end panel keeps sending `submit_alive`, so the relay's silence check (D35) never drops them."

### C17 [nit]

**Where:** §1: "`LockstepService` and `CommandService` find a sender's slot by `network_id`. They read the roster through `MatchStart.running_setup()`"

**Problem:** `CommandService._slot_of_peer` reads `References.match_session`, which a relay does not have, so on the relay it always answers 0. Only LockstepService reads `running_setup()`.

**Fix:** "`LockstepService` finds a sender's slot by `network_id`, reading the roster through `MatchStart.running_setup()`, which is null until the go signal. (`CommandService` reads a `MatchSession`, which a relay does not have, and its replication-era endpoint is refused under lockstep.)"

### C18 [nit]

**Where:** §2 step 8: "the match role's own exit codes are 64 and above, below 128."

**Problem:** For a death by signal, Godot returns the raw wait status, which without a core dump is the signal number itself. Linux signals run up to SIGRTMAX, which is 64, so an exit code of 64 is ambiguous.

**Fix:** "the match role's own exit codes lie between 65 and 126."

### C19 [nit]

**Where:** §7 P1: "`systemd-run --unit=ltw-porttest --uid=ltw --gid=ltw /opt/godot/godot --headless --path /srv/ltw/LTW_Test -- --server --port <port>`"

**Problem:** The test server runs as `ltw`, so it shares the live lobby's user:// directory. Its boot rotates and truncates the lobby's `godot.log`, which is the Findings' own measurement and the reason §4 puts `--log-file` on every spawn line.

**Fix:** "`systemd-run --unit=ltw-porttest --uid=ltw --gid=ltw /opt/godot/godot --headless --path /srv/ltw/LTW_Test --log-file /tmp/ltw-porttest.log -- --server --port <port>`"

### C20 [nit]

**Where:** §2 step 1, the match file holds: "the lobby's pid."

**Problem:** Nothing in the plan reads this field; §4's Windows orphan rule uses the load timeout instead. A later reader is likely to wire it to `OS.is_process_running`, which on Linux prints an engine error on every call for a process that is not its child.

**Fix:** Either drop the field, or name its reader: "the lobby's pid, so a match process whose lobby has gone before READY exits at once (read from `/proc/<pid>` on Linux, never through `is_process_running`, which errors for a non-child)."

### C21 [nit]

**Where:** §2 step 3: "the room keeps reading "Starting the match..." with Start disabled", read against "the host's Cancel ... cancels the start" for the whole window

**Problem:** During a countdown the host's Start button IS the Cancel button. If it is disabled after zero, the host has no Cancel for the part of the window the rule covers.

**Fix:** "the room keeps reading "Starting the match...", with the host's button still offering Cancel and everyone else's disabled:"

### C22 [nit]

**Where:** §2 step 6, Claiming: "its link is stretched (D41) at that moment rather than at go."

**Problem:** D41's row stretches ENet's timeout "for the match". Stretching from the claim instead means a claimed loader that crashes is noticed only after the silence allowance plus its margin. Only then does D26's hold start, so the others wait longer for that seat to become `left` than they do today. This consequence is not recorded, and D41's row is not in P7's list.

**Fix:** Add after that sentence: "So a claimed loader that crashes is noticed only once the stretched timeout runs out, and D26's hold starts then: the others wait longer for it than today." P7 gains: "D41's row: in a match process the stretch starts at the claim."

### C23 [nit]

**Where:** §7 P2: "The code comments in Lockstep and Net that cite D19 as current are updated here."

**Problem:** The comment on `NetworkService.rpc_signature` still says "Godot addresses an rpc by its INDEX in the method list ... one method added anywhere shifts every method after it". D31's corrected row now contradicts it, and §3's frozen-handshake rule depends on the corrected reading.

**Fix:** "The code comments in Lockstep and Net that cite D19 as current are updated here, and so is `NetworkService.rpc_signature`'s account of rpc numbering: position in the name-sorted list of that node's rpcs, as D31's row now says."

### C24 [nit]

**Where:** §7 P2 item list and P3 item list; P7: "delete the in-process single-match path that the switch kept alive;"

**Problem:** No phase owns two items: the match role's own `max_peers` (§3), and the lobby's kill of a child whose heartbeat is stale (§4). P2 lists only "the heartbeat", and P3 lists only "reaping, and killed children". P7 also deletes the path but leaves the switch and its boot log line behind.

**Fix:** P2 adds: "the match role's own `max_peers` (§3);". P3 adds: "the stale-heartbeat kill, logged "wedged" (§4);". P7: "delete the in-process single-match path that the switch kept alive, and the switch itself with its boot log line;"

## Reader 3: the implementer
VERDICT: The shape is sound and most of it can be built as written: one process per match, a handoff by token, the client's move as a state of its own, stage (a) before stage (b). Several places would still make an implementer guess, and some of those guesses ship bugs. (1) P0's fix can be read so that it leaves the bug in, and its proof ends below min_players with no positive control. (2) Step 6 uses "held" for two opposite things, so one of P2's proofs contradicts the owner's re-claim rule. Two dials can also claim one seat, and one P2 proof (TOO_LATE after go) cannot pass while refuse_new_connections is set. (3) "Exits on every road into _finish_match" has no ordering, and a naive exit loses the D15 and D45 sentences at the receiver. (4) Four contracts between phases are left open: the match file, the auth bytes and status encoding, the RESULT, and the exit codes. P2 and P3 both need them before either is written. (5) P4's heading puts the protocol bump in P4, against §6 and §7. P5 would release with a guessed cap because its load test can only run after the release. With the fixes below applied, I could start P0, then P2, without guessing.

### I1 [major]

**Where:** §7 P0, the live bug's Fix: "while the gate waits, a drop also clears that player's readiness"

**Problem:** "A drop" has two readings. If it means `_drop_peer`, which runs only after D26's hold, a player who reported ready and then disconnected stays in both `_expected` and `_ready_ids` for the whole hold. The new gate ("every expected peer is ready") can then pass in that window, and `_roster_of_ready()` puts the disconnected player in the go roster. That is the D15 breach the fix exists to close. Whether it happens depends on when the third player finishes loading. Three more gaps: the all-ready path never checks `min_players` (only the timeout path does); the left-behind notice is sent to departed ids; and nothing says readiness is re-broadcast.

**Fix:** Replace the three Fix sub-bullets with:
  - Fix, on today's in-process path:
    - while the gate waits, a DISCONNECT (`_on_peer_left`) removes that player from `_ready_ids` at once and re-broadcasts readiness. This happens at the disconnect, not only at the drop after D26's hold. A player inside the hold still counts as expected and not ready, so the start waits out the hold;
    - the gate is "every peer in `_expected` is in `_ready_ids`", never a count;
    - the go roster is always `_roster_of_ready()`, on both paths. A go roster below `min_players` aborts with D15's sentence on both paths;
    - "You did not finish loading in time." goes only to peers still connected.

### I2 [major]

**Where:** §7 P0: "Prove it with LockstepProbe, in a three-player load. Kill one player after it reports ready, and another before it does. The go roster must hold neither, and the start must wait for the third player."

**Problem:** The proof cannot come out as written. Two drops out of three leave a go roster of one player, which is below min_players, so a correct fix aborts rather than starts. LockstepProbe cannot yet stage the case: the host presses Start at two members, and no flag ties a kill to report_ready or delays one. The third player's timing decides whether the bug shows at all, and no positive control is named. A green run can therefore mean the gate was never exercised.

**Fix:**   - Prove it with LockstepProbe in a FOUR-player load. The probe gains:
    - `--players <n>`: the host starts at n members;
    - `--quit-after-ready`: a hard exit with no goodbye, right after report_ready;
    - `--quit-before-ready`;
    - `--ready-delay <s>`: longer than ENet's detection plus D26's hold.
  - One probe quits after reporting ready, one quits before, and one delays. The go roster must hold exactly the host and the delayed probe. The server's "Match start" line must come after the delayed probe's "Client loaded" line.
  - **Positive control:** the same run on the parent commit starts early, with all four players in the go roster.
  - A three-player run of the same shape must end in D15's abort.

### I3 [major]

**Where:** §2 step 6: "a state: unclaimed, claimed, ready, held (inside D26's hold) or left"; "Readiness is a flag on the SEAT"; "Releasing. A claim ends: ... on `peer_authentication_failed`"; P2 proof "a second live claim for a held seat gets SEAT_HELD"; §8 "Never evicting a held seat"

**Problem:** The word "held" means two opposite things. As a state, a held seat MAY be claimed again (the owner's rule). In the SEAT_HELD status, the P2 proof and §8, it means a seat that a live connection holds, which must be refused. Read against the state list, the P2 proof contradicts the owner's decision. Several other points are open:
- `ready` appears both as a state and as a flag;
- "claim" names both a pending entry and an admitted one. `peer_authentication_failed` only ever ends a pending entry, never a claim;
- nothing says whether each drop starts a fresh hold;
- nothing says what happens at go to seats that are held, unclaimed or not ready (their hold timers, and any PLAYER_LEFT);
- nothing says what a go roster below min_players does on the all-ready path;
- nothing says which status a token gets when its seat is `left`.

**Fix:** Replace the state bullet with a table, and rename the D26 state:
| state | meaning | leaves it when |
|---|---|---|
| unclaimed | never admitted | admitted with its token -> claimed |
| claimed | admitted; peer id set; `ready` flag | `report_leaving` -> left; `peer_disconnected`, or the code's own `disconnect_peer` -> dropped (`ready` cleared, peer id 0) |
| dropped | inside D26's hold | admitted again with its token -> claimed (the next drop starts a fresh hold); the hold runs out -> left |
| left | out for this match | never |

Then:
- "A pending entry is not a claim. `peer_authentication_failed` discards it and changes no state."
- "The early start needs every seat that is not `left` to be claimed and ready, so an unclaimed or dropped seat blocks it. At the D15 timeout the go roster is the claimed, ready seats. On either path a roster below `min_players` aborts with D15's sentence."
- "At go, every seat outside the go roster becomes `left`, its hold is discarded, and no PLAYER_LEFT is issued, because it never had an area."
- "TOO_LATE answers a token whose seat is `left`."

In P2 write: "a token presented while another live or pending connection holds its seat gets SEAT_HELD". In §8 write: "Never evicting a seat that a live connection holds".

### I4 [major]

**Where:** §2 step 6 Checking: "for a valid token whose seat is unclaimed or held, records `pending[peer] = seat` and completes auth" together with "The seat is re-keyed only on `peer_connected`"

**Problem:** Two connections can present one token within a round trip. This happens when a client's connect timer fires after the server has already passed its first dial and the client dials again, or when a sniffed token races the real player. Both pass the check, because the seat stays unclaimed until the first one's `peer_connected`. Both get complete_auth, both are admitted, and two peers share one seat. Nothing says what `peer_connected` does for a seat that is already claimed.

**Fix:** Add to Checking:
- "A seat with a pending entry counts as taken. A token for it gets SEAT_HELD while that entry lives. When the entry is discarded (`peer_authentication_failed`, or the code's own `disconnect_peer`), the seat returns to the state it had."
- "A `peer_connected` for a seat that is already claimed by a live peer cannot happen under this rule. If it does, the newcomer is disconnected and counted, and the seat keeps its holder."

### I5 [major]

**Where:** §2 step 6: "From the go signal on, no token is accepted and `refuse_new_connections` is set."; P2 proof: "a wrong token, and a token after the go signal, are refused with their statuses, and the client reads them"

**Problem:** With refuse_new_connections set, a dial after go never reaches auth. ENetMultiplayerPeer resets the peer at ENet's CONNECT event, before `peer_connected`, so `_add_peer`, the auth callback and send_auth never run. No TOO_LATE can be sent after go, and the P2 proof cannot pass. The late client sees only silence, which the move retries until its own deadline.

**Fix:** Step 6: "From the go signal on, `refuse_new_connections` is set, so a dial after go is reset at ENet's CONNECT, before any auth. The late client hears silence and ends with the give-up sentence at its own deadline. TOO_LATE is sent only before go, to a token whose seat is `left`." P2 proof: "a wrong token gets WRONG_TOKEN and a token for a `left` seat gets TOO_LATE, and the client reads both; a dial after go is never admitted (the probe prints a rising `dial_attempts` and ends with the give-up sentence)."

### I6 [major]

**Where:** §2 step 8: "**The match process exits on EVERY road into `_finish_match`**, and never goes back to listening."

**Problem:** The plan never says how the process exits. The obvious implementation quits inside or right after `_finish_match`, and that loses the sentence on every road that has one. `_abort` sends receive_match_cancelled and calls `_finish_match` in the same call, so the D15 sentence is followed at once by the socket closing on quit. CLAUDE.md says such a message is lost at the receiver. On the D45 road, `_finish_match` runs synchronously inside `shutdown_started.emit`, so an exit hooked there would quit during Net's NOTICE phase, before any notice or close. The separate bullet about peer_disconnect_later says what to call, but not that the quit must wait for it.

**Fix:** Add under step 8's first line:
- "Exiting is ordered, and is never a `quit()` in the frame of the last notice. Every link still open is closed with `peer_disconnect_later`. The process waits until they have all closed or `shutdown_close_seconds` has passed (Net's CLOSING phase, reused), writes the RESULT, and then quits."
- "On the D45 road, Net's own shutdown already does the notice, the close and the quit. The match role only writes the RESULT before `_finish_shutdown` quits."

### I7 [major]

**Where:** §2 step 8: "**The RESULT carries what a relay can know:** the roster (slot, name, colour); start and end; every departure, in order, with its reason and relay turn; ... how the match ended."

**Problem:** P2 writes the RESULT and P3 reads it, and nothing fixes its form. Open questions:
- the file name and the serializer;
- the time format;
- the set of "how it ended" values (§4's "wedged" is missing from the table);
- which slot numbering is meant: after a D15 short start the go roster is renumbered, so "slot" has two meanings;
- what "relay turn" is for a departure before go, when no turn exists;
- whether the lobby reads it before or after the child exits;
- who writes "the RESULT line" that §4 says tools read with `-o cat`. Step 8 has the lobby delete the run files at reap, so if nobody logs the RESULT it is simply lost;
- what "the lobby writes the RESULT" means for a crash: a file or a log line.

**Fix:** Replace the bullet with:
- "**The RESULT is one JSON object in `<run dir>/<match id>.result`.** It is written under a temporary name and renamed into place. Its keys:
  - `match`;
  - `ended`: one of `all_left`, `aborted` (D15, including no seat ever claimed) or `shutdown` (D45), or, written by the lobby, `died`, `never_ready`, `killed` or `wedged`;
  - `seats`: per ANNOUNCED slot, the name, the colour, the go slot (0 if it was not started with), and how it went (`left`, `timed_out`, `went_silent`, `never_claimed`, `not_loaded`), with the relay turn, or -1 before go;
  - `started` and `ended_at` in Unix seconds, `started` being 0 for a match that never began;
  - `desync_tick`, or null;
  - the refusal and stranger counters."
- "The lobby reads it only after the child has exited, adds `exit_code`, logs it as one `Match result` line carrying the match id, and deletes the file with the other run files. For a child with no RESULT, the lobby logs that line itself. The line is what tools read, and nothing keeps the file."

Add the table row: "| the heartbeat went stale | the lobby, as 'wedged' |".

### I8 [major]

**Where:** §2 step 1: "writes the MATCH FILE into its run directory. It holds: the setup; the token map; when the countdown ends ...; the lobby's pid."

**Problem:** This file is the contract between P2 (the child reads it, and P2's harness hand-writes it) and P3 (the lobby writes it), and its form is open: the serializer, the token encoding, the time format and a version check. Tokens are PackedByteArray from Crypto.generate_random_bytes, which does not survive a plain JSON round trip as one. Nothing uses the lobby's pid: a child must not exit when the lobby dies, because stage (b) exists for matches to outlive it.

**Fix:** "The MATCH FILE is one JSON object, `<run dir>/<match id>.match`, written under a temporary name and renamed into place. Its keys:
- `format`: a number. The child exits with BAD_MATCH_FILE on a mismatch;
- `setup`: `MatchSetup.to_dict()`;
- `tokens`: the announced slot, as a string, mapped to the token as 32 lowercase hex characters;
- `countdown_ends`: Unix seconds from `Time.get_unix_time_from_system()`, which the lobby and the child share because they run on one machine;
- `lobby_pid`: logged by the child and nothing more. A match never acts on its lobby's death."

### I9 [major]

**Where:** §2 step 6 Checking: "refuses a payload over a small fixed size; parses a fixed layout, never with `bytes_to_var`"; Refusing: "WRONG_TOKEN, SEAT_HELD, TOO_LATE or SHUTTING_DOWN"

**Problem:** The auth exchange is a wire contract between the client build handed out at P5 and every later match process, and it cannot change afterwards without a bump. The plan names neither the layout nor how the statuses are encoded. It also misses a trap that follows from the engine and P1's pattern. P1's client calls complete_auth right after send_auth, so the client's completion arrives straight after its token. Once it has arrived, the server's send_auth fails. So a refusal must be decided and sent inside the callback call for the token message; a status sent from a later frame never leaves.

**Fix:** Add to step 6:
"**The auth bytes are fixed now.**
- The client's message is exactly the 16 token bytes. Any other length is WRONG_TOKEN.
- A refusal is one byte from an append-only enum declared once, in a script both roles load: WRONG_TOKEN, SEAT_HELD, TOO_LATE, SHUTTING_DOWN.
- Success carries no status: it is `complete_auth`.
- The client calls `send_auth` and then `complete_auth` at once (P1's pattern). So every refusal is decided and sent inside the callback call for that message. A status sent later fails, because the client's side has already completed.
- In the announce and the match file, the token travels as 32 hex characters."

### I10 [major]

**Where:** §7 P4 heading: "**P4: the client side** (§6), and the protocol bump, still behind the switch."

**Problem:** This contradicts §7 ("The protocol bump lands in the same commit that turns the switch on, at the release (P5)") and §6 ("The bump lands in the same commit that switches match processes on"). A bump committed in P4 reaches the box at the next deploy by any session and locks out every tester, which is the D30 decision taken by accident. P4's own proof, "an old build is refused with the sentence", needs a bumped version, and the plan does not say how to get one without committing it.

**Fix:** "**P4: the client side** (§6), behind the switch. **The protocol bump is not committed in P4.** It lands in P5's release commit, together with turning the switch on (§7). P4's old-build proof runs with the bump applied in the working tree only and reverted afterwards, against a checkout of the last handed-out commit. P5 runs it again once the bump is committed."

### I11 [major]

**Where:** §7 P5: "**The release happens in one window:** 1. push; 2. the deploy that turns the switch on, together with the bump ..." and "Prove: ... the load test (§5) sets the cap and the READY ceiling."

**Problem:** The code first runs on the box with the switch on AT the release. The load test that §0 requires for the cap ("set from a load test, not guessed") and that step 2 requires for the READY ceiling can therefore only run afterwards, so the release ships a guessed cap and ceiling. The plan also never says who runs P5's box steps. They need a shell on the box, and a Claude session's ssh to it is refused. P1 names the owner for its box run; P5 names nobody.

**Fix:** Add before P5's release window:
"**P5's measurements run BEFORE the release, on the box, and are the owner's to run.** The implementer hands over exact commands, and what success looks like.
1. Deploy `main` with the switch still off. Players see no change, which is what the switch buys, as long as no rpc changed (§7).
2. Start a second server as a transient unit with the switch on, on a port outside the public one, as P1's port test does, passing the drop-in's settings as properties: `systemd-run --unit=ltw-mmtest --uid=ltw --gid=ltw -p OOMPolicy=continue -p RuntimeDirectory=ltw-mmtest -p RuntimeDirectoryMode=0700 /opt/godot/godot --headless --path /srv/ltw/LTW_Test -- --server --match-processes --port <p> --shutdown-file /run/ltw-mmtest/shutdown`.
3. Run the load test and the probe matches against it. Set the cap and the READY ceiling in the `.tres` from what they show, then stop the unit.
4. Only then open the release window.
The deploy-cancel and OOM proofs need the real unit with its drop-in. They run after the release, with nobody playing."

### I12 [minor]

**Where:** §7 "Off until it ships": "A `NetworkConfig` switch, false in the shipped `.tres`, keeps the lobby on today's in-process path. The P2-P4 proofs turn it on from the command line."

**Problem:** Several things about the switch are open:
- It has no name, no flag and no stated reader.
- It does not say what a client does when it is off. A P4 client that reads `receive_readiness` as slots would mis-draw the in-process path's peer ids.
- It cannot hide an rpc change. D31 hashes every autoload `@rpc`, so any endpoint added or changed before P5 refuses every tester's build at the next deploy, whatever the switch says.

**Fix:** Add:
- "The switch is `NetworkConfig.match_processes_enabled`, false in the shipped `.tres`. `--match-processes` on the LOBBY's command line turns it on for that process, read through `CommandLineUtil` as `--port` is. `run_server.ps1` gains a parameter for it, and `server.md` names the control. Only the lobby reads it; a match process is its own role."
- "With it off, nothing an existing build can observe changes: the announce carries no port or token, and `receive_readiness` still carries peer ids. A P4 client moves only when the announce carries a port, and reads readiness as SLOTS only on a connection it moved to."
- "**No phase before P5 changes the rpc surface.** D31 hashes it (name, argument count, mode), so a new or changed `@rpc` on `main` refuses every tester's build at the next deploy, whatever the switch says. An rpc that is truly needed lands with the bump."

### I13 [minor]

**Where:** §6 Net: "**The move has states of its own**, and ends only as admitted, given up or refused."

**Problem:** The plan never says what "admitted" is. `connected_to_server` fires at admission, but the version handshake runs after it and its pass is silent. A build refusal then arrives as `refuse_protocol_version`, which today tears down to OFFLINE, and MatchStart drops the setup before any sentence is shown. P4 still expects "a mismatched build ends with its own sentence, and the setup is kept". Four smaller gaps:
- A failed attempt walks on to the lobby's other candidate addresses unless the list is collapsed.
- The client stretches its link only at go, while the server now stretches its end at claim.
- The client's auth_timeout is unset.
- The give-up deadline has no anchor.

**Fix:** Add to the Net bullet:
- "`move_to` collapses the candidate list to `current_address()`, so a retry dials that address and never walks on to the lobby's other candidates. It sets `auth_timeout` from the same NetworkConfig value as the match process."
- "The move ends as ADMITTED at `connected_to_server`, and the client stretches its own link then (D41), as the server does at claim."
- "Until the go signal, a `refuse_protocol_version` on the match connection still belongs to the move. It ends the move as REFUSED with the build sentence and is never retried, and the setup is kept until that sentence is on screen."
- "The client gives up at its announce time plus the load timeout. The retry interval is a named NetworkConfig value."

### I14 [minor]

**Where:** §2 step 6: "D15's clock starts when the countdown ends, a time the match file carries"; step 3: "If the countdown reaches zero before READY ..."

**Problem:** When READY arrives after the countdown has ended, the announce is late but D15's clock is already running. Every player then gets less than the load timeout, and a slow boot can use up the load window before anyone has moved. The plan also does not say which moment the lobby's load window for handed-off connections is counted from.

**Fix:** "D15's clock starts at the later of the countdown's end, which the match file carries, and the moment the process wrote READY. So a slow boot never shortens anybody's load. The lobby counts the load window for handed-off connections from its own announce."

### I15 [minor]

**Where:** §2 step 1, Limits on spawning: "Spawns are serialised, one child booting at a time" and "The cap counts a child from spawn to reap."

**Problem:** The plan does not say what happens to a Start pressed while another lobby's child is still booting: whether its countdown starts and its spawn is queued, or whether it is refused. A start that is queued but not yet spawned is not counted by "from spawn to reap", so two queued starts can both pass the cap check and overshoot it.

**Fix:** "A Start pressed while another child is booting still begins its countdown. Its spawn waits in a queue and is made when the booting child writes READY or is reaped. The cap counts a start from the moment its countdown begins, queued or spawned, until its child is reaped or its countdown is cancelled. So 'The server is full' is decided at Start, never after a countdown has run."

### I16 [minor]

**Where:** §2 step 8: "the match role's own exit codes are 64 and above, below 128"; step 2: "A bind that fails exits at once with its own exit code"; "A taken port is respawned once on the next free port"

**Problem:** No code or meaning is listed, and the lobby has to recognise the bind failure to respawn. Step 2 has other refusals (lockstep off, a bad match file) with no code named. Step 2.4 deletes the match file before 2.7 binds, so a respawn finds no match file unless the lobby writes it again.

**Fix:** "The exit codes are named constants in one script both roles read, each with one meaning:
- 0: ended normally, and a RESULT exists;
- PORT_TAKEN: the bind failed. The lobby respawns once on the next free port, and writes the match file again from its own copy, because the first child deleted it;
- BAD_MATCH_FILE: missing, unreadable, or of another `format`;
- LOCKSTEP_OFF: refused to boot with `lockstep_enabled` off.
The lobby acts on PORT_TAKEN alone. Any other code, and any exit with no RESULT, is logged as 'died' with the code."

### I17 [minor]

**Where:** §7 P2: "LockstepProbe gains a role that reads its setup and token from a hand-written match file"; proofs "a claimed seat that drops can claim again inside D26's hold, and cannot after it" and "a connection whose peer id equals another seat's lobby-era id claims only its own seat"

**Problem:** Three proofs cannot be run as written:
- The match process deletes its match file at boot (step 2.4), before READY, so probes started afterwards find nothing to read.
- The re-claim proof names no flag that drops a link without a goodbye and dials again, and no printed count that shows a re-claim happened.
- `create_client` picks a random peer id, so the chosen-id proof needs a crafted client, and the plan does not say how to build one.

**Fix:** - "The P2 harness writes TWO copies of the match file: one for the match process, which deletes it, and one the probes read. Each probe takes `--match-port <p> --match-file <copy> --slot <n>` and reads its token from its slot's entry."
- "For the re-claim proofs the probe gains `--redial-after <s>` (close the link without a goodbye, then dial again with the same token) and prints `claims=<n>`. The positive control is `claims=2` together with the go signal carrying that slot's NEW id. The late case must read TOO_LATE."
- "The chosen-id proof uses a raw `ENetConnection` whose connect data is the chosen id, since ENet takes it as the peer id, and sends the auth bytes by hand."

### I18 [minor]

**Where:** §4 stage (a): "Each match process touches a heartbeat file every few seconds, and the lobby kills and reaps a child whose heartbeat is stale, logging 'wedged'."

**Problem:** The plan does not say when staleness starts being judged. The boot is synchronous and writes no heartbeat, so if the lobby judges it from the spawn, it kills slow but healthy boots and overlaps with the READY ceiling. The period and the bound are not named as config values, and step 8's table has no wedged row.

**Fix:** "The child writes its heartbeat from the main loop from READY on. The lobby judges staleness only after READY; before READY the ceiling is the only bound. The period and the staleness bound are named NetworkConfig values, the bound several periods long. A stale child is killed, reaped as 'wedged', and the lobby logs its RESULT line." Add the table row "| the heartbeat went stale | the lobby, as 'wedged' |".

### I19 [minor]

**Where:** §4 D45 in stage (a): "3. creates the shutdown file of every announced child, and waits for them, with a bound; 4. quits."

**Problem:** Net's shutdown quits as soon as the lobby's OWN links have closed or `shutdown_close_seconds` has passed, and nothing in it waits for children. The plan does not say which component holds the lobby's quit, when the children's files are created relative to the lobby's NOTICE phase, or whether the two notices run one after the other or side by side, which is what its TimeoutStopSec sum assumes.

**Fix:** "The lobby creates every announced child's shutdown file at the START of its own NOTICE phase, so the children's notices and closes run alongside its own. The lobby's Net does not quit until every child it told has been reaped or the bound has passed: `_finish_shutdown` waits on the supervisor. The bound is a named NetworkConfig value, checked against `TimeoutStopSec` in P5."

### I20 [minor]

**Where:** §3: "there is a per-source-address limit on children loading or running, with a sentence"

**Problem:** The plan does not say whose address is counted: the host's, or any member's. It also does not say when the limit is checked, or where its value lives.

**Fix:** "A per-source limit, counted by the HOST's address: the children loading or running for lobbies that address hosted. It is checked at Start, with a sentence, and the limit is a NetworkConfig value. Players behind one NAT share it, which is accepted."

### I21 [minor]

**Where:** §7 P0 "Left: ... handing out the client build that carries the fixes."; §6 "The two client fixes ... are DONE (2026-09-25) and need no bump"

**Problem:** The plan gives no time for handing out this build. "Need no bump" is true of protocol_version, but the lobby-seat commit moved D31's rpc hash. A client build handed out before a matching deploy is refused as 'different code' by the server as deployed.

**Fix:** "- handing out the client build that carries the fixes. It goes out with a deploy of the same commit, never alone, because the lobby-seat rpc (`Lobby.request_seat_state`) moved D31's hash. At the latest it is P5's bumped build, which carries them."

### I22 [nit]

**Where:** §2 step 2 item 3: "It raises its own `/proc/self/oom_score_adj` (Linux only) and reads the value back (§4)."

**Problem:** The plan does not say what value to raise it to, or what a read-back that differs does (exit, or log and continue).

**Fix:** "It raises its own `/proc/self/oom_score_adj` to a positive NetworkConfig value (Linux only) and reads it back. A read-back that differs is an error line and the boot continues, since it is protection, not a precondition. On Windows the step is skipped silently."
