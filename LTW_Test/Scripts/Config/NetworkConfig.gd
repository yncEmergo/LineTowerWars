class_name NetworkConfig
extends Resource

## Where the server listens and where a client dials.
## Stored as Resources/Config/network_config.tres, reached via References.network_config.
##
## The addresses are the ONLY thing that changes when the dev server moves off
## this machine and into a datacentre (D18), which is the whole point of them
## living in a resource rather than in a script.
##
## Both the address and the port can be overridden from the command line, so a
## second server can be started on another port, or one client aimed at another
## machine, without editing this file or rebuilding. See CommandLineUtil for
## the two spellings that are accepted.
##
## **There is deliberately no tick rate here**, although the roadmap once listed
## one. The simulation tick IS the engine's physics tick, set in project.godot
## and read back through MatchSession.tick_seconds() (D11). A copy of that
## number in this file would be a second place to change it and a first chance
## for the two to disagree.

@export_group("Server")
## The port the server listens on. Overridable with the port argument below.
@export var port: int = 7777
## Total simultaneous connections the SERVER accepts, across every lobby and
## match it is running at once.
##
## NOT the same number as MenuConfig.max_players, which is seats in ONE lobby
## (2-12, per game_rules.md). One process currently runs the lobby and the
## matches together (D19), so this has to cover everyone connected to it.
@export var max_peers: int = 32

@export_group("Client")
## Every address a client will try, in order, taking the first that answers.
##
## A LIST rather than one address because the dev loop has no fixed server: two
## machines take it in turns, and whichever is not hosting has to find the one
## that is without being rebuilt or told. Put 127.0.0.1 first, so a player on
## the same PC as the server connects instantly instead of waiting out a
## machine that is switched off.
##
## The command line still wins outright when given: --address collapses this to
## the single address named, which is what the headless probes and a deliberate
## one-off test both want. See resolved_addresses().
##
## Setting these up across two PCs - and why the addresses here are the ones
## Tailscale hands out rather than public ones - is server.md.
@export var server_addresses: PackedStringArray = PackedStringArray(["127.0.0.1"])
## How long a client waits on ONE address before trying the next.
##
## Needed because ENet reports an unreachable host by simply saying nothing:
## create_client() succeeds against an address with nothing behind it, and the
## connection just never completes. Without this the browser would sit on
## "Connecting..." for ever.
##
## This is PER ADDRESS, so a list of three costs three times this at worst -
## which is the whole reason it is no longer the five seconds one address could
## afford. A dead candidate is the common case now, not the failure case.
@export var connect_timeout_seconds: float = 3.0

@export_group("Compatibility")
## What this build speaks. A client stating a different number is refused by the
## server with a message naming both, rather than being let in to desync.
##
## **Bump it by hand whenever a change makes two builds unable to play together**
## - a command's arguments, a replicated field, the meaning of an authored id.
## Adding content does not need a bump; the ability and unit-type registries are
## built from the folders, so a build with more of it still agrees about what it
## shares. Forgetting to bump leaves exactly the failure this replaces, so when
## in doubt, bump: the cost is a re-download, and the cost of not doing it is a
## match that goes subtly wrong.
##
## WorldChecksum stays the backstop underneath this. A version number catches
## two builds that were never meant to meet; the checksum catches two builds
## that agree on their version and still built different worlds.
@export var protocol_version: int = 1
## How long the server waits for a freshly connected peer to state its version
## before dropping it.
##
## The point is a build from BEFORE the handshake existed: it connects, says
## nothing, and would otherwise sit there looking connected. A client that is
## merely slow has nothing to send but one integer, so this can be short.
@export var handshake_timeout_seconds: float = 5.0

@export_group("Lockstep")

## Whether the game plays by lockstep or by state replication.
##
## ON in the shipped `.tres`. Off, the match is server-authoritative exactly as
## it was before the cutover: the server simulates, clients draw snapshots, and
## none of `LockstepService` runs. The old model is kept switchable rather than
## deleted because it is the only way to compare the two under load.
##
## **Off is not merely a different model, it also silences the checksums**, and
## that is a correctness matter rather than a preference. Comparing world
## checksums between machines is meaningless while only one of them simulates:
## a client under replication holds a REPLICA, not an independently computed
## world, so the comparison disagrees as soon as a tower is built. Left ungated
## it ended a live match on 2026-09-04. "Do these two machines agree" only has
## an answer while both are computing.
@export var lockstep_enabled: bool = true

## How many simulation ticks make one lockstep TURN.
##
## A turn is the unit commands are scheduled in and checksums are compared on.
##
## **ONE, and there is no good reason for it to be anything else.** A turn
## longer than a tick quantises every order to its length twice over - once
## waiting for the turn to close, once again because the delay is counted in
## turns - so two ticks per turn cost 100 ms of latency to save ten packets a
## second. The packets are a few dozen bytes and usually empty. That trade was
## backwards, and it was most of why an order took 200-300 ms on a LAN.
##
## What it does NOT change is the simulation rate: every tick still runs
## whatever this says. The floor underneath it is the tick itself - an order can
## only take effect on a tick boundary, so 20 Hz costs up to 50 ms on its own
## (D11, and see `multiplayer.md` 11.4).
@export var ticks_per_turn: int = 1

## Whether the input delay is MEASURED from the live connection or fixed.
##
## **On, and the fixed number below exists only so the two can be compared.**
## A fixed delay has to be set for the worst connection anybody might have, so
## everybody pays for it - which is how a LAN game ended up feeling like a 300
## ms one. Measured, it is whatever the wire actually needs and no more, so a
## player on a good connection gets a responsive game and a player on a bad one
## gets a playable one.
##
## Safe to change at any moment and safe to differ between peers, because the
## delay decides only WHICH turn an order is booked for, never what that turn
## does. See `LockstepService.delay_turns()`.
@export var adaptive_delay: bool = true

## The delay used when `adaptive_delay` is off, in TURNS.
##
## Only for deliberate comparison: set it, turn adaptation off, and the game
## behaves like a build with no measurement in it. Paired runs against the same
## server are the only honest way to show the adaptive path is actually winning
## (`CLAUDE.md`).
@export var fixed_delay_turns: int = 2

## The smallest delay adaptation may choose, in TURNS.
##
## **One, and it cannot be zero.** A turn whose orders have not arrived cannot
## be simulated, and zero would book an order for a turn already being run - so
## every peer would stall on every order instead of merely feeling heavy.
@export var min_delay_turns: int = 1

## The largest delay adaptation may choose, in TURNS.
##
## A ceiling rather than a target: past this the connection is bad enough that
## stalling is the honest outcome, and stretching the delay further only trades
## a visible stutter for an invisible sluggishness nobody asked for.
@export var max_delay_turns: int = 12

## Head room added on top of the measured round trip, in MILLISECONDS.
##
## A link averaging 30 ms that spikes to 70 needs the 70, and a mean cannot see
## a spike. ENet's own round-trip VARIANCE is added first and this sits on top
## of it, covering what neither measures: the frame a packet waits before Godot
## flushes it, and the scheduling jitter of two machines nobody is tuning.
##
## The trade is exact and worth stating: every millisecond here is a millisecond
## of input delay for everybody, and every millisecond missing is a risk of a
## stall. A stall is worse than sluggishness, so this is deliberately generous.
@export var jitter_margin_ms: int = 20

## How often the world is checksummed and compared between machines, in TURNS.
##
## Every turn is the strictest and the most expensive; comparing rarely means a
## desync is found later and is harder to trace back. Detection only - there is
## no correction to send. See MatchStartService.receive_desync.
@export var checksum_every_turns: int = 5

@export_group("Command line")
## Collapses server_addresses to the one named, e.g.
##   godot -- --address 192.168.1.20
@export var address_argument: String = "--address"
## Overrides port, e.g.  godot -- --port 7778
@export var port_argument: String = "--port"


## Every address to try, in order, command line first.
##
## An --address on the command line collapses the list to that one entry: it is
## an instruction to dial THAT machine, and walking on to the others afterwards
## would quietly disobey it. Without one, the authored list is used as written.
##
## Blank entries are dropped rather than attempted, so a half-filled row in the
## inspector costs nothing at runtime.
func resolved_addresses() -> PackedStringArray:
	var override: String = CommandLineUtil.value_for(address_argument, "").strip_edges()
	if !override.is_empty():
		return PackedStringArray([override])

	var addresses: PackedStringArray = PackedStringArray()
	for candidate in server_addresses:
		var trimmed: String = candidate.strip_edges()
		if !trimmed.is_empty() && !(trimmed in addresses):
			addresses.append(trimmed)
	return addresses


## The first address that would be tried, for a message written before any
## attempt has been made. What is CURRENTLY being tried is Net.current_address(),
## which is a different question the moment the list has more than one entry.
func resolved_address() -> String:
	var addresses: PackedStringArray = resolved_addresses()
	if addresses.is_empty():
		return ""
	return addresses[0]


## The port to use, command line first. Applies to both ends: the server listens
## on it and the client dials it, so one argument moves a whole test pair.
func resolved_port() -> int:
	return CommandLineUtil.int_for(port_argument, port)


## Reports everything unusable at once rather than one failed connection at a
## time. Called before the peer is created, so a bad number is a message rather
## than a silent refusal to connect.
func validate() -> bool:
	var complete: bool = true

	var effective_port: int = resolved_port()
	if effective_port < 1 || effective_port > 65535:
		Log.err("NetworkConfig port is outside the legal range", effective_port)
		complete = false

	if resolved_addresses().is_empty():
		Log.err("NetworkConfig has no server addresses, a client has nowhere to dial")
		complete = false

	if handshake_timeout_seconds <= 0.0:
		Log.err("NetworkConfig handshake timeout must be positive", handshake_timeout_seconds)
		complete = false

	if protocol_version < 1:
		Log.err("NetworkConfig protocol_version must be at least one", protocol_version)
		complete = false

	if max_peers < 1:
		Log.err("NetworkConfig max_peers is below one, nobody could connect", max_peers)
		complete = false

	if ticks_per_turn < 1:
		Log.err("NetworkConfig ticks_per_turn must be at least one", ticks_per_turn)
		complete = false

	# Zero would mean simulating a turn whose commands cannot have arrived yet.
	if min_delay_turns < 1:
		Log.err("NetworkConfig min_delay_turns must be at least one", min_delay_turns)
		complete = false

	if max_delay_turns < min_delay_turns:
		Log.err("NetworkConfig max_delay_turns is below min_delay_turns", {
			"min": min_delay_turns, "max": max_delay_turns,
		})
		complete = false

	if fixed_delay_turns < 1:
		Log.err("NetworkConfig fixed_delay_turns must be at least one", fixed_delay_turns)
		complete = false

	if jitter_margin_ms < 0:
		Log.err("NetworkConfig jitter_margin_ms cannot be negative", jitter_margin_ms)
		complete = false

	if checksum_every_turns < 1:
		Log.err("NetworkConfig checksum_every_turns must be at least one",
			checksum_every_turns)
		complete = false

	if connect_timeout_seconds <= 0.0:
		Log.err("NetworkConfig connect timeout must be positive", connect_timeout_seconds)
		complete = false

	return complete
