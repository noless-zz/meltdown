extends RefCounted

## Salvage drops: a destroyed robot leaves its part floating where it died
## (SLV-1, CMB-1, ARC-2, ARC-4, #243).

const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## Where the drone waits for the ship's shots, straight ahead of it.
const DRONE_AT: Vector3 = Vector3(0.0, 0.0, -30.0)


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))


## A sim whose only ship carries the pulse cannon and faces -Z, with one drone
## of type `def` ahead of it.
func _sim_with_drone(def: RobotDef) -> Sim:
	var sim: Sim = Sim.new(9, 1)
	sim.ships[0].primary_slots[0] = WeaponDef.parse_json(
		FileAccess.get_file_as_string(PULSE_CANNON))
	sim.spawn_robot(def, DRONE_AT, Basis.IDENTITY)
	return sim


func _step(sim: Sim, fire: bool) -> void:
	var inputs: Array[ShipInput] = [ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, fire)]
	sim.step(inputs)


func _events(sim: Sim, kind: SimEvent.Kind) -> Array[SimEvent]:
	var found: Array[SimEvent] = []
	for event: SimEvent in sim.last_events:
		if event.kind == kind:
			found.append(event)
	return found


## Fires until the robot is gone or 300 ticks pass. Returns the robot's
## position on the tick before it was removed.
func _kill(sim: Sim) -> Vector3:
	var last: Vector3 = sim.robots[0].position
	for i: int in 300:
		last = sim.robots[0].position
		_step(sim, true)
		if sim.robots.is_empty():
			break
	return last


func test_killing_a_drone_leaves_its_cannon_where_it_died() -> String:
	var sim: Sim = _sim_with_drone(_drone())
	var before: Vector3 = _kill(sim)
	if not sim.robots.is_empty():
		return "drone survived 300 ticks of fire"
	if sim.salvage.size() != 1:
		return "%d items after the kill, expected 1" % sim.salvage.size()
	var item: SalvageItem = sim.salvage[0]
	if item.part_id != "pulse_cannon":
		return "dropped part is '%s'" % item.part_id
	# A hovering drone at rest dies where it waited.
	if not item.position.is_equal_approx(before) or not item.position.is_equal_approx(DRONE_AT):
		return "item at %s, drone was at %s" % [item.position, before]
	var drops: Array[SimEvent] = _events(sim, SimEvent.Kind.SALVAGE_DROPPED)
	if drops.size() != 1:
		return "%d SALVAGE_DROPPED events on the kill tick" % drops.size()
	if drops[0].magnitude != 0.0 or drops[0].vector != item.position or drops[0].ship != 0:
		return "event %s does not name item 0 at %s by ship 0" % [drops[0], item.position]
	var last: SimEvent = sim.last_events[sim.last_events.size() - 1]
	if last.kind != SimEvent.Kind.SALVAGE_DROPPED:
		return "SALVAGE_DROPPED is not the tick's last event"
	var destroyed_at: int = -1
	for e: int in sim.last_events.size():
		if sim.last_events[e].kind == SimEvent.Kind.ROBOT_DESTROYED:
			destroyed_at = e
	if destroyed_at < 0:
		return "no ROBOT_DESTROYED on the kill tick"
	return ""


func test_dropped_item_stays_and_does_not_expire() -> String:
	var sim: Sim = _sim_with_drone(_drone())
	_kill(sim)
	var at: Vector3 = sim.salvage[0].position
	for i: int in 3600:
		_step(sim, false)
	if sim.salvage.size() != 1 or sim.salvage[0].position != at:
		return "item moved or vanished within a minute of resting"
	if not _events(sim, SimEvent.Kind.SALVAGE_DROPPED).is_empty():
		return "SALVAGE_DROPPED repeated after the kill tick"
	return ""


func test_item_thrown_at_a_wall_stays_inside_and_comes_to_rest() -> String:
	var bounds: BoxBounds = BoxBounds.new(Vector3(-5.0, -5.0, -5.0), Vector3(5.0, 5.0, 5.0))
	var sim: Sim = Sim.new(1, 1, bounds)
	sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3(3.0, 0.0, 0.0),
		Vector3(40.0, 0.0, -2.0)))
	for i: int in 600:
		_step(sim, false)
		if not bounds.holds(sim.salvage[0].position, SalvageItem.RADIUS - 0.0001):
			return "item left the walls at tick %d: %s" % [sim.tick, sim.salvage[0].position]
	var item: SalvageItem = sim.salvage[0]
	if not item.is_at_rest():
		return "item still moving at %s after 10 s" % item.velocity
	if not is_equal_approx(item.position.x, 5.0 - SalvageItem.RADIUS):
		return "item rests at x %f, not against the wall it was thrown at" % item.position.x
	return ""


func test_robot_without_salvage_drops_nothing() -> String:
	var bare: RobotDef = _drone()
	bare.salvage = ""
	var sim: Sim = _sim_with_drone(bare)
	_kill(sim)
	if not sim.robots.is_empty():
		return "drone survived 300 ticks of fire"
	if not sim.salvage.is_empty():
		return "a robot with no salvage dropped %d items" % sim.salvage.size()
	if not _events(sim, SimEvent.Kind.SALVAGE_DROPPED).is_empty():
		return "SALVAGE_DROPPED without an item"
	return ""


func test_salvage_changes_the_hash() -> String:
	var sim: Sim = Sim.new(1, 1)
	var without: int = sim.state_hash()
	sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3.ZERO))
	if sim.state_hash() == without:
		return "an item does not change the hash"
	var first: int = sim.state_hash()
	sim.salvage[0].position = Vector3(0.0, 0.0, 1.0)
	if sim.state_hash() == first:
		return "an item's position does not change the hash"
	return ""


func test_two_sims_with_kills_hash_the_same_every_tick() -> String:
	var a: Sim = _sim_with_drone(_drone())
	var b: Sim = _sim_with_drone(_drone())
	# A second drone off to the side, moving when it dies, so the drop has a
	# velocity and the items move.
	for sim: Sim in [a, b]:
		sim.spawn_robot(_drone(), Vector3(0.0, 0.0, -20.0), Basis.IDENTITY)
		sim.robots[1].velocity = Vector3(3.0, 1.0, 0.0)
	for i: int in 600:
		var fire: bool = i % 90 < 60
		_step(a, fire)
		_step(b, fire)
		if a.state_hash() != b.state_hash():
			return "hashes differ at tick %d" % a.tick
		if a.last_events.size() != b.last_events.size():
			return "event counts differ at tick %d" % a.tick
	if a.salvage.size() != 2:
		return "%d items after 600 ticks, expected both drones' cannons" % a.salvage.size()
	return ""
