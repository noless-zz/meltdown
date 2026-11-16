extends RefCounted

## Projectiles hitting robots: segment test, damage, destruction and events
## (CMB-1, CMB-3, MP-2, ARC-2, #205).

const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## `Sim.state_hash()` after the reference flight of `test_sim_robots.gd`,
## recorded on `main` before robots existed (commit 2c68c89). Hits must not
## change the hash of a run with no robots.
const REFERENCE_HASH: int = 3186405771


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


## `ship_count` ships at rest; ship `shooter` carries the pulse cannon. Ships
## start facing -Z, so the cannon fires along -Z from where the ship sits.
func _sim(ship_count: int = 1, shooter: int = 0) -> Sim:
	var sim: Sim = Sim.new(5, ship_count)
	sim.ships[shooter].primary_slots[0] = _cannon()
	return sim


func _input(fire: bool, afterburner: bool = false) -> ShipInput:
	return ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, afterburner, false, fire)


func _step(sim: Sim, fire: bool) -> void:
	var inputs: Array[ShipInput] = [_input(fire)]
	sim.step(inputs)


func _count(sim: Sim, kind: SimEvent.Kind) -> int:
	var found: int = 0
	for event: SimEvent in sim.last_events:
		if event.kind == kind:
			found += 1
	return found


## Fires one shot on the first tick, then flies `ticks` more without firing.
## Returns the number of ROBOT_HIT events seen.
func _one_shot(sim: Sim, ticks: int) -> int:
	_step(sim, true)
	var hits: int = _count(sim, SimEvent.Kind.ROBOT_HIT)
	for i: int in ticks:
		_step(sim, false)
		hits += _count(sim, SimEvent.Kind.ROBOT_HIT)
	return hits


func test_holding_fire_destroys_a_drone_after_enough_hits() -> String:
	var sim: Sim = _sim()
	var drone: RobotDef = _drone()
	var damage: float = _cannon().damage
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -30.0), Basis.IDENTITY)
	var hits: int = 0
	var destroyed: int = 0
	for i: int in 300:
		_step(sim, true)
		hits += _count(sim, SimEvent.Kind.ROBOT_HIT)
		destroyed += _count(sim, SimEvent.Kind.ROBOT_DESTROYED)
		if destroyed > 0:
			break
		if sim.robots.size() != 1:
			return "drone removed at tick %d without a ROBOT_DESTROYED event" % sim.tick
		if not is_equal_approx(sim.robots[0].hull, drone.hull - hits * damage):
			return "hull %s after %d hits" % [sim.robots[0].hull, hits]
	var expected: int = ceili(drone.hull / damage)
	if destroyed != 1 or hits != expected:
		return "%d hits and %d destructions, expected %d hits and 1" % [hits, destroyed, expected]
	if not sim.robots.is_empty():
		return "destroyed drone still in Sim.robots at the end of its tick"
	return ""


func test_shot_passing_beside_the_drone_misses() -> String:
	var drone: RobotDef = _drone()
	var sim: Sim = _sim()
	sim.spawn_robot(drone, Vector3(drone.radius + 0.05, 0.0, -20.0), Basis.IDENTITY)
	if _one_shot(sim, 60) != 0:
		return "a shot %s m from the drone's centre hit it" % (drone.radius + 0.05)
	if sim.robots[0].hull != drone.hull:
		return "a missed drone lost hull"
	var near: Sim = _sim()
	near.spawn_robot(drone, Vector3(drone.radius - 0.05, 0.0, -20.0), Basis.IDENTITY)
	if _one_shot(near, 60) != 1:
		return "a shot just inside the radius did not hit"
	return ""


func test_shot_passing_through_between_ticks_hits() -> String:
	var drone: RobotDef = _drone()
	var step_length: float = _cannon().projectile_speed * ShipState.TICK_DT
	if step_length <= 2.0 * drone.radius:
		return "test needs a shot that moves further than a drone is wide in one tick"
	# Shots sit at whole multiples of step_length behind the nose; the drone is
	# centred halfway between two of them, so no tick ends inside it.
	var centre_z: float = -15.5 * step_length
	var sim: Sim = _sim()
	sim.spawn_robot(drone, Vector3(0.0, 0.0, centre_z), Basis.IDENTITY)
	_step(sim, true)
	var hits: int = _count(sim, SimEvent.Kind.ROBOT_HIT)
	for i: int in 60:
		_step(sim, false)
		hits += _count(sim, SimEvent.Kind.ROBOT_HIT)
		for projectile: Projectile in sim.projectiles:
			if projectile.position.distance_to(sim.robots[0].position) <= drone.radius:
				return "test setup: a shot ended a tick inside the drone"
	if hits != 1:
		return "%d hits on a drone passed through between ticks, expected 1" % hits
	return ""


func test_one_shot_never_hits_two_robots() -> String:
	var drone: RobotDef = _drone()
	var sim: Sim = _sim()
	# Both spheres are entered on the same tick's segment; the farther one has
	# the lower index, so the nearer must win on distance, not index.
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -32.6), Basis.IDENTITY)
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -31.0), Basis.IDENTITY)
	sim.spawn_robot(drone, Vector3(0.0, 0.0, -50.0), Basis.IDENTITY)
	if _one_shot(sim, 60) != 1:
		return "one shot through three drones in a line did not hit exactly once"
	if sim.robots[1].hull == drone.hull:
		return "the nearest drone along the path was not the one hit"
	if sim.robots[0].hull != drone.hull or sim.robots[2].hull != drone.hull:
		return "a drone behind the one hit lost hull"
	if not sim.projectiles.is_empty():
		return "the shot was not removed by its hit"
	var tie: Sim = _sim()
	tie.spawn_robot(drone, Vector3(0.0, 0.0, -20.0), Basis.IDENTITY)
	tie.spawn_robot(drone, Vector3(0.0, 0.0, -20.0), Basis.IDENTITY)
	if _one_shot(tie, 60) != 1 or tie.robots[0].hull == drone.hull or tie.robots[1].hull != drone.hull:
		return "a tie between two drones did not go to the lower index"
	return ""


## Ship 1 fires a single killing shot; ship 0 lights its afterburner on the
## tick the shot lands. Returns that sim's events on the landing tick, or an
## empty array if the shot never landed.
func _killing_tick_events(hit_tick: int) -> Array[SimEvent]:
	var sim: Sim = _sim(2, 1)
	sim.set_start_pose(1, Vector3(3.0, 0.0, 0.0), Basis.IDENTITY)
	sim.spawn_robot(_drone(), Vector3(3.0, 0.0, -10.5), Basis.IDENTITY)
	sim.robots[0].hull = _cannon().damage
	for i: int in 30:
		var inputs: Array[ShipInput] = [_input(false, i == hit_tick), _input(i == 0)]
		sim.step(inputs)
		if _count(sim, SimEvent.Kind.ROBOT_HIT) > 0:
			if not sim.robots.is_empty():
				return []
			return sim.last_events
	return []


func test_events_follow_ship_events_in_order() -> String:
	# First pass finds the landing tick without afterburner (-1 never matches).
	var dry: Sim = _sim(2, 1)
	dry.set_start_pose(1, Vector3(3.0, 0.0, 0.0), Basis.IDENTITY)
	dry.spawn_robot(_drone(), Vector3(3.0, 0.0, -10.5), Basis.IDENTITY)
	var hit_tick: int = -1
	for i: int in 30:
		var inputs: Array[ShipInput] = [_input(false), _input(i == 0)]
		dry.step(inputs)
		if _count(dry, SimEvent.Kind.ROBOT_HIT) > 0:
			hit_tick = i
			break
	if hit_tick < 1:
		return "test setup: the shot did not land after the firing tick"
	var events: Array[SimEvent] = _killing_tick_events(hit_tick)
	if events.size() != 3:
		return "expected 3 events on the killing tick with the robot removed, got %s" % [events]
	var forward: Vector3 = Vector3(0.0, 0.0, -1.0)
	if not events[0].equals(SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, 0)):
		return "first event %s, expected ship 0's AFTERBURNER_STARTED" % events[0]
	if not events[1].equals(SimEvent.new(SimEvent.Kind.ROBOT_HIT, 1, _cannon().damage, forward)):
		return "second event %s, expected ROBOT_HIT by ship 1" % events[1]
	if not events[2].equals(SimEvent.new(SimEvent.Kind.ROBOT_DESTROYED, 1)):
		return "third event %s, expected ROBOT_DESTROYED by ship 1" % events[2]
	return ""


func test_same_inputs_give_same_hashes_with_hits() -> String:
	var a: Sim = _sim()
	var b: Sim = _sim()
	for sim: Sim in [a, b]:
		sim.spawn_robot(_drone(), Vector3(0.0, 0.0, -25.0), Basis.IDENTITY)
		sim.spawn_robot(_drone(), Vector3(0.5, 0.3, -40.0), Basis.IDENTITY)
	for i: int in 240:
		_step(a, true)
		_step(b, true)
		if a.state_hash() != b.state_hash():
			return "hashes differ at tick %d" % a.tick
	if a.robots.size() == 2:
		return "test setup: no drone was destroyed"
	return ""


func test_no_robots_hashes_exactly_as_before() -> String:
	var sim: Sim = Sim.new(11, 1, BoxBounds.new(Vector3(-10.0, -10.0, -200.0), Vector3(10.0, 10.0, 10.0)))
	sim.ships[0].primary_slots[0] = _cannon()
	var input: ShipInput = ShipInput.new(
		Vector3i(300, -200, -1000), Vector3i(100, -150, 50), false, false, true)
	for i: int in 100:
		var inputs: Array[ShipInput] = [input]
		sim.step(inputs)
	if sim.projectiles.is_empty():
		return "the reference flight should leave projectiles in flight"
	if sim.state_hash() != REFERENCE_HASH:
		return "hash %d differs from %d recorded on main" % [sim.state_hash(), REFERENCE_HASH]
	return ""
