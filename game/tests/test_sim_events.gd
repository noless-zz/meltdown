extends RefCounted

## Per-tick simulation events (PLT-6, FLT-2, FLT-3): `SimEvent` and
## `Sim.last_events`.

const FORWARD_Q: Vector3i = Vector3i(0, 0, -1000)


func _input(afterburner: bool, thrust_q: Vector3i = FORWARD_Q) -> Array[ShipInput]:
	var inputs: Array[ShipInput] = [ShipInput.new(thrust_q, Vector3i.ZERO, afterburner)]
	return inputs


## A box 10 m wide and high whose far wall is 40 m ahead of the start point.
func _box() -> BoxBounds:
	return BoxBounds.new(Vector3(-5.0, -5.0, -40.0), Vector3(5.0, 5.0, 5.0))


func _kinds(events: Array[SimEvent]) -> Array[int]:
	var kinds: Array[int] = []
	for event: SimEvent in events:
		kinds.append(event.kind)
	return kinds


## Steps `sim` with `inputs` and returns the tick numbers (0-based, counted
## from the first call) on which an event of `kind` was reported.
func _ticks_with(sim: Sim, kind: SimEvent.Kind, inputs: Array) -> Array[int]:
	var found: Array[int] = []
	for i: int in inputs.size():
		var tick_inputs: Array[ShipInput] = inputs[i]
		sim.step(tick_inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == kind:
				found.append(i)
	return found


func _repeat(input: Array[ShipInput], count: int) -> Array:
	var list: Array = []
	for i: int in count:
		list.append(input)
	return list


func test_no_events_without_a_change() -> String:
	var sim: Sim = Sim.new(1, 1)
	for i: int in 300:
		sim.step(_input(false))
		if not sim.last_events.is_empty():
			return "tick %d reported %s while only flying forward" % [i, sim.last_events]
	return ""


func test_afterburner_started_and_stopped_once_per_transition() -> String:
	var sim: Sim = Sim.new(1, 1)
	# 10 ticks off, 30 held, 20 off, 10 held: well under the 4 s pool.
	var inputs: Array = (_repeat(_input(false), 10) + _repeat(_input(true), 30)
		+ _repeat(_input(false), 20) + _repeat(_input(true), 10))
	var started: Array[int] = _ticks_with(sim, SimEvent.Kind.AFTERBURNER_STARTED, inputs)
	if started != [10, 60]:
		return "afterburner started on ticks %s, expected [10, 60]" % [started]
	sim = Sim.new(1, 1)
	var stopped: Array[int] = _ticks_with(sim, SimEvent.Kind.AFTERBURNER_STOPPED, inputs)
	if stopped != [40]:
		return "afterburner stopped on ticks %s, expected [40]" % [stopped]
	var event: SimEvent = SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, 0)
	if event.magnitude != 0.0 or event.vector != Vector3.ZERO:
		return "an afterburner event carries a magnitude or vector"
	return ""


func test_energy_depleted_once_then_stopped_next_tick() -> String:
	var sim: Sim = Sim.new(1, 1)
	var ship: ShipState = sim.ships[0]
	var depleted_at: int = -1
	var stopped_at: int = -1
	var depleted_count: int = 0
	var restarted_at: int = -1
	# 4 s of boost empties the pool and the restart level is reached 2 s later.
	# The 1 s of boost that buys then empties the pool again, so only
	# depletions before the restart count.
	for i: int in 480:
		var energy_before: float = ship.energy
		sim.step(_input(true))
		for event: SimEvent in sim.last_events:
			match event.kind:
				SimEvent.Kind.ENERGY_DEPLETED:
					if restarted_at >= 0:
						continue
					depleted_count += 1
					depleted_at = i
					if energy_before <= 0.0 or ship.energy > 0.0:
						return "depleted reported on tick %d, energy %f -> %f" % [
							i, energy_before, ship.energy]
				SimEvent.Kind.AFTERBURNER_STOPPED:
					if stopped_at < 0:
						stopped_at = i
				SimEvent.Kind.AFTERBURNER_STARTED:
					if i > 0 and restarted_at < 0:
						restarted_at = i
	if depleted_count != 1:
		return "energy depleted reported %d times before the restart, expected once" % (
			depleted_count)
	if stopped_at != depleted_at + 1:
		return "stopped on tick %d, expected the tick after depletion (%d)" % [
			stopped_at, depleted_at + 1]
	if restarted_at <= stopped_at:
		return "afterburner did not restart after the lock (restart tick %d)" % restarted_at
	return ""


func test_wall_impact_reports_speed_and_normal_once() -> String:
	var sim: Sim = Sim.new(1, 1, _box())
	var ship: ShipState = sim.ships[0]
	var hits: Array[int] = []
	for i: int in 240:
		var speed_before: float = ship.velocity.length()
		sim.step(_input(false))
		for event: SimEvent in sim.last_events:
			if event.kind != SimEvent.Kind.WALL_IMPACT:
				continue
			hits.append(i)
			if hits.size() > 1:
				continue
			if event.ship != 0:
				return "impact reported for ship %d" % event.ship
			if not event.vector.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
				return "far wall normal %s, expected (0, 0, 1)" % event.vector
			if event.magnitude < 0.9 * speed_before or event.magnitude > ship.max_speed + 0.01:
				return "impact speed %f with %f before the tick" % [event.magnitude, speed_before]
			if ship.velocity.z <= 0.0:
				return "impact reported but the ship was not bounced: %s" % ship.velocity
	if hits.is_empty():
		return "no wall impact in 4 s of full thrust at a wall 40 m away"
	if hits[0] < 60:
		return "first impact on tick %d, before the ship could reach the wall" % hits[0]
	if hits.size() > 1 and hits[1] == hits[0] + 1:
		return "one hit reported on two consecutive ticks (%d, %d)" % [hits[0], hits[1]]
	return ""


func test_corner_impact_is_one_event_with_unit_normal() -> String:
	var sim: Sim = Sim.new(1, 1, _box())
	var ship: ShipState = sim.ships[0]
	ship.position = Vector3(-4.0, -4.0, -38.9)
	ship.velocity = Vector3(-10.0, -10.0, -10.0)
	sim.step(_input(false, Vector3i.ZERO))
	var impacts: Array[SimEvent] = []
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.WALL_IMPACT:
			impacts.append(event)
	if impacts.size() != 1:
		return "corner hit gave %d impact events, expected 1" % impacts.size()
	var normal: Vector3 = impacts[0].vector
	if not is_equal_approx(normal.length(), 1.0):
		return "corner normal %s is not a unit vector" % normal
	if normal.x <= 0.0 or normal.y <= 0.0 or normal.z <= 0.0:
		return "corner normal %s does not point back into the box" % normal
	return ""


func test_no_wall_impact_while_flying_inside() -> String:
	var sim: Sim = Sim.new(1, 1, _box())
	for i: int in 50:
		sim.step(_input(false))
		if SimEvent.Kind.WALL_IMPACT in _kinds(sim.last_events):
			return "wall impact on tick %d, ship at %s" % [i, sim.ships[0].position]
	return ""


func test_events_belong_to_one_tick_only() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.step(_input(true))
	if _kinds(sim.last_events) != [SimEvent.Kind.AFTERBURNER_STARTED]:
		return "first boosted tick reported %s" % [sim.last_events]
	sim.step(_input(true))
	if not sim.last_events.is_empty():
		return "second boosted tick still reported %s" % [sim.last_events]
	sim.step(_input(false))
	var empty: Array[ShipInput] = []
	if sim.step(empty):
		return "a step with the wrong input count was accepted"
	if not sim.last_events.is_empty():
		return "a refused step kept the previous tick's events"
	return ""


func test_events_are_not_part_of_the_hash() -> String:
	var a: Sim = Sim.new(5, 1)
	var b: Sim = Sim.new(5, 1)
	a.step(_input(true))
	b.step(_input(true))
	b.last_events = []
	if a.state_hash() != b.state_hash():
		return "clearing last_events changed the hash"
	b.ships[0].afterburner_active = false
	if a.state_hash() != b.state_hash():
		return "the derived afterburner_active flag changed the hash"
	return ""


func test_same_inputs_give_same_hashes_and_events() -> String:
	var sims: Array[Sim] = [Sim.new(9, 2, _box()), Sim.new(9, 2, _box())]
	var total: int = 0
	for tick: int in 900:
		var inputs: Array[ShipInput] = [
			ShipInput.new(FORWARD_Q, Vector3i(0, 400, 0), tick % 120 < 70),
			ShipInput.new(Vector3i(600, 0, -1000), Vector3i(200, 0, 0), tick > 50),
		]
		for sim: Sim in sims:
			sim.step(inputs)
		var first: Array[SimEvent] = sims[0].last_events
		var second: Array[SimEvent] = sims[1].last_events
		if first.size() != second.size():
			return "tick %d: %s vs %s" % [tick, first, second]
		for i: int in first.size():
			if not first[i].equals(second[i]):
				return "tick %d: event %s vs %s" % [tick, first[i], second[i]]
		total += first.size()
	if sims[0].state_hash() != sims[1].state_hash():
		return "identical inputs produced different hashes"
	if total < 4:
		return "only %d events in 15 s; the comparison proved little" % total
	return ""
