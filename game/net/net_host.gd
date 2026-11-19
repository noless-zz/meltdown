class_name NetHost
extends RefCounted

## The authoritative end of a networked game: owns the only `Sim` that counts,
## one ship per client, and steps it in lockstep with its clients' inputs
## (MP-2). Talks ENet directly with no nodes or scene multiplayer, and runs only
## when the caller calls `poll`, so the same code can run inside a headless
## dedicated server or beside a local player (MP-3, ARC-1).
##
## A client sends `hello` first. The host answers every hello with its own, so
## the client learns the host's protocol and build, and then refuses a client
## whose protocol differs by disconnecting it with `REFUSED_PROTOCOL` (MP-11).
## Ships are handed out in the order clients are accepted.
##
## Tick `t` is stepped only once every client's input for `t` has arrived:
## guessing a missing input would fork the clients from the host. After the
## step every client is sent each ship's applied input for `t`, and, whenever
## the tick count reaches a multiple of `HASH_INTERVAL`, the host's state hash.

## Ticks between state hashes sent to the clients: one a second at 60 Hz.
const HASH_INTERVAL: int = 60
## Inputs further ahead of the host's tick than this are dropped, so a client
## cannot make the host buffer without limit. Two seconds at 60 Hz.
const MAX_INPUT_LEAD: int = 120
## ENet disconnect data, so a refused client can tell why.
const REFUSED_PROTOCOL: int = 1
const REFUSED_FULL: int = 2
const REFUSED_NOT_HELLO: int = 3
const CHANNEL: int = 0

var sim: Sim
## The UDP port the host listens on, set by `start`. Port 0 asks the system
## for a free one, which is how tests avoid colliding with each other.
var port: int = 0
## True once every ship has a client; ticks run only from then on.
var started: bool = false
## Why each refused client was refused, in order.
var refusals: Array[String] = []
## The most recent problem with the socket, a client or a packet; empty if none.
var error: String = ""

var _build: String = ""
var _connection: ENetConnection = null
## Ship index of every accepted client, by its peer.
var _ships: Dictionary[ENetPacketPeer, int] = {}
## Clients in ship order, for relaying.
var _clients: Array[ENetPacketPeer] = []
## Refused clients still waiting to be disconnected; their packets are ignored.
var _refused: Dictionary[ENetPacketPeer, bool] = {}
## Tick to one input per ship, null until it arrives.
var _pending: Dictionary[int, Array] = {}


## `game_sim` must have one ship per expected client; `build` is the build
## string sent in the host's hello.
func _init(game_sim: Sim, build: String = "") -> void:
	sim = game_sim
	_build = build


## Opens the socket on `address` and `listen_port` (0 for any free port).
## Returns the error instead of retrying, so a test fails rather than hangs.
func start(listen_port: int = 0, address: String = "127.0.0.1") -> Error:
	if sim == null or sim.ships.is_empty():
		error = "the host needs a sim with at least one ship"
		return ERR_INVALID_PARAMETER
	_connection = ENetConnection.new()
	var result: Error = _connection.create_host_bound(address, listen_port, sim.ships.size() + 1, 1)
	if result != OK:
		error = "could not open %s:%d (%s)" % [address, listen_port, error_string(result)]
		_connection = null
		return result
	port = _connection.get_local_port()
	return OK


## Handles every waiting network event and steps every tick whose inputs are
## complete. Returns the number of ticks stepped.
func poll() -> int:
	if _connection == null:
		return 0
	while true:
		var event: Array = _connection.service(0)
		var type: int = event[0]
		if type == ENetConnection.EVENT_NONE:
			break
		if type == ENetConnection.EVENT_ERROR:
			error = "the host socket failed"
			break
		var peer: ENetPacketPeer = event[1]
		if type == ENetConnection.EVENT_RECEIVE:
			_receive(peer, peer.get_packet())
		elif type == ENetConnection.EVENT_DISCONNECT and _refused.has(peer):
			_refused.erase(peer)
		elif type == ENetConnection.EVENT_DISCONNECT and _ships.has(peer):
			error = "client for ship %d disconnected at tick %d" % [_ships[peer], sim.tick]
	var stepped: int = _step_ready_ticks()
	_connection.flush()
	return stepped


## Closes the socket; clients see a disconnect.
func stop() -> void:
	if _connection == null:
		return
	for peer: ENetPacketPeer in _clients:
		peer.peer_disconnect()
	_connection.flush()
	_connection.destroy()
	_connection = null


## Number of clients accepted so far.
func client_count() -> int:
	return _clients.size()


func _receive(peer: ENetPacketPeer, bytes: PackedByteArray) -> void:
	if _refused.has(peer):
		return
	var message: Dictionary = NetMessages.decode(bytes)
	if not _ships.has(peer):
		_greet(peer, message)
		return
	if message.has("error"):
		error = "ship %d sent a bad packet: %s" % [_ships[peer], message["error"]]
		return
	if message["type"] != NetMessages.TYPE_INPUT:
		return
	var tick: int = message["tick"]
	if tick < sim.tick or tick >= sim.tick + MAX_INPUT_LEAD:
		error = "ship %d sent input for tick %d while the host is at %d" % [_ships[peer], tick, sim.tick]
		return
	if not _pending.has(tick):
		var slots: Array = []
		slots.resize(sim.ships.size())
		_pending[tick] = slots
	# The connection decides the ship, not the packet: a client cannot fly
	# someone else's ship by writing another index.
	var ship: int = _ships[peer]
	if _pending[tick][ship] == null:
		_pending[tick][ship] = message["input"]


## A client's first packet must be a hello with this build's protocol.
func _greet(peer: ENetPacketPeer, message: Dictionary) -> void:
	var is_hello: bool = message.get("type", -1) == NetMessages.TYPE_HELLO
	var reason: int = 0
	if message.has("error"):
		# A protocol mismatch is the one decode error a newer or older build
		# sends on purpose; anything else is not a hello at all.
		is_hello = String(message["error"]).begins_with("protocol version mismatch")
		reason = REFUSED_PROTOCOL if is_hello else REFUSED_NOT_HELLO
		refusals.append(message["error"])
	elif not is_hello:
		reason = REFUSED_NOT_HELLO
		refusals.append("first packet was not a hello")
	elif started:
		reason = REFUSED_FULL
		refusals.append("every ship already has a client")
	if is_hello:
		# Answered even when refusing, so the client can name the host's version.
		peer.send(CHANNEL, NetMessages.encode_hello(_build), ENetPacketPeer.FLAG_RELIABLE)
	if reason != 0:
		_refused[peer] = true
		peer.peer_disconnect_later(reason)
		return
	_ships[peer] = _clients.size()
	_clients.append(peer)
	started = _clients.size() == sim.ships.size()


func _step_ready_ticks() -> int:
	var stepped: int = 0
	while started and _is_complete(sim.tick):
		var applied: int = sim.tick
		var inputs: Array[ShipInput] = []
		inputs.assign(_pending[applied])
		_pending.erase(applied)
		sim.step(inputs)
		stepped += 1
		for ship: int in inputs.size():
			_send_all(NetMessages.encode_input(applied, ship, inputs[ship]))
		if sim.tick % HASH_INTERVAL == 0:
			_send_all(NetMessages.encode_state_hash(sim.tick, sim.state_hash()))
	return stepped


func _is_complete(tick: int) -> bool:
	if not _pending.has(tick):
		return false
	for input: Variant in _pending[tick]:
		if input == null:
			return false
	return true


func _send_all(bytes: PackedByteArray) -> void:
	for peer: ENetPacketPeer in _clients:
		peer.send(CHANNEL, bytes, ENetPacketPeer.FLAG_RELIABLE)
