extends RefCounted

## Fire is passable (#480, RUN-4, RUN-3): `DebrisRouteGuard` never holds it back
## and `KnownRoute` never counts it as a closed opening.


func _idle() -> Array[ShipInput]:
	return [ShipInput.new()]


## A room (z -10..0) with the start at (0, 0, -2) and one 4 m tunnel off it
## (z -70..-8); the ship parked deep in the tunnel and the reactor dead, with one
## entry of `kind` filling the only opening, centred on (0, 0, -9).
func _tunnel_sim(kind: String) -> Sim:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-5, -5, -10), Vector3(5, 5, 0)),
		BoxBounds.new(Vector3(-2, -2, -70), Vector3(2, 2, -8))]
	var sim: Sim = Sim.new(480, 1)
	sim.set_walls(BoxUnion.new(boxes))
	sim.set_start_pose(0, Vector3(0, 0, -2), Basis())
	sim.set_reactor(ReactorState.parse_json('{"position": [0, 0, -66], "radius": 0.5,'
		+ ' "hull": 1, "meltdown_seconds": 60, "exit_radius": 1}'))
	var extra: String = ', "kind": "fire", "damage_per_second": 5' if kind == "fire" else ""
	sim.set_debris(MeltdownDebris.parse_json('[{"position": [0, 0, -9], "radius": 1.5,'
		+ ' "after_seconds": 0.1%s}]' % extra))
	sim.step(_idle())
	sim.ships[0].position = Vector3(0, 0, -40)
	sim.reactor.apply_damage(1.0)
	return sim


## Fire in the only opening is not held back, falls, and leaves the route open
## for the guard and the map; a solid entry in its place is held.
func test_fire_in_the_only_opening_falls_and_the_route_stays_open() -> String:
	var held: Dictionary = {}
	for kind: String in ["solid", "fire"]:
		var sim: Sim = _tunnel_sim(kind)
		held[kind] = false
		for i: int in 20:
			sim.step(_idle())
			for event: SimEvent in sim.last_events:
				held[kind] = held[kind] or event.kind == SimEvent.Kind.DEBRIS_HELD
		if kind == "solid":
			if not held[kind] or not sim.debris.is_skipped(0):
				return "a solid entry sealing the tunnel was let fall, the test proves nothing"
			continue
		if held[kind] or sim.debris.is_skipped(0) or not sim.debris.is_burning(0):
			return "the fire was held back"
		var explored: Array[int] = [0, 1]
		var route: KnownRoute = KnownRoute.find(sim.walls, explored, sim.ships[0].position,
			sim.start_positions[0], sim.debris, 1.0)
		if route.length_mm == EscapePath.UNREACHABLE:
			return "the map route counts the fire as a closed opening"
		var lit: MeltdownDebris = sim.debris.fresh_copy()
		lit.elapsed_ticks = 60
		if not lit.is_burning(0) or lit.is_solid(0):
			return "a fresh copy forgot the entry is fire"
	return ""
