extends RefCounted

## `OpeningGraph` splits a box where solid box debris closes its whole
## cross-section, by `BoxSplit`'s rule, and so agrees with `KnownRoute.find`
## (every box explored) on whether the start can be reached from the reactor
## (#869, RUN-4, GEN-3, ARC-2). The levels are `test_box_split.gd`'s: a room
## and a 4 m tunnel off it, with and without a loop round the tunnel's middle.

const SHIP_RADIUS: float = 1.0
## The start in the room, the reactor deep in the tunnel.
const ENDS: String = """
	"start": {"position": [0.0, 0.0, -2.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [0, 0, -40], "radius": 1, "hull": 40, "meltdown_seconds": 60},
"""
const ROOM: String = '{"min": [-10, -5, -10], "max": [10, 5, 0]}'
const TUNNEL: String = '{"min": [-2, -2, -70], "max": [2, 2, -8]}'
## The side corridor that joins the tunnel beyond z -15 back to the room.
const LOOP: String = '{"min": [-1, -2, -30], "max": [10, 2, -26]}, {"min": [6, -2, -30], "max": [10, 2, -8]}'
## #514's probe: a slab across the whole tunnel at z -15, touching no opening.
const SLAB: String = '{"position": [0, 0, -15], "size": [4, 4, 0.5], "after_seconds": 0.05}'
## The same slab past the reactor: it splits the tunnel, but not between any
## two of the tunnel's own points.
const FAR_SLAB: String = '{"position": [0, 0, -60], "size": [4, 4, 0.5], "after_seconds": 0.05}'
## Across the room at z -5, 8 m of its 20 m: 12 m are left beside it.
const ROOM_SLAB: String = '{"position": [-6, 0, -5], "size": [8, 10, 0.5], "after_seconds": 0.05}'


## A level of `boxes` and `debris` (JSON lists without brackets), all fallen.
func _level(boxes: String, debris: String) -> LevelDef:
	var level: LevelDef = LevelDef.parse_json('{"boxes": [%s], %s "debris": [%s]}'
			% [boxes, ENDS, debris])
	if level.debris == null:
		level.debris = MeltdownDebris.new()
	level.debris.elapsed_ticks = 600
	return level


## Whether `OpeningGraph` finds a route with every entry of the level fallen:
## the openings they block closed and the boxes they split split.
func _graph_route(level: LevelDef, graph: OpeningGraph) -> bool:
	var closed: Array[bool] = []
	for k: int in graph.opening_count():
		closed.append(graph.blocks(k, level.debris))
	var splits: Array[Vector4i] = []
	for index: int in level.debris.size():
		splits.append_array(graph.splits_by(level.debris, index))
	return graph.connected(closed, splits)


func _known_route(level: LevelDef) -> bool:
	var all: Array[int] = []
	for box: int in level.union.boxes.size():
		all.append(box)
	var route: KnownRoute = KnownRoute.find(level.union, all, level.reactor.position(),
			level.start_position(), level.debris, SHIP_RADIUS)
	return route.length_mm != EscapePath.UNREACHABLE


## "" when the graph and `KnownRoute` agree that a route is `expected`.
func _agree(level: LevelDef, expected: bool) -> String:
	if level.error != "":
		return level.error
	var graph: bool = _graph_route(level, OpeningGraph.new(level, SHIP_RADIUS))
	var known: bool = _known_route(level)
	if graph != known:
		return "OpeningGraph finds a route %s, KnownRoute %s" % [graph, known]
	return "" if graph == expected else "both find a route %s, expected %s" % [graph, expected]


func test_a_slab_across_a_dead_end_tunnel_closes_the_route() -> String:
	var level: LevelDef = _level(ROOM + ", " + TUNNEL, SLAB)
	var problem: String = _agree(level, false)
	if problem != "":
		return problem
	var splits: Array[Vector4i] = OpeningGraph.new(level, SHIP_RADIUS).splits_by(level.debris, 0)
	if splits != [Vector4i(1, 0, 2, -15000)]:
		return "splits %s, expected the tunnel (box 1) across z at -15000" % [splits]
	return _agree(_level(ROOM + ", " + TUNNEL, ""), true)


func test_a_slab_with_a_loop_round_it_leaves_a_route() -> String:
	var level: LevelDef = _level(ROOM + ", " + TUNNEL + ", " + LOOP, SLAB)
	var problem: String = _agree(level, true)
	if problem != "":
		return problem
	if OpeningGraph.new(level, SHIP_RADIUS).splits_by(level.debris, 0).is_empty():
		return "the slab splits nothing, so the loop is not what keeps the route"
	return ""


func test_a_slab_that_does_not_span_the_room_splits_nothing() -> String:
	var level: LevelDef = _level(ROOM + ", " + TUNNEL, ROOM_SLAB)
	var problem: String = _agree(level, true)
	if problem != "":
		return problem
	var splits: Array[Vector4i] = OpeningGraph.new(level, SHIP_RADIUS).splits_by(level.debris, 0)
	return "" if splits.is_empty() else "12 m left clear, yet split: %s" % [splits]


func test_a_slab_past_both_ends_counts_no_split() -> String:
	var level: LevelDef = _level(ROOM + ", " + TUNNEL, FAR_SLAB)
	var problem: String = _agree(level, true)
	if problem != "":
		return problem
	var splits: Array[Vector4i] = OpeningGraph.new(level, SHIP_RADIUS).splits_by(level.debris, 0)
	return "" if splits.is_empty() else "splits %s between none of the tunnel's points" % [splits]


## The guard's rule in `DebrisEscape` holds the slab back where it would close
## the last way out, and lets it fall where the loop goes round it, as
## `DebrisRouteGuard` does (`test_box_split.gd`).
func test_the_guard_rule_holds_the_slab_only_on_the_dead_end() -> String:
	var dead_end: LevelDef = _level(ROOM + ", " + TUNNEL, SLAB)
	var held: Array[bool] = DebrisEscape.held_by_guard(dead_end, dead_end.debris, SHIP_RADIUS)
	if held != [true]:
		return "dead end: held %s, expected [true]" % [held]
	var looped: LevelDef = _level(ROOM + ", " + TUNNEL + ", " + LOOP, SLAB)
	held = DebrisEscape.held_by_guard(looped, looped.debris, SHIP_RADIUS)
	return "" if held == [false] else "loop: held %s, expected [false]" % [held]


## With the slab fallen the escape goes round the loop, so a margin that fits
## only the straight way fails `debris_escape` and names the slab.
func test_a_split_that_lengthens_the_escape_fails_the_check() -> String:
	var level: LevelDef = _level(ROOM + ", " + TUNNEL + ", " + LOOP, SLAB)
	var clear_mm: int = EscapePath.length_mm(level.union, level.reactor.position(),
			level.start_position())
	var countdown: float = level.reactor.meltdown_ticks_for_path(clear_mm) \
			/ float(ReactorState.TICKS_PER_SECOND)
	# Just over the clear escape at 10 m/s.
	var margin: float = (clear_mm / 1000.0 / 10.0 + 0.1) / countdown
	var entries: Array[int] = DebrisEscape.lengthening(level, level.debris, SHIP_RADIUS, 10.0, margin)
	return "" if entries == [0] else "lengthening %s, expected [0]" % [entries]
