extends RefCounted

## The escape cues in the main scene (#617, RUN-2, RUN-3, MAP-2, CMF-8, MP-2):
## G2 has an exit sign at its entrance and the test tunnel none; the cockpit
## countdown shows when the reactor dies and hides after the first show time;
## the arrow follows the same route the held map draws; the cue rides with the
## status panel; and the run's state hash is the same without the cues.

const TICK: float = 1.0 / 60.0
## G2's reactor room: far from the exit, so the ship does not escape at once.
const REACTOR_BOX: int = 4


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


func _escape(main: Node) -> EscapeCueWiring:
	return (main.get("meltdown") as MeltdownWiring).escape


func _centre(box: BoxBounds) -> Vector3:
	return (box.min_corner + box.max_corner) / 2.0


## G2 one tick in, the ship moved to the reactor room with every box explored
## by the map (and by the cue when `own_search`, the cue left without the map's
## route wiring, as when it is built alone), and the reactor destroyed.
func _g2_meltdown(own_search: bool = false) -> Node:
	var main: Node = _main("g2")
	var session: LocalSession = _session(main)
	if own_search:
		_escape(main).route_wiring = null
		_escape(main).attach(main, session)
	main.call("advance_frame", 0.0)
	_ticks(main, 1)
	var walls: BoxUnion = session.replay.walls()
	session.sim.ships[0].position = _centre(walls.boxes[REACTOR_BOX])
	session.sim.ships[0].velocity = Vector3.ZERO
	for box: BoxBounds in walls.boxes:
		(main.get("map") as MapWiring).explored.visit(_centre(box))
		if own_search:
			_escape(main).explored.visit(_centre(box))
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	return main


func test_g2_has_an_exit_sign_at_the_entrance_and_the_tunnel_none() -> String:
	var main: Node = _main("g2")
	var marker: ExitMarker = _escape(main).exit_marker
	var in_world: bool = marker != null and marker.get_parent() == main
	var at: Vector3 = Vector3.INF if marker == null else marker.position
	var want: Vector3 = ReplayStartLine.position(_session(main).replay, 0)
	main.free()
	var tunnel: Node = _main()
	var none: bool = _escape(tunnel).exit_marker == null
	tunnel.free()
	if not in_world:
		return "G2 has no exit sign in the world"
	if at != want:
		return "the exit sign is at %s, the entrance at %s" % [at, want]
	if not none:
		return "the test tunnel, which has no reactor, has an exit sign"
	return ""


func test_no_cue_before_the_reactor_dies() -> String:
	var main: Node = _main("g2")
	_ticks(main, 30)
	var cue: MeltdownCue = _escape(main).cue
	var shown: bool = cue != null and (cue.countdown.visible or cue.arrow.visible)
	var searches: int = _escape(main).searches
	main.free()
	if shown or searches != 0:
		return "before the reactor dies: cue shown %s, %d searches" % [shown, searches]
	return ""


func test_the_countdown_shows_at_once_and_hides_after_the_first_show() -> String:
	var main: Node = _g2_meltdown()
	_ticks(main, 1)
	var cue: MeltdownCue = _escape(main).cue
	if cue == null:
		main.free()
		return "no cue after the reactor died"
	var at_once: bool = cue.countdown.visible and cue.line.visible
	var first_ticks: int = roundi(float(EscapeCueLook.shared()["first_show_seconds"]) * 60.0)
	_ticks(main, first_ticks - 2)
	var still: bool = cue.countdown.visible
	_ticks(main, 2)
	var later: bool = cue.countdown.visible or cue.line.visible
	var rig: Node = main.get_node("XRRig")
	var under_rig: bool = cue.get_parent() == rig
	main.free()
	if not at_once:
		return "the countdown did not show when the reactor died"
	if not still:
		return "the countdown hid before the first show time"
	if later:
		return "the countdown still showed after the first show time"
	if not under_rig:
		return "the cue is not under the rig, beside the status panel"
	return ""


func test_the_arrow_follows_the_maps_route() -> String:
	var main: Node = _g2_meltdown()
	_ticks(main, 2)
	var escape: EscapeCueWiring = _escape(main)
	var map_route: KnownRoute = (main.get("map") as MapWiring).route_wiring.route
	var route: KnownRoute = escape.route
	var shown: bool = escape.cue != null and escape.cue.arrow.visible
	var direction: Vector3 = Vector3.ZERO
	var want: Vector3 = Vector3.ZERO
	if shown and route != null and route.points_mm.size() >= 2:
		var world_from_cue: Transform3D = escape.world_from_cue()
		direction = escape.cue.arrow_direction(world_from_cue)
		var from: Vector3 = world_from_cue * escape.cue.arrow.position
		want = (Vector3(route.points_mm[1]) / 1000.0 - from).normalized()
	main.free()
	if route == null or map_route == null:
		return "no route during the meltdown (cue %s, map %s)" % [route != null, map_route != null]
	if route.points_mm != map_route.points_mm:
		return "the cue's route %s is not the map's %s" % [route.points_mm, map_route.points_mm]
	if not shown:
		return "the arrow is hidden with a route known"
	if direction.angle_to(want) > 0.02:
		return "the arrow points %s, the next corner is %s" % [direction, want]
	return ""


func test_one_route_search_per_interval_shared_by_map_and_arrow() -> String:
	var main: Node = _g2_meltdown()
	_ticks(main, 1)
	var escape: EscapeCueWiring = _escape(main)
	var map_wiring: MapRouteWiring = (main.get("map") as MapWiring).route_wiring
	var session: LocalSession = _session(main)
	var problem: String = ""
	if escape.route_wiring != map_wiring:
		problem = "the main scene did not hand the map's route wiring to the cue"
	elif escape.explored != null:
		problem = "the cue keeps its own explored boxes"
	var intervals: int = 0
	for interval: int in 8:
		if problem != "":
			break
		var before: int = map_wiring.searches + escape.searches
		var solid: int = MapRouteWiring.solid_count(session.sim.debris)
		_ticks(main, MapRouteWiring.ROUTE_EVERY_TICKS)
		var ran: int = map_wiring.searches + escape.searches - before
		if escape.searches != 0:
			problem = "the cue searched %d times itself" % escape.searches
		elif escape.route == null or not is_same(escape.route, map_wiring.route):
			problem = "the arrow does not read the map's route"
		elif solid == MapRouteWiring.solid_count(session.sim.debris):
			# Falling debris rightly forces a search; count only quiet intervals.
			intervals += 1
			if ran != 1:
				problem = "interval %d ran %d route searches" % [interval, ran]
	main.free()
	if problem == "" and intervals == 0:
		problem = "debris fell in every interval; no quiet interval was counted"
	return problem


func test_without_a_route_wiring_the_cue_searches_as_the_map_does() -> String:
	var main: Node = _g2_meltdown(true)
	_ticks(main, 2)
	var escape: EscapeCueWiring = _escape(main)
	var map_route: KnownRoute = (main.get("map") as MapWiring).route_wiring.route
	var route: KnownRoute = escape.route
	var searches: int = escape.searches
	var shown: bool = escape.cue != null and escape.cue.arrow.visible
	main.free()
	if searches == 0 or route == null or map_route == null:
		return "the cue alone did not search (%d searches)" % searches
	if route.points_mm != map_route.points_mm:
		return "the cue's own route %s is not the map's %s" % [route.points_mm, map_route.points_mm]
	if not shown:
		return "the arrow is hidden with a route known"
	return ""


func test_the_cue_sits_at_the_panels_eye_point() -> String:
	var main: Node = _g2_meltdown()
	_ticks(main, 1)
	var panel: StatusPanel = main.get("status_panel") as StatusPanel
	var cue: MeltdownCue = _escape(main).cue
	var eye: Transform3D = cue.transform
	var panel_at: Transform3D = panel.transform
	main.free()
	if not StatusPanel.rig_transform(eye).is_equal_approx(panel_at):
		return "the cue's eye point %s does not place the panel at %s" % [eye, panel_at]
	return ""


func test_the_cue_hides_once_the_run_is_lost() -> String:
	var main: Node = _g2_meltdown()
	_ticks(main, 1)
	_session(main).sim.ships[0].hull = 0.0
	_ticks(main, 2)
	var cue: MeltdownCue = _escape(main).cue
	var shown: bool = cue.countdown.visible or cue.arrow.visible
	main.free()
	if shown:
		return "the cue still shows after the ship was lost"
	return ""


## The wiring with its frame work switched off, for the run without it.
class NoEscape:
	extends EscapeCueWiring

	func update(_session: LocalSession, _panel: StatusPanel) -> void:
		pass


func test_the_state_hash_is_the_same_without_the_cues() -> String:
	var hashes: Array[int] = []
	for with_cues: bool in [true, false]:
		var main: Node = _main("g2")
		if not with_cues:
			(main.get("meltdown") as MeltdownWiring).escape = NoEscape.new()
		var session: LocalSession = _session(main)
		main.call("advance_frame", 0.0)
		_ticks(main, 1)
		session.sim.ships[0].position = _centre(session.replay.walls().boxes[REACTOR_BOX])
		session.sim.reactor.apply_damage(session.sim.reactor.hull)
		_ticks(main, 400)
		hashes.append(session.sim.state_hash())
		main.free()
	if hashes[0] != hashes[1]:
		return "the state hash is %d with the cues and %d without" % [hashes[0], hashes[1]]
	return ""
