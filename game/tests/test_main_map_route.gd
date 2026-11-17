extends RefCounted

## The known escape route on the main scene's map (#402, MAP-2, RUN-4, MP-2):
## none before the reactor dies or after the run ends; during the meltdown the
## route `EscapePath.known_route` finds, searched at most once every
## `MapRouteWiring.ROUTE_EVERY_TICKS` ticks and at once when debris falls or a box
## is explored; and the run's state hash is the same with or without it.

const TICK: float = 1.0 / 60.0
## G2's reactor room: far from the exit, so the ship does not escape at once.
const REACTOR_BOX: int = 4
## G2's start room, where the ship is on its first tick.
const START_BOX: int = 0
## The shaft from the start room down, explored by hand in one test.
const SHAFT_BOX: int = 1
## Debris for the main scene's G2 run, which has none of its own: one entry in
## the side room (box 3), off the route, falling half a second into the meltdown.
const SIDE_DEBRIS: Array = [{"position": [20.0, -32.0, -72.0], "radius": 1.0, "after_seconds": 0.5}]


## The wiring with its frame work switched off, for the run without it.
class NoWiring:
	extends MapWiring

	func update(_session: LocalSession, _delta_seconds: float, _shared: ClickHold = null) -> void:
		pass


func _main(level_name: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if level_name != "":
		main.call("use_level", LevelSwitch.path_for(level_name))
	main.call("_ready")
	return main


func _ticks(main: Node, ticks: int) -> void:
	for i: int in ticks:
		main.call("advance_frame", TICK)


func _session(main: Node) -> LocalSession:
	return main.get("session") as LocalSession


func _wiring(main: Node) -> MapRouteWiring:
	return (main.get("map") as MapWiring).route_wiring


func _map(main: Node) -> MapWiring:
	return main.get("map") as MapWiring


func _centre(box: BoxBounds) -> Vector3:
	return (box.min_corner + box.max_corner) / 2.0


## G2 with `SIDE_DEBRIS`, one tick flown from the start, then the ship moved
## into the reactor room (after the first tick, which fixes where the exit is),
## every box explored when `explore_all`, and the reactor destroyed when
## `destroy`. The next tick is the first of the meltdown.
func _g2_meltdown(explore_all: bool, destroy: bool = true) -> Node:
	var main: Node = _main("g2")
	var session: LocalSession = _session(main)
	session.sim.set_debris(MeltdownDebris.parse(SIDE_DEBRIS))
	main.call("advance_frame", 0.0)
	_ticks(main, 1)
	var walls: BoxUnion = session.replay.walls()
	session.sim.ships[0].position = _centre(walls.boxes[REACTOR_BOX])
	session.sim.ships[0].velocity = Vector3.ZERO
	if explore_all:
		for box: BoxBounds in walls.boxes:
			_map(main).explored.visit(_centre(box))
	if destroy:
		session.sim.reactor.apply_damage(session.sim.reactor.hull)
	return main


func test_no_route_before_the_reactor_dies() -> String:
	var main: Node = _g2_meltdown(true, false)
	_ticks(main, 90)
	var wiring: MapRouteWiring = _wiring(main)
	var searches: int = wiring.searches
	var drawn: int = _map(main).hologram.route().segment_count()
	var has_route: bool = wiring.route != null
	main.free()
	if searches != 0 or has_route or drawn != 0:
		return "before the reactor dies: %d searches, route %s, %d segments drawn" % [
			searches, has_route, drawn]
	return ""


func test_g2_route_with_every_box_explored_matches_length_mm() -> String:
	var main: Node = _g2_meltdown(true)
	_ticks(main, 1)
	var session: LocalSession = _session(main)
	var wiring: MapRouteWiring = _wiring(main)
	var route: KnownRoute = wiring.route
	var from: Vector3 = session.current_ship().position
	var exit_at: Vector3 = ReplayStartLine.position(session.replay, 0)
	var want: int = EscapePath.length_mm(session.replay.walls(), from, exit_at)
	var drawn: int = _map(main).hologram.route().segment_count()
	main.free()
	if route == null:
		return "no route was handed to the map during the meltdown"
	if want == EscapePath.UNREACHABLE or route.length_mm != want:
		return "the route is %d mm, length_mm gives %d" % [route.length_mm, want]
	if route.points_mm.size() < 2 or drawn != route.points_mm.size() - 1:
		return "the map draws %d segments for %d route points" % [drawn, route.points_mm.size()]
	if route.points_mm[0] != EscapePath.to_mm(from) \
			or route.points_mm[-1] != EscapePath.to_mm(exit_at):
		return "the route runs %s..%s, not ship to exit" % [route.points_mm[0], route.points_mm[-1]]
	return ""


func test_unexplored_boxes_leave_no_route_out() -> String:
	var main: Node = _g2_meltdown(false)
	_ticks(main, 1)
	var wiring: MapRouteWiring = _wiring(main)
	var route: KnownRoute = wiring.route
	var explored: Array[int] = _map(main).explored.explored()
	main.free()
	if explored != [START_BOX, REACTOR_BOX]:
		return "only the start and reactor rooms should be explored, got %s" % [explored]
	if route == null or route.length_mm != EscapePath.UNREACHABLE:
		return "a route through unexplored boxes was handed over"
	return ""


func test_searches_at_most_once_every_15_ticks() -> String:
	var main: Node = _g2_meltdown(true)
	_ticks(main, 1)
	var wiring: MapRouteWiring = _wiring(main)
	var first: int = wiring.searches
	_ticks(main, 14)
	var within: int = wiring.searches
	_ticks(main, 1)
	var at_15: int = wiring.searches
	_ticks(main, 45)
	var after_60: int = wiring.searches
	main.free()
	if first != 1 or within != 1:
		return "searched %d times on the reactor's death and %d within 15 ticks" % [first, within]
	if at_15 != 2 or after_60 != 5:
		return "searched %d times after 15 ticks and %d after 60, expected 2 and 5" % [
			at_15, after_60]
	return ""


func test_searches_at_once_when_debris_falls() -> String:
	var main: Node = _g2_meltdown(true)
	var session: LocalSession = _session(main)
	var debris: MeltdownDebris = session.sim.debris
	var wiring: MapRouteWiring = _wiring(main)
	_ticks(main, 1)  # The reactor's death searches once.
	var frames: int = 0
	while not debris.is_solid(0) and frames < 120:
		# Pretend a search just ran, so only the falling debris can start one.
		wiring.set("_tick", session.sim.tick)
		var before: int = wiring.searches
		_ticks(main, 1)
		frames += 1
		if not debris.is_solid(0) and wiring.searches != before:
			main.free()
			return "searched on tick %d with nothing new" % session.sim.tick
		if debris.is_solid(0) and wiring.searches != before + 1:
			main.free()
			return "the debris fell on tick %d without a search" % session.sim.tick
	var outcome: ExitRule.Outcome = session.sim.outcome()
	main.free()
	if frames >= 120:
		return "the debris never fell"
	if outcome != ExitRule.Outcome.RUNNING:
		return "the run ended before the debris fell"
	return ""


func test_searches_at_once_when_a_box_is_explored() -> String:
	var main: Node = _g2_meltdown(false)
	_ticks(main, 1)
	var session: LocalSession = _session(main)
	var wiring: MapRouteWiring = _wiring(main)
	var before: int = wiring.searches
	# A frame of no time runs no tick; only the newly explored box can search.
	_map(main).explored.visit(_centre(session.replay.walls().boxes[SHAFT_BOX]))
	main.call("advance_frame", 0.0)
	var after: int = wiring.searches
	main.free()
	if after != before + 1:
		return "exploring a box searched %d times, expected 1" % (after - before)
	return ""


func test_no_route_once_the_run_is_lost() -> String:
	var main: Node = _g2_meltdown(true)
	_ticks(main, 1)
	var session: LocalSession = _session(main)
	var wiring: MapRouteWiring = _wiring(main)
	var during: bool = wiring.route != null
	session.sim.reactor.meltdown_ticks_left = 1
	_ticks(main, 3)
	var outcome: ExitRule.Outcome = session.sim.outcome()
	var after: bool = wiring.route != null
	var drawn: int = _map(main).hologram.route().segment_count()
	main.free()
	if not during:
		return "no route during the meltdown"
	if outcome != ExitRule.Outcome.LOST:
		return "the run did not end lost"
	if after or drawn != 0:
		return "after the loss the route is %s with %d segments drawn" % [after, drawn]
	return ""


func test_no_route_once_the_ship_escapes() -> String:
	# The ship stays at its start, inside the exit, so it escapes on the first tick.
	var main: Node = _main("g2")
	main.call("advance_frame", 0.0)
	var session: LocalSession = _session(main)
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	_ticks(main, 2)
	var outcome: ExitRule.Outcome = session.sim.outcome()
	var wiring: MapRouteWiring = _wiring(main)
	var has_route: bool = wiring.route != null
	var drawn: int = _map(main).hologram.route().segment_count()
	main.free()
	if outcome != ExitRule.Outcome.ESCAPED:
		return "the ship at its start did not escape"
	if has_route or drawn != 0:
		return "after the escape a route is drawn"
	return ""


func test_the_debris_copy_is_not_the_simulations() -> String:
	var source: MeltdownDebris = MeltdownDebris.parse([
		{"position": [0, 0, 0], "radius": 1.0, "after_seconds": 0.5},
		{"position": [5, 0, 0], "radius": 1.0, "after_seconds": 5.0}])
	source.elapsed_ticks = 40
	source.skipped[1] = true
	var copy: MeltdownDebris = MapRouteWiring.debris_copy(source)
	if copy == source or copy.state_hash() != source.state_hash():
		return "the copy is the source or differs from it"
	if not copy.is_solid(0) or not copy.is_skipped(1):
		return "the copy lost which entries fell or were skipped"
	copy.elapsed_ticks = 0
	copy.skipped[1] = false
	if source.elapsed_ticks != 40 or not source.is_skipped(1):
		return "writing to the copy changed the source"
	if MapRouteWiring.debris_copy(null) != null:
		return "no debris gave a copy"
	return ""


func test_the_state_hash_is_the_same_without_the_wiring() -> String:
	var hashes: Array[int] = []
	var searched: Array[bool] = []
	for with_map: bool in [true, false]:
		var main: Node = _main("g2")
		if not with_map:
			main.set("map", NoWiring.new())
		var session: LocalSession = _session(main)
		session.sim.set_debris(MeltdownDebris.parse(SIDE_DEBRIS))
		main.call("advance_frame", 0.0)
		_ticks(main, 1)
		session.sim.ships[0].position = _centre(session.replay.walls().boxes[REACTOR_BOX])
		session.sim.reactor.apply_damage(session.sim.reactor.hull)
		_ticks(main, 120)
		hashes.append(session.sim.state_hash())
		searched.append(_wiring(main).searches > 0)
		main.free()
	if searched != [true, false]:
		return "the route was searched %s, expected [true, false]" % [searched]
	if hashes[0] != hashes[1]:
		return "the state hash is %d with the route and %d without" % [hashes[0], hashes[1]]
	return ""
