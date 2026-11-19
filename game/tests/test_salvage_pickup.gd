extends RefCounted

## Salvage pickup: flying through a floating part takes it into the hold
## (SLV-1, CMB-1, ARC-2, #245).

const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const DRONE_AT: Vector3 = Vector3(0.0, 0.0, -30.0)
## Full forward thrust, in the thousandths `ShipInput` stores.
const FORWARD: Vector3i = Vector3i(0, 0, -1000)


## A sim whose only ship carries the pulse cannon and faces -Z, with an
## unarmed drone ahead of it.
func _sim_with_drone() -> Sim:
	var sim: Sim = Sim.new(9, 1)
	sim.ships[0].primary_slots[0] = WeaponDef.parse_json(
		FileAccess.get_file_as_string(PULSE_CANNON))
	sim.spawn_robot(RobotDef.parse_json(FileAccess.get_file_as_string(DRONE)),
		DRONE_AT, Basis.IDENTITY)
	return sim


func _step(sim: Sim, thrust: Vector3i = Vector3i.ZERO, fire: bool = false) -> void:
	var inputs: Array[ShipInput] = []
	for i: int in sim.ships.size():
		inputs.append(ShipInput.new(thrust, Vector3i.ZERO, false, false, fire))
	sim.step(inputs)


func _holds_cannon(ship: ShipState) -> bool:
	return ship.hold.size() == 1 and ship.hold[0] == "pulse_cannon"


func _events(sim: Sim, kind: SimEvent.Kind) -> Array[SimEvent]:
	var found: Array[SimEvent] = []
	for event: SimEvent in sim.last_events:
		if event.kind == kind:
			found.append(event)
	return found


## Shoots the drone until it is gone, then flies forward until the item is
## taken or `ticks` pass. Returns the SALVAGE_COLLECTED events seen.
func _kill_and_fly_through(sim: Sim, ticks: int) -> Array[SimEvent]:
	for i: int in 300:
		_step(sim, Vector3i.ZERO, true)
		if sim.robots.is_empty():
			break
	var collected: Array[SimEvent] = []
	for i: int in ticks:
		_step(sim, FORWARD)
		collected.append_array(_events(sim, SimEvent.Kind.SALVAGE_COLLECTED))
		if sim.salvage.is_empty():
			break
	return collected


func test_flying_through_a_dropped_cannon_takes_it() -> String:
	var sim: Sim = _sim_with_drone()
	var collected: Array[SimEvent] = _kill_and_fly_through(sim, 600)
	if not sim.robots.is_empty():
		return "drone survived 300 ticks of fire"
	if not sim.salvage.is_empty():
		return "item still floating after flying at it for 10 s"
	if not _holds_cannon(sim.ships[0]):
		return "hold is %s, expected [pulse_cannon]" % [sim.ships[0].hold]
	if collected.size() != 1:
		return "%d SALVAGE_COLLECTED events, expected 1" % collected.size()
	if not collected[0].equals(SimEvent.new(SimEvent.Kind.SALVAGE_COLLECTED, 0, 0.0, DRONE_AT)):
		return "event %s, expected ship 0 taking item 0 at %s" % [collected[0], DRONE_AT]
	var reach: float = sim.ships[0].radius + sim.salvage_rules.pickup_reach
	if sim.ships[0].position.distance_to(DRONE_AT) > reach + 1.0:
		return "taken from %f m away" % sim.ships[0].position.distance_to(DRONE_AT)
	return ""


func test_fast_pass_between_ticks_still_takes_it() -> String:
	var sim: Sim = Sim.new(1, 1)
	var at: Vector3 = Vector3(0.5, 0.0, -5.0)
	sim.salvage.append(SalvageItem.new("pulse_cannon", at))
	# About 10 m per tick: the ship starts 5 m short of the item and ends the
	# tick 5 m past it, never within reach at a tick boundary.
	sim.ships[0].velocity = Vector3(0.0, 0.0, -600.0)
	var reach: float = sim.ships[0].radius + sim.salvage_rules.pickup_reach
	_step(sim)
	if sim.ships[0].position.distance_to(at) <= reach:
		return "test is wrong: the tick ended within reach"
	if not sim.salvage.is_empty() or not _holds_cannon(sim.ships[0]):
		return "a pass through the item between ticks did not take it"
	return ""


func test_full_hold_leaves_the_item() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.ships[0].hold.append("pulse_cannon")
	sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3(0.0, 0.0, -3.0)))
	for i: int in 120:
		_step(sim, FORWARD)
	if sim.salvage.size() != 1:
		return "a full hold took the item"
	if sim.ships[0].hold.size() != ShipState.HOLD_CAPACITY:
		return "hold grew past capacity: %s" % [sim.ships[0].hold]
	if sim.salvage[0].position != Vector3(0.0, 0.0, -3.0):
		return "the item left behind moved"
	return ""


func test_tie_goes_to_the_lower_ship_index() -> String:
	var sim: Sim = Sim.new(1, 2)
	sim.set_start_pose(0, Vector3(-3.2, 0.0, 0.0), Basis.IDENTITY)
	sim.set_start_pose(1, Vector3(3.2, 0.0, 0.0), Basis.IDENTITY)
	sim.ships[0].velocity = Vector3(60.0, 0.0, 0.0)
	sim.ships[1].velocity = Vector3(-60.0, 0.0, 0.0)
	sim.salvage.append(SalvageItem.new("pulse_cannon", Vector3.ZERO))
	_step(sim)
	var reach: float = sim.ships[0].radius + sim.salvage_rules.pickup_reach
	for ship: ShipState in sim.ships:
		if ship.position.length() > reach:
			return "test is wrong: a ship did not reach the item on the first tick"
	if not _holds_cannon(sim.ships[0]) or not sim.ships[1].hold.is_empty():
		return "holds %s and %s, expected ship 0 to get it" % [sim.ships[0].hold, sim.ships[1].hold]
	var collected: Array[SimEvent] = _events(sim, SimEvent.Kind.SALVAGE_COLLECTED)
	if collected.size() != 1 or collected[0].ship != 0:
		return "events %s, expected one for ship 0" % [collected]
	if not sim.salvage.is_empty():
		return "item still floating"
	return ""


func test_held_part_changes_the_hash() -> String:
	var ship: ShipState = ShipState.new()
	var empty: int = ship.state_hash()
	ship.hold.append("pulse_cannon")
	if ship.state_hash() == empty:
		return "a held part does not change the ship's hash"
	var other: ShipState = ShipState.new()
	other.hold.append("needle_gun")
	if other.state_hash() == ship.state_hash():
		return "different held parts hash alike"
	return ""


func test_pickup_is_deterministic_over_600_ticks() -> String:
	var a: Sim = _sim_with_drone()
	var b: Sim = _sim_with_drone()
	for i: int in 600:
		var fire: bool = i < 240
		var thrust: Vector3i = FORWARD if i >= 240 else Vector3i.ZERO
		_step(a, thrust, fire)
		_step(b, thrust, fire)
		if a.state_hash() != b.state_hash():
			return "hashes differ at tick %d" % a.tick
		if a.last_events.size() != b.last_events.size():
			return "event counts differ at tick %d" % a.tick
		for e: int in a.last_events.size():
			if not a.last_events[e].equals(b.last_events[e]):
				return "events differ at tick %d" % a.tick
	if not _holds_cannon(a.ships[0]) or not a.salvage.is_empty():
		return "the run did not take the cannon: hold %s" % [a.ships[0].hold]
	return ""
