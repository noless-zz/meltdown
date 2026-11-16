extends RefCounted

## M2's two-client network smoke test: a host and two clients in one process
## play the same simulation over real ENet sockets on 127.0.0.1 and agree on its
## hash (MP-1, MP-2, MP-3, MP-11, ARC-1, ARC-2, #247).
##
## Every loop is bounded by `TIME_LIMIT_MSEC`, so a socket that never delivers
## fails the test instead of hanging the suite.

const SHIP: String = "res://data/ships/default_ship.json"
const DRONE: String = "res://data/robots/drone.json"
const WEAPONS: String = "res://data/weapons/"
const SEED: int = 247
const TICKS: int = 600
const TIME_LIMIT_MSEC: int = 10000


## Fires its primary every tick while drifting forward.
class FiringPilot:
	extends ShipInputSource

	func next_input(_tick: int) -> ShipInput:
		return ShipInput.new(Vector3i(0, 0, -300), Vector3i.ZERO, false, false, true)


## Yaws one way, then pitches and rolls the other, so orientation matters.
class TurningPilot:
	extends ShipInputSource

	func next_input(tick: int) -> ShipInput:
		var turn: Vector3i = Vector3i(0, 700, 0) if tick < 300 else Vector3i(-400, 0, 250)
		return ShipInput.new(Vector3i(200, 0, -500), turn)


## Two armed ships and one armed drone ahead of them; host and clients each
## build their own from the same values.
func _sim() -> Sim:
	var sim: Sim = Sim.new(SEED, 2)
	sim.equip(LocalSession.load_tuning(SHIP).loadout)
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var weapon: WeaponDef = WeaponDef.parse_json(
			FileAccess.get_file_as_string(WEAPONS + def.weapon + ".json"))
	sim.spawn_robot(def, Vector3(0.0, 0.0, -30.0), Basis.IDENTITY, weapon)
	return sim


## Polls everything until `done` returns true or the time runs out; returns
## whether it finished.
func _run_until(host: NetHost, clients: Array[NetClient], done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + TIME_LIMIT_MSEC
	while not done.call():
		if Time.get_ticks_msec() > deadline:
			return false
		var progress: int = host.poll()
		for client: NetClient in clients:
			progress += client.poll()
		if progress == 0:
			OS.delay_usec(200)
	return true


func _start_host(sim: Sim) -> NetHost:
	var host: NetHost = NetHost.new(sim, "host-build")
	if host.start() != OK:
		return null
	return host


func _connect(host: NetHost, client: NetClient, clients: Array[NetClient]) -> String:
	if client.connect_to(host.port) != OK:
		return "client could not start connecting: %s" % client.error
	clients.append(client)
	if not _run_until(host, clients, func() -> bool: return client.accepted or not client.refusal.is_empty()):
		return "client was neither accepted nor refused in time"
	return ""


func _stop(host: NetHost, clients: Array[NetClient]) -> void:
	for client: NetClient in clients:
		client.stop()
	if host != null:
		host.stop()


func test_two_clients_agree_with_the_host_for_600_ticks() -> String:
	var host: NetHost = _start_host(_sim())
	if host == null:
		return "the host could not open a port on 127.0.0.1"
	var clients: Array[NetClient] = []
	var firing: NetClient = NetClient.new(_sim(), FiringPilot.new(), "client-a")
	var turning: NetClient = NetClient.new(_sim(), TurningPilot.new(), "client-b")
	var problem: String = _connect(host, firing, clients)
	if problem.is_empty():
		problem = _connect(host, turning, clients)
	if problem.is_empty() and not host.started:
		problem = "host did not start with two clients"
	var fired: Array[bool] = [false]
	var finished: bool = problem.is_empty() and _run_until(host, clients, func() -> bool:
		fired[0] = fired[0] or not host.sim.projectiles.is_empty()
		return firing.sim.tick >= TICKS and turning.sim.tick >= TICKS)
	if problem.is_empty() and not finished:
		problem = "600 ticks did not finish in %d ms (host %d, clients %d and %d)" % [
				TIME_LIMIT_MSEC, host.sim.tick, firing.sim.tick, turning.sim.tick]
	if problem.is_empty():
		problem = _check_clients(host, clients, fired[0])
	_stop(host, clients)
	return problem


func _check_clients(host: NetHost, clients: Array[NetClient], fired: bool) -> String:
	if not host.error.is_empty():
		return "host reported: %s" % host.error
	for i: int in clients.size():
		var client: NetClient = clients[i]
		if not client.error.is_empty():
			return "client %d reported: %s" % [i, client.error]
		if not client.desyncs.is_empty():
			return "client %d desynced: %s" % [i, client.desyncs]
		var expected: int = client.sim.tick / NetHost.HASH_INTERVAL
		if client.hash_checks != expected or expected < TICKS / NetHost.HASH_INTERVAL:
			return "client %d matched %d hashes by tick %d, expected %d" % [
					i, client.hash_checks, client.sim.tick, expected]
	if not fired:
		return "the firing ship never fired, so projectiles were not exercised"
	if host.sim.ships[1].orientation.is_equal_approx(Basis.IDENTITY):
		return "the turning ship never turned"
	if host.sim.ships[0].primary_slots[0] == null:
		return "the ships were not armed"
	return ""


func test_a_client_with_another_protocol_is_refused_and_told_why() -> String:
	var single: Sim = Sim.new(SEED, 1)
	var host: NetHost = _start_host(single)
	if host == null:
		return "the host could not open a port on 127.0.0.1"
	var clients: Array[NetClient] = []
	var other: int = NetMessages.PROTOCOL_VERSION + 1
	var stranger: NetClient = NetClient.new(Sim.new(SEED, 1), null, "newer", other)
	var problem: String = _connect(host, stranger, clients)
	if problem.is_empty() and stranger.accepted:
		problem = "a client with protocol %d was accepted" % other
	if problem.is_empty() and not (stranger.refusal.contains("protocol version mismatch")
			and stranger.refusal.contains(str(other))
			and stranger.refusal.contains(str(NetMessages.PROTOCOL_VERSION))):
		problem = "refusal '%s' does not name both protocol versions" % stranger.refusal
	if problem.is_empty() and (host.client_count() != 0 or host.refusals.size() != 1):
		problem = "host has %d clients and refusals %s" % [host.client_count(), host.refusals]
	if problem.is_empty() and not _run_until(host, clients, func() -> bool: return stranger.disconnected):
		problem = "the refused client was not disconnected"
	# The ship stays free for a client with the right protocol.
	var friend: NetClient = NetClient.new(Sim.new(SEED, 1), null, "same")
	if problem.is_empty():
		problem = _connect(host, friend, clients)
	if problem.is_empty() and not (friend.accepted and host.started):
		problem = "a matching client was not accepted after the refusal: %s" % friend.refusal
	_stop(host, clients)
	return problem


func test_a_client_whose_sim_differs_reports_a_desync_with_the_tick() -> String:
	var host: NetHost = _start_host(Sim.new(SEED, 1))
	if host == null:
		return "the host could not open a port on 127.0.0.1"
	var clients: Array[NetClient] = []
	var wrong: Sim = Sim.new(SEED, 1)
	wrong.set_start_pose(0, Vector3(5.0, 0.0, 0.0), Basis.IDENTITY)
	var client: NetClient = NetClient.new(wrong, TurningPilot.new())
	var problem: String = _connect(host, client, clients)
	if problem.is_empty() and not _run_until(host, clients, func() -> bool:
			return client.sim.tick >= NetHost.HASH_INTERVAL * 2):
		problem = "120 ticks did not finish in time"
	if problem.is_empty():
		if client.desyncs.size() != 2 or client.hash_checks != 0:
			problem = "expected 2 desyncs and no matches, got %s and %d" % [client.desyncs, client.hash_checks]
		elif client.desyncs[0]["tick"] != NetHost.HASH_INTERVAL:
			problem = "first desync reported at tick %s, expected %d" % [
					client.desyncs[0]["tick"], NetHost.HASH_INTERVAL]
	_stop(host, clients)
	return problem


func test_a_port_in_use_fails_instead_of_hanging() -> String:
	var first: NetHost = _start_host(Sim.new(SEED, 1))
	if first == null:
		return "the host could not open a port on 127.0.0.1"
	var second: NetHost = NetHost.new(Sim.new(SEED, 1))
	var result: Error = second.start(first.port)
	first.stop()
	second.stop()
	if result == OK:
		return "a second host opened port %d, which the first holds" % first.port
	if second.error.is_empty():
		return "the failed start left no error message"
	return ""


func test_the_host_refuses_a_sim_with_no_ships() -> String:
	var host: NetHost = NetHost.new(Sim.new(SEED, 0))
	if host.start() == OK:
		host.stop()
		return "a host with no ships started"
	return ""
