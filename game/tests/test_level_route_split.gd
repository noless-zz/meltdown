extends RefCounted

## The bot's route goes round a cave-in that splits a tunnel (#870, RUN-4,
## CMB-3, ARC-2): a solid slab across a tunnel's whole cross-section blocks no
## opening, so `LevelRoute` splits the box with `BoxSplit`, as `KnownRoute` does.

const SHIP_RADIUS: float = 1.0
## A loop: a near room (box 0), a short left tunnel (box 1) straight to the far
## room (box 3), and a longer right way of two boxes (2, then 4). Every opening
## overlaps by at least `LevelDef.MIN_OVERLAP_M`.
const LOOP_LEVEL: String = """{
	"boxes": [
		{"min": [-12.0, -3.0, -6.0], "max": [12.0, 3.0, 0.0]},
		{"min": [-12.0, -3.0, -40.0], "max": [-6.0, 3.0, -4.0]},
		{"min": [6.0, -3.0, -24.0], "max": [12.0, 3.0, -4.0]},
		{"min": [-12.0, -3.0, -44.0], "max": [12.0, 3.0, -38.0]},
		{"min": [6.0, -3.0, -40.0], "max": [12.0, 3.0, -20.0]}
	],
	"start": {"position": [-9.0, 0.0, -2.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [0, 0, -42], "radius": 1, "hull": 40, "meltdown_seconds": 60},
	"debris": []
}"""
## Mid-tunnel slabs across the whole 6 m by 6 m cross-section, touching no
## opening: one in the left tunnel, one in the right.
const LEFT_SLAB: String = '{"position": [-9, 0, -22], "size": [6, 6, 1], "after_seconds": 0.05}'
const RIGHT_SLAB: String = '{"position": [9, 0, -12], "size": [6, 6, 1], "after_seconds": 0.05}'
const FROM: Vector3 = Vector3(-9.0, 0.0, -2.0)
const TO: Vector3 = Vector3(-9.0, 0.0, -42.0)


func _route() -> LevelRoute:
	var level: LevelDef = LevelDef.parse_json(LOOP_LEVEL)
	return LevelRoute.new(level)


## The entries of `entries` (JSON objects), all fallen.
static func _fallen(entries: Array[String]) -> MeltdownDebris:
	var debris: MeltdownDebris = MeltdownDebris.parse_json("[" + ", ".join(entries) + "]")
	for index: int in debris.size():
		debris.elapsed_ticks = maxi(debris.elapsed_ticks, debris.after_ticks[index])
	return debris


func test_the_level_loads_and_the_slab_blocks_no_opening() -> String:
	var level: LevelDef = LevelDef.parse_json(LOOP_LEVEL)
	if level.error != "":
		return level.error
	var route: LevelRoute = LevelRoute.new(level)
	route.close_blocked(_fallen([LEFT_SLAB]), SHIP_RADIUS)
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(1, 3), Vector2i(0, 2), Vector2i(2, 4), Vector2i(3, 4)]:
		if route.is_closed(pair.x, pair.y):
			return "opening %s was closed; the slab touches none" % pair
	return ""


func test_without_a_slab_the_route_takes_the_short_side() -> String:
	var route: LevelRoute = _route()
	if route.chain(FROM, TO, SHIP_RADIUS) != [0, 1, 3]:
		return "with no debris the chain is %s" % [route.chain(FROM, TO, SHIP_RADIUS)]
	route.close_blocked(_fallen([]), SHIP_RADIUS)
	if route.chain(FROM, TO, SHIP_RADIUS) != [0, 1, 3]:
		return "with empty debris the chain is %s" % [route.chain(FROM, TO, SHIP_RADIUS)]
	return ""


func test_a_slab_not_yet_fallen_changes_nothing() -> String:
	var route: LevelRoute = _route()
	route.close_blocked(MeltdownDebris.parse_json("[" + LEFT_SLAB + "]"), SHIP_RADIUS)
	if route.chain(FROM, TO, SHIP_RADIUS) != [0, 1, 3]:
		return "before the slab falls the chain is %s" % [route.chain(FROM, TO, SHIP_RADIUS)]
	return ""


func test_a_slab_on_the_short_side_sends_the_route_the_long_way() -> String:
	var route: LevelRoute = _route()
	route.close_blocked(_fallen([LEFT_SLAB]), SHIP_RADIUS)
	if route.chain(FROM, TO, SHIP_RADIUS) != [0, 2, 4, 3]:
		return "with the left slab down the chain is %s" % [route.chain(FROM, TO, SHIP_RADIUS)]
	var points: Array[Vector3] = route.waypoints(FROM, TO, SHIP_RADIUS)
	for point: Vector3 in points:
		if point.x < -5.0 and point.z < -6.0 and point.z > -38.0:
			return "a waypoint %s lies in the blocked tunnel" % point
	return ""


func test_a_slab_on_the_long_side_leaves_the_short_side() -> String:
	var route: LevelRoute = _route()
	route.close_blocked(_fallen([RIGHT_SLAB]), SHIP_RADIUS)
	if route.chain(FROM, TO, SHIP_RADIUS) != [0, 1, 3]:
		return "with the right slab down the chain is %s" % [route.chain(FROM, TO, SHIP_RADIUS)]
	return ""


func test_with_no_way_round_the_route_is_empty() -> String:
	var route: LevelRoute = _route()
	route.close_blocked(_fallen([LEFT_SLAB, RIGHT_SLAB]), SHIP_RADIUS)
	if not route.chain(FROM, TO, SHIP_RADIUS).is_empty():
		return "with both slabs down the chain is %s" % [route.chain(FROM, TO, SHIP_RADIUS)]
	# As for a blocked opening: no chain, so the caller flies straight.
	if route.waypoints(FROM, TO, SHIP_RADIUS) != [TO]:
		return "waypoints were %s" % [route.waypoints(FROM, TO, SHIP_RADIUS)]
	return ""


## Both ends in the slab's own tunnel, one each side: the route leaves by one
## end and comes back in by the other.
func test_ends_either_side_of_a_slab_in_one_tunnel_go_round_the_loop() -> String:
	var route: LevelRoute = _route()
	var below: Vector3 = Vector3(-9.0, 0.0, -30.0)
	var above: Vector3 = Vector3(-9.0, 0.0, -14.0)
	if route.waypoints(below, above, SHIP_RADIUS) != [above]:
		return "with no slab the tunnel is not flown straight"
	route.close_blocked(_fallen([LEFT_SLAB]), SHIP_RADIUS)
	if route.chain(below, above, SHIP_RADIUS) != [1, 3, 4, 2, 0, 1]:
		return "round the loop the chain is %s" % [route.chain(below, above, SHIP_RADIUS)]
	if route.waypoints(below, above, SHIP_RADIUS).size() != 6:
		return "waypoints were %s" % [route.waypoints(below, above, SHIP_RADIUS)]
	return ""


func test_the_same_inputs_give_the_same_route() -> String:
	var first: LevelRoute = _route()
	var second: LevelRoute = _route()
	first.close_blocked(_fallen([LEFT_SLAB]), SHIP_RADIUS)
	second.close_blocked(_fallen([LEFT_SLAB]), SHIP_RADIUS)
	if first.waypoints(FROM, TO, SHIP_RADIUS) != second.waypoints(FROM, TO, SHIP_RADIUS):
		return "two routes from the same inputs differ"
	return ""
