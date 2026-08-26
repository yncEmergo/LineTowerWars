class_name NetworkConfig
extends Resource

## Where the server listens and where a client dials.
## Stored as Resources/Config/network_config.tres, reached via References.network_config.
##
## The address is the ONLY thing that changes when the dev server moves off this
## machine and into a datacentre (D18), which is the whole point of it living in
## a resource rather than in a script.
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
## Where a client dials. Localhost during development (D18); a LAN address or a
## public one later, and nothing else in the project changes when it does.
@export var server_address: String = "127.0.0.1"
## How long a client waits before giving up on a server that never answers.
##
## Needed because ENet reports an unreachable host by simply saying nothing:
## create_client() succeeds against an address with nothing behind it, and the
## connection just never completes. Without this the browser would sit on
## "Connecting..." for ever.
@export var connect_timeout_seconds: float = 5.0

@export_group("Command line")
## Overrides server_address, e.g.  godot -- --address 192.168.1.20
@export var address_argument: String = "--address"
## Overrides port, e.g.  godot -- --port 7778
@export var port_argument: String = "--port"


## The address to dial, command line first.
func resolved_address() -> String:
	return CommandLineUtil.value_for(address_argument, server_address).strip_edges()


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

	if resolved_address().is_empty():
		Log.err("NetworkConfig has no server address, a client has nowhere to dial")
		complete = false

	if max_peers < 1:
		Log.err("NetworkConfig max_peers is below one, nobody could connect", max_peers)
		complete = false

	if connect_timeout_seconds <= 0.0:
		Log.err("NetworkConfig connect timeout must be positive", connect_timeout_seconds)
		complete = false

	return complete
