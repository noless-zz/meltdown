extends RefCounted

## Debris never closes the last route to the exit (#397, RUN-4, RUN-3, ARC-1,
## ARC-2): an entry that would seal a live ship's only way out is held back,
## reported, joins the hash, and replays the same.

const PULSE: String = "res://data/weapons/pulse_cannon.json"
const SHIP_RADIUS: float = 1.0


## A room (box 0, z -10..0) with the start, and one tunnel (box 1, 4 m square,
## z -70..-8) leading off it. Their only opening spans x -2..2, y -2..2,
## z -10..-8, centred on (0, 0, -9).
func _tunnel_boxes() -> Array:
	var mins: Array[Vector3i] = [Vector3i(-5000, -5000, -10000), Vector3i(-2000, -2000, -70000)]
	var maxs: Array[Vector3i] = [Vector3i(5000, 5000, 0), Vector3i(2000, 2000, -8000)]
	return [mins, maxs]


## Flies down the tunnel, shoots the reactor at its end, then flies back to the
## start. The entry in the opening falls due a moment after the reactor dies,
## with the ship deep in the tunnel.
func _tunnel_replay() -> Replay:
	var replay: Replay = Replay.new(397, 1)
	var boxes: Array = _tunnel_boxes()
	replay.set_boxes(boxes[0], boxes[1])
	replay.set_start_pose(0, Vector3(0, 0, -2), Vector3(0, 0, -1))
	replay.reactor = ReactorState.parse_json('{"position": [0, 0, -66], "radius": 2,'
		+ ' "hull": 8, "meltdown_seconds": 60, "exit_radius": 1}')
	replay.debris = MeltdownDebris.parse_json('[{"position": [0, 0, -9], "radius": 1.5,'
		+ ' "after_seconds": 0.1}]')
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	replay.loadout = loadout
	for i: int in 90:
		replay.add_tick([ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO)])
	var shoot: ShipInput = ShipInput.from_floats(Vector3(0, 0, 1), Vector3.ZERO)
	shoot.fire_primary = true
	for i: int in 10:
		replay.add_tick([shoot])
	for i: int in 600:
		replay.add_tick([ShipInput.from_floats(Vector3(0, 0, 1), Vector3.ZERO)])
	return replay


## The ring from `test_known_route.gd`: a near room (box 0, z -4..0) with the
## start, a far room (box 3, z -23..-19), and a left (box 1) and a right (box 2)
## corridor between them. The left corridor meets the far room in an opening
## centred on (-8, 0, -20), the right one in one centred on (8, 0, -20).
func _ring() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-10, -2, -4), Vector3(10, 2, 0)),
		BoxBounds.new(Vector3(-10, -2, -21), Vector3(-6, 2, -2)),
		BoxBounds.new(Vector3(6, -2, -21), Vector3(10, 2, -2)),
		BoxBounds.new(Vector3(-10, -2, -23), Vector3(10, 2, -19))]
	return BoxUnion.new(boxes)


## One tick in, on the ring: the start (and exit) at (0, 0, -1), the ship parked
## in the far room and the reactor already dead, with `debris_text`.
func _ring_sim(debris_text: String) -> Sim:
	var sim: Sim = Sim.new(397, 1)
	sim.set_walls(_ring())
	sim.set_start_pose(0, Vector3(0, 0, -1), Basis())
	sim.set_reactor(ReactorState.parse_json('{"position": [0, 0, -21], "radius": 0.5,'
		+ ' "hull": 1, "meltdown_seconds": 60, "exit_radius": 1}'))
	sim.set_debris(MeltdownDebris.parse_json(debris_text))
	sim.step(_idle())
	sim.ships[0].position = Vector3(0, 0, -21)
	sim.reactor.apply_damage(1.0)
	return sim


func _idle() -> Array[ShipInput]:
	return [ShipInput.new()]


## Steps `sim` `ticks` times and returns every DEBRIS_HELD event on the way.
func _held(sim: Sim, ticks: int) -> Array[SimEvent]:
	var held: Array[SimEvent] = []
	for i: int in ticks:
		sim.step(_idle())
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.DEBRIS_HELD:
				held.append(event)
	return held


func _all_boxes(walls: BoxUnion) -> Array[int]:
	var all: Array[int] = []
	for index: int in walls.boxes.size():
		all.append(index)
	return all


func _route(sim: Sim) -> KnownRoute:
	return KnownRoute.find(sim.walls, _all_boxes(sim.walls), sim.ships[0].position,
		sim.start_positions[0], sim.debris, SHIP_RADIUS)


func test_an_entry_sealing_the_only_tunnel_is_skipped_and_the_ship_escapes() -> String:
	var replay: Replay = _tunnel_replay()
	var sim: Sim = replay.run()
	if sim == null:
		return "the replay did not run: %s" % replay.run_error
	if not sim.reactor.destroyed:
		return "the reactor survived"
	if not sim.debris.is_skipped(0) or sim.debris.is_solid(0):
		return "the entry in the only opening was let fall"
	if not sim.ships[0].escaped:
		return "the ship did not escape; it ended at %s" % sim.ships[0].position
	# Solid, the entry would have sealed the tunnel: the guard is what kept it open.
	var sealed: MeltdownDebris = sim.debris.fresh_copy()
	sealed.elapsed_ticks = 60
	var route: KnownRoute = KnownRoute.find(sim.walls, _all_boxes(sim.walls), Vector3(0, 0, -40),
		sim.start_positions[0], sealed, SHIP_RADIUS)
	if route.length_mm != EscapePath.UNREACHABLE:
		return "the entry would not have sealed the tunnel, the test proves nothing"
	# One held event, for this ship and this entry, on the tick it fell due.
	var held: Array[SimEvent] = []
	var stepped: Sim = _step_replay(replay, held)
	if held.size() != 1:
		return "%d DEBRIS_HELD events, expected 1" % held.size()
	var event: SimEvent = held[0]
	if event.ship != 0 or event.magnitude != 0.0 or event.vector != Vector3(0, 0, -9):
		return "event %s" % event
	if stepped.state_hash() != sim.state_hash():
		return "stepping the replay by hand ends elsewhere"
	return ""


## Runs `replay` tick by tick as `Replay.run` does, collecting DEBRIS_HELD events.
func _step_replay(replay: Replay, held: Array[SimEvent]) -> Sim:
	var copy: Replay = Replay.from_text(replay.to_text())
	var frames: Array[Array] = copy.frames
	copy.frames = []
	var sim: Sim = copy.run()
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.DEBRIS_HELD:
				held.append(event)
	return sim


func test_with_a_loop_the_entry_falls_and_the_route_goes_round() -> String:
	var sim: Sim = _ring_sim('[{"position": [-8, 0, -20], "radius": 2, "after_seconds": 0.05}]')
	var held: Array[SimEvent] = _held(sim, 10)
	if not held.is_empty():
		return "held %s although the right corridor stays open" % held[0]
	if not sim.debris.is_solid(0):
		return "the entry did not fall"
	var route: KnownRoute = _route(sim)
	if route.length_mm == EscapePath.UNREACHABLE:
		return "no route left"
	if route.blocked_openings.is_empty():
		return "the entry blocks no opening, the test proves nothing"
	for point: Vector3i in route.points_mm:
		if point.x < -5000:
			return "the route still runs left: %s" % route.points_mm
	return ""


func test_of_two_entries_that_together_seal_the_ring_the_second_is_skipped() -> String:
	var left: String = '{"position": [-8, 0, -20], "radius": 2, "after_seconds": %s}'
	var right: String = '{"position": [8, 0, -20], "radius": 2, "after_seconds": %s}'
	# Falling on different ticks, and on the same tick (then file order decides).
	for times: Array in [["0.05", "0.1"], ["0.05", "0.05"]]:
		var sim: Sim = _ring_sim("[%s, %s]" % [left % times[0], right % times[1]])
		var held: Array[SimEvent] = _held(sim, 12)
		if not sim.debris.is_solid(0) or sim.debris.is_solid(1) or not sim.debris.is_skipped(1):
			return "%s: first solid %s, second solid %s" % [times, sim.debris.is_solid(0),
				sim.debris.is_solid(1)]
		if held.size() != 1 or held[0].magnitude != 1.0 or held[0].vector != Vector3(8, 0, -20):
			return "%s: held %s" % [times, held]
		if _route(sim).length_mm == EscapePath.UNREACHABLE:
			return "%s: the ship has no route left" % times
		if sim.debris.state_hash() == hash(["debris", sim.debris.elapsed_ticks]):
			return "%s: the skipped entry did not join the hash" % times
	return ""


func test_dead_and_escaped_ships_do_not_hold_debris_back() -> String:
	for escaped: bool in [false, true]:
		var sim: Sim = _ring_sim('[{"position": [-8, 0, -20], "radius": 2, "after_seconds": 0.05},'
			+ ' {"position": [8, 0, -20], "radius": 2, "after_seconds": 0.05}]')
		if escaped:
			sim.ships[0].escaped = true
		else:
			sim.ships[0].hull = 0.0
		if not _held(sim, 10).is_empty() or not sim.debris.is_solid(1):
			return "debris was held back for a%s ship" % (" escaped" if escaped else " destroyed")
	return ""


func test_replaying_the_run_gives_the_same_hash() -> String:
	var replay: Replay = _tunnel_replay()
	var first: Sim = replay.run()
	if first == null:
		return replay.run_error
	replay.expected_hash = first.state_hash()
	var read: Replay = Replay.from_text(replay.to_text())
	if read.error != "":
		return read.error
	var again: Sim = read.run()
	if again == null or again.state_hash() != read.expected_hash:
		return "the replay read back from text ends elsewhere"
	if not again.debris.is_skipped(0) or not again.ships[0].escaped:
		return "the replayed run did not hold the entry back"
	return ""
