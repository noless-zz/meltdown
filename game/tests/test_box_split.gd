extends RefCounted

## A box entry that closes a box's whole cross-section splits that box for the
## route (#868, RUN-4, MAP-2, ARC-1, ARC-2): no route crosses it, the map marks
## it, the guard holds it back when it would close the last way out, and with
## nothing split every route is what it was.

const G2_LEVEL: String = "res://data/levels/g2_level.json"
const SHIP_RADIUS: float = 1.0
const RADIUS_MM: int = 1000
## #514's probe: a slab across the whole 4 m tunnel at z = -15.
const SLAB: String = '{"position": [0, 0, -15], "size": [4, 4, 0.5], "after_seconds": 0.05}'
## Covers x -2..-0.5 only, leaving 2.5 m beside it, more than a ship's diameter.
const PART_SLAB: String = '{"position": [-1.25, 0, -15], "size": [1.5, 4, 0.5], "after_seconds": 0.05}'
## A sphere wider than the tunnel, touching no opening.
const BIG_SPHERE: String = '{"position": [0, 0, -15], "radius": 3, "after_seconds": 0.05}'
const DEEP: Vector3 = Vector3(0, 0, -40)
const EXIT: Vector3 = Vector3(0, 0, -2)


## A room (box 0, z -10..0) and a 4 m tunnel (box 1, z -70..-8) off it, as in
## `test_debris_route_guard.gd`. With `with_loop` a side corridor joins the tunnel
## beyond z -15 back to the room: box 2 (x -1..10, z -30..-26) and box 3
## (x 6..10, z -30..-8). The room is 20 m wide so box 3 meets it.
func _tunnel(with_loop: bool = false) -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-10, -5, -10), Vector3(10, 5, 0)),
		BoxBounds.new(Vector3(-2, -2, -70), Vector3(2, 2, -8))]
	if with_loop:
		boxes.append(BoxBounds.new(Vector3(-1, -2, -30), Vector3(10, 2, -26)))
		boxes.append(BoxBounds.new(Vector3(6, -2, -30), Vector3(10, 2, -8)))
	return BoxUnion.new(boxes)


func _fallen(text: String) -> MeltdownDebris:
	var debris: MeltdownDebris = MeltdownDebris.parse_json("[" + text + "]")
	debris.elapsed_ticks = 60
	return debris


func _all(walls: BoxUnion) -> Array[int]:
	var all: Array[int] = []
	for index: int in walls.boxes.size():
		all.append(index)
	return all


func _route(walls: BoxUnion, from: Vector3, to: Vector3, debris: MeltdownDebris) -> KnownRoute:
	return KnownRoute.find(walls, _all(walls), from, to, debris, SHIP_RADIUS)


func test_the_probe_slab_splits_the_tunnel_where_it_lies() -> String:
	var walls: BoxUnion = _tunnel()
	var cuts: Array[Vector3i] = BoxSplit.splits(Vector3i(-2000, -2000, -70000),
		Vector3i(2000, 2000, -8000), _fallen(SLAB), RADIUS_MM)
	if cuts != [Vector3i(0, 2, -15000)]:
		return "splits %s, expected entry 0 across z at -15000" % [cuts]
	var clear: KnownRoute = _route(walls, DEEP, EXIT, null)
	if clear.length_mm != 38000:
		return "clear tunnel route %d, expected 38000" % clear.length_mm
	var route: KnownRoute = _route(walls, DEEP, EXIT, _fallen(SLAB))
	if route.length_mm != EscapePath.UNREACHABLE or not route.points_mm.is_empty():
		return "a route %s through the slab" % [route.points_mm]
	if not route.blocked_openings.is_empty() or route.blocked_splits != [Vector2i(1, 0)]:
		return "openings %s, splits %s" % [route.blocked_openings, route.blocked_splits]
	if route.blocked_centres_mm != [Vector3i(0, 0, -15000)]:
		return "marks at %s" % [route.blocked_centres_mm]
	return ""


func test_a_slab_that_leaves_a_ship_room_splits_nothing() -> String:
	var walls: BoxUnion = _tunnel()
	var clear: KnownRoute = _route(walls, DEEP, EXIT, null)
	var route: KnownRoute = _route(walls, DEEP, EXIT, _fallen(PART_SLAB))
	if not route.blocked_splits.is_empty() or not route.blocked_centres_mm.is_empty():
		return "2.5 m left clear, yet split: %s" % [route.blocked_splits]
	if route.length_mm != clear.length_mm or route.points_mm != clear.points_mm:
		return "route %s, expected %s" % [route.points_mm, clear.points_mm]
	return ""


func test_a_sphere_never_splits_a_box() -> String:
	var walls: BoxUnion = _tunnel()
	var debris: MeltdownDebris = _fallen(BIG_SPHERE)
	if not BoxSplit.splits(Vector3i(-2000, -2000, -70000), Vector3i(2000, 2000, -8000), debris,
			RADIUS_MM).is_empty():
		return "a sphere split the tunnel"
	var route: KnownRoute = _route(walls, DEEP, EXIT, debris)
	if route.length_mm != 38000 or not route.blocked_splits.is_empty():
		return "route %d, splits %s" % [route.length_mm, route.blocked_splits]
	return ""


func test_a_slab_not_yet_fallen_splits_nothing() -> String:
	var waiting: MeltdownDebris = MeltdownDebris.parse_json("[" + SLAB + "]")
	if _route(_tunnel(), DEEP, EXIT, waiting).length_mm != 38000:
		return "a slab still to fall closed the tunnel"
	return ""


func test_the_start_and_exit_inside_a_split_box_keep_their_own_side() -> String:
	var walls: BoxUnion = _tunnel()
	var slab: MeltdownDebris = _fallen(SLAB)
	var near: Vector3 = Vector3(0, 0, -12)
	if _route(walls, near, EXIT, slab).length_mm != _route(walls, near, EXIT, null).length_mm:
		return "the start on the room's side of the slab lost its route"
	var beyond: KnownRoute = _route(walls, Vector3(0, 0, -20), DEEP, slab)
	if beyond.length_mm != 20000:
		return "start and exit both beyond the slab: route %d, expected 20000" % beyond.length_mm
	if _route(walls, near, DEEP, slab).length_mm != EscapePath.UNREACHABLE:
		return "a route across the slab inside one box"
	if BoxSplit.part([Vector3i(0, 2, -15000)], Vector3i(0, 0, -12000)) \
			== BoxSplit.part([Vector3i(0, 2, -15000)], Vector3i(0, 0, -20000)):
		return "points either side of the split share a part"
	return ""


func test_with_a_loop_the_route_goes_round_the_slab() -> String:
	var walls: BoxUnion = _tunnel(true)
	var route: KnownRoute = _route(walls, DEEP, EXIT, _fallen(SLAB))
	if route.length_mm == EscapePath.UNREACHABLE:
		return "no route round the slab"
	var round_the_side: bool = false
	for point: Vector3i in route.points_mm:
		round_the_side = round_the_side or point.x > 5000
	if not round_the_side:
		return "the route %s does not go round" % [route.points_mm]
	if route.blocked_splits != [Vector2i(1, 0)]:
		return "splits %s" % [route.blocked_splits]
	return ""


func test_with_nothing_split_g2_routes_are_unchanged() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	if level.error != "":
		return level.error
	var walls: BoxUnion = level.union
	var exit: Vector3 = level.start_position()
	var from: Vector3 = level.reactor.position()
	# A small box entry beside the exit splits nothing.
	var small: MeltdownDebris = _fallen(('{"position": [%f, %f, %f], "size": [0.5, 0.5, 0.5],'
		% [exit.x + 1.0, exit.y, exit.z]) + ' "after_seconds": 0.05}')
	var plain: KnownRoute = _route(walls, from, exit, null)
	var with_small: KnownRoute = _route(walls, from, exit, small)
	if plain.length_mm == EscapePath.UNREACHABLE:
		return "no g2 route to compare"
	if with_small.points_mm != plain.points_mm or with_small.length_mm != plain.length_mm \
			or not with_small.blocked_splits.is_empty():
		return "a small entry changed the route"
	return ""


## One tick in: the reactor dead, the ship parked deep in the tunnel and the slab
## due three ticks into the meltdown.
func _guard_sim(with_loop: bool) -> Sim:
	var sim: Sim = Sim.new(868, 1)
	sim.set_walls(_tunnel(with_loop))
	sim.set_start_pose(0, EXIT, Basis())
	sim.set_reactor(ReactorState.parse_json('{"position": [0, 0, -66], "radius": 0.5,'
		+ ' "hull": 1, "meltdown_seconds": 60, "exit_radius": 1}'))
	sim.set_debris(MeltdownDebris.parse_json("[" + SLAB + "]"))
	sim.step([ShipInput.new()])
	sim.ships[0].position = DEEP
	sim.reactor.apply_damage(1.0)
	for i: int in 30:
		sim.ships[0].position = DEEP
		sim.step([ShipInput.new()])
	return sim


func test_the_guard_holds_back_a_slab_closing_the_last_way_out() -> String:
	var sim: Sim = _guard_sim(false)
	if not sim.reactor.destroyed:
		return "the reactor survived"
	if not sim.debris.is_skipped(0) or sim.debris.is_solid(0):
		return "the slab sealing the only tunnel fell"
	return ""


func test_the_guard_lets_the_slab_fall_when_a_loop_goes_round() -> String:
	var sim: Sim = _guard_sim(true)
	if sim.debris.is_skipped(0) or not sim.debris.is_solid(0):
		return "the slab was held though a loop goes round it"
	return ""


func test_a_split_with_all_the_box_on_one_side_is_not_marked() -> String:
	var cut: Vector3i = Vector3i(0, 2, -15000)
	if BoxSplit.separates(cut, [Vector3i(0, 0, -9000), Vector3i(0, 0, -12000)]):
		return "two points on the same side counted as separated"
	if not BoxSplit.separates(cut, [Vector3i(0, 0, -9000), Vector3i(0, 0, -40000)]):
		return "points either side not counted as separated"
	# The slab with nothing beyond it: no start or exit deep in the tunnel.
	var route: KnownRoute = _route(_tunnel(), Vector3(0, 0, -12), EXIT, _fallen(SLAB))
	if not route.blocked_splits.is_empty():
		return "a split with only the room's side in use marked %s" % [route.blocked_splits]
	return ""
