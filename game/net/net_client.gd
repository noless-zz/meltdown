class_name NetClient
extends RefCounted

## One player's end of a networked game. Sends its ship's input for each tick
## to the host and runs its own `Sim` purely from the inputs the host says it
## applied, so it can never step a tick the host did not (MP-2). There is no
## prediction yet (M5): the client's sim trails the host by the round trip.
##
## Every state hash the host sends is compared with this sim's hash at the same
## tick; a difference is recorded in `desyncs` with the tick. Like `NetHost`,
## it uses ENet directly, holds no nodes and runs only when `poll` is called
## (MP-3, ARC-1).

## Ticks of input the client may send ahead of its own sim. Small, so a client
## is never more than a few ticks of input ahead of what it has seen applied.
const INPUT_LEAD: int = 3

var sim: Sim
## True once the host has answered the hello with a matching protocol.
var accepted: bool = false
## Why the host refused this client; empty unless refused (MP-11).
var refusal: String = ""
## The most recent problem with the socket or a packet; empty if none.
var error: String = ""
## True once the connection is gone, for whatever reason.
var disconnected: bool = false
## The host's build string from its hello, for a mismatch report.
var host_build: String = ""
## State hashes that matched the host's.
var hash_checks: int = 0
## One `{"tick", "host_hash", "client_hash"}` per mismatched hash, in order.
var desyncs: Array[Dictionary] = []

var _input_source: ShipInputSource
var _build: String = ""
var _protocol: int = NetMessages.PROTOCOL_VERSION
var _connection: ENetConnection = null
var _host: ENetPacketPeer = null
## The next tick this client will send input for.
var _next_send_tick: int = 0
## Tick to one input per ship, as relayed by the host.
var _relayed: Dictionary[int, Array] = {}
## Hashes waiting for their counterpart, by tick.
var _host_hashes: Dictionary[int, int] = {}
var _own_hashes: Dictionary[int, int] = {}


## `client_sim` must be built exactly as the host's (seed, ship count, loadout,
## robots), or the first hash check reports a desync. `protocol` exists so a
## test can play an older or newer build.
func _init(client_sim: Sim, input_source: ShipInputSource = null, build: String = "",
		protocol: int = NetMessages.PROTOCOL_VERSION) -> void:
	sim = client_sim
	_input_source = input_source if input_source != null else ShipInputSource.new()
	_build = build
	_protocol = protocol


## Starts connecting; the hello goes out once ENet reports the connection.
func connect_to(host_port: int, address: String = "127.0.0.1") -> Error:
	_connection = ENetConnection.new()
	var result: Error = _connection.create_host(1, 1)
	if result == OK:
		_host = _connection.connect_to_host(address, host_port, 1)
		if _host == null:
			result = ERR_CANT_CONNECT
	if result != OK:
		error = "could not connect to %s:%d (%s)" % [address, host_port, error_string(result)]
		_connection = null
	return result


## Handles every waiting network event, steps every tick whose relayed inputs
## are complete and sends input up to `INPUT_LEAD` ticks ahead. Returns the
## number of ticks stepped.
func poll() -> int:
	if _connection == null:
		return 0
	while true:
		var event: Array = _connection.service(0)
		var type: int = event[0]
		if type == ENetConnection.EVENT_NONE:
			break
		if type == ENetConnection.EVENT_ERROR:
			error = "the client socket failed"
			break
		if type == ENetConnection.EVENT_CONNECT:
			_host.send(NetHost.CHANNEL, NetMessages.encode_hello(_build, _protocol),
					ENetPacketPeer.FLAG_RELIABLE)
		elif type == ENetConnection.EVENT_DISCONNECT:
			_on_disconnect(event[2])
			break
		elif type == ENetConnection.EVENT_RECEIVE:
			_receive(_host.get_packet())
	if _connection == null:
		return 0
	var stepped: int = _step_ready_ticks()
	_send_inputs()
	_connection.flush()
	return stepped


## Closes the connection.
func stop() -> void:
	if _connection == null:
		return
	if _host != null and not disconnected:
		_host.peer_disconnect()
		_connection.flush()
	_connection.destroy()
	_connection = null
	disconnected = true


func _receive(bytes: PackedByteArray) -> void:
	var message: Dictionary = NetMessages.decode(bytes)
	if message.has("error"):
		if not accepted and refusal.is_empty():
			refusal = "host refused: %s" % message["error"]
		else:
			error = "bad packet from host: %s" % message["error"]
		return
	match int(message["type"]):
		NetMessages.TYPE_HELLO:
			host_build = message["build"]
			if message["protocol"] != _protocol:
				refusal = "host refused: protocol version mismatch: host %d (build %s), this client %d" \
						% [message["protocol"], host_build, _protocol]
			else:
				accepted = true
		NetMessages.TYPE_INPUT:
			_store_input(message)
		NetMessages.TYPE_STATE_HASH:
			_host_hashes[message["tick"]] = message["hash"]
			_compare_hashes(message["tick"])


func _store_input(message: Dictionary) -> void:
	var tick: int = message["tick"]
	var ship: int = message["ship"]
	if tick < sim.tick or ship >= sim.ships.size():
		error = "host relayed ship %d for tick %d while this client is at %d with %d ships" \
				% [ship, tick, sim.tick, sim.ships.size()]
		return
	if not _relayed.has(tick):
		var slots: Array = []
		slots.resize(sim.ships.size())
		_relayed[tick] = slots
	_relayed[tick][ship] = message["input"]


func _step_ready_ticks() -> int:
	var stepped: int = 0
	while _relayed.has(sim.tick) and not _relayed[sim.tick].has(null):
		var inputs: Array[ShipInput] = []
		inputs.assign(_relayed[sim.tick])
		_relayed.erase(sim.tick)
		sim.step(inputs)
		stepped += 1
		if sim.tick % NetHost.HASH_INTERVAL == 0:
			_own_hashes[sim.tick] = sim.state_hash()
			_compare_hashes(sim.tick)
	return stepped


## Compares once both sides' hash for `tick` is known. The host's hash can
## arrive before this client has stepped to that tick, or after.
func _compare_hashes(tick: int) -> void:
	if not _host_hashes.has(tick) or not _own_hashes.has(tick):
		return
	var host_hash: int = _host_hashes[tick]
	var own_hash: int = _own_hashes[tick]
	_host_hashes.erase(tick)
	_own_hashes.erase(tick)
	if host_hash == own_hash:
		hash_checks += 1
	else:
		desyncs.append({"tick": tick, "host_hash": host_hash, "client_hash": own_hash})


func _send_inputs() -> void:
	if not accepted or disconnected:
		return
	while _next_send_tick < sim.tick + INPUT_LEAD:
		var input: ShipInput = _input_source.next_input(_next_send_tick)
		# The host fills in the ship from the connection, so 0 is sent here.
		var bytes: PackedByteArray = NetMessages.encode_input(_next_send_tick, 0, input)
		if bytes.is_empty():
			error = "input for tick %d does not fit a packet" % _next_send_tick
			return
		_host.send(NetHost.CHANNEL, bytes, ENetPacketPeer.FLAG_RELIABLE)
		_next_send_tick += 1


func _on_disconnect(reason: int) -> void:
	disconnected = true
	accepted = false
	if refusal.is_empty():
		match reason:
			NetHost.REFUSED_PROTOCOL:
				refusal = "host refused: protocol version mismatch"
			NetHost.REFUSED_FULL:
				refusal = "host refused: every ship already has a client"
			NetHost.REFUSED_NOT_HELLO:
				refusal = "host refused: the first packet was not a hello"
			_:
				error = "disconnected from the host at tick %d" % sim.tick
	_connection.destroy()
	_connection = null
