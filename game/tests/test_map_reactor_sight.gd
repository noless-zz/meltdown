extends RefCounted

## The held map's reactor and exit markers after the G3 playtest (#913, MAP-1,
## MAP-2, RUN-2, MP-2): the reactor is known once the ship has a clear line to
## its centre, without entering its box, stays known, and is dimmed once it is
## destroyed; the exit cube is see-through, no bigger than before, and drawn
## under the reactor ball.
##
## The level is hand-built: a start room, a narrow corridor straight down -z
## (the doorway), and the reactor room beyond it, with the start off to one
## side so the corridor's walls hide the reactor from it.

const LEVEL: String = '{"boxes": [' \
	+ '{"min": [-5.0, -5.0, -20.0], "max": [5.0, 5.0, 5.0]},' \
	+ '{"min": [-2.0, -2.0, -40.0], "max": [2.0, 2.0, -18.0]},' \
	+ '{"min": [-10.0, -10.0, -70.0], "max": [10.0, 10.0, -38.0]}],' \
	+ '"start": {"position": [4.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]}, "robots": [],' \
	+ '"reactor": {"position": [0.0, 0.0, -60.0], "radius": 2.5, "hull": 400.0, "meltdown_seconds": 90.0}}'
const REACTOR_AT: Vector3 = Vector3(0.0, 0.0, -60.0)
## In the corridor, outside the reactor room, on the reactor's axis.
const DOORWAY: Vector3 = Vector3(0.0, 0.0, -30.0)
## In the start room, behind the corridor's wall as seen from the reactor.
const BEHIND_WALL: Vector3 = Vector3(4.0, 3.0, -10.0)
const REACTOR_BOX: int = 2
const FRAME: float = 1.0 / 60.0


## A session on the hand-built level and a wiring holding the map in a bare rig.
func _setup() -> Array:
	var level: LevelDef = LevelDef.parse_json(LEVEL)
	var session: LocalSession = LocalSession.for_level(level)
	var rig: Node3D = Node3D.new()
	var hand: Node3D = Node3D.new()
	hand.name = "LeftHand"
	rig.add_child(hand)
	var wiring: MapWiring = MapWiring.new()
	wiring.attach(rig, ThumbstickMapping.new())
	return [level, session, wiring, rig]


## Puts the ship at `at`, at rest, and runs the wiring for one frame.
func _stop_at(session: LocalSession, wiring: MapWiring, at: Vector3) -> void:
	session.sim.ships[0].position = at
	session.sim.ships[0].velocity = Vector3.ZERO
	session.reset_ship_snapshots()
	wiring.update(session, FRAME)


func _reactor_color(wiring: MapWiring) -> Color:
	var reactor: MeshInstance3D = wiring.hologram.marker_nodes()[1]
	return ((reactor.mesh as SphereMesh).material as StandardMaterial3D).emission


func test_the_level_is_as_the_tests_need() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL)
	if level.error != "":
		return "the hand-built level was rejected: %s" % level.error
	if not LineOfSight.clear(level.union, DOORWAY, REACTOR_AT):
		return "the doorway has no clear line to the reactor"
	if LineOfSight.clear(level.union, BEHIND_WALL, REACTOR_AT) \
			or LineOfSight.clear(level.union, level.start_position(), REACTOR_AT):
		return "the start room sees the reactor"
	if level.union.boxes[REACTOR_BOX].holds(DOORWAY, 0.0):
		return "the doorway is inside the reactor's box"
	return ""


func test_a_clear_line_from_the_doorway_marks_the_reactor() -> String:
	var parts: Array = _setup()
	var session: LocalSession = parts[1]
	var wiring: MapWiring = parts[2]
	_stop_at(session, wiring, BEHIND_WALL)
	var behind: bool = wiring.hologram.reactor_marker_shown()
	_stop_at(session, wiring, DOORWAY)
	var doorway: bool = wiring.hologram.reactor_marker_shown()
	var explored: Array[int] = wiring.explored.explored()
	_stop_at(session, wiring, BEHIND_WALL)
	var back: bool = wiring.hologram.reactor_marker_shown()
	(parts[3] as Node).free()
	if behind:
		return "the reactor is marked from behind the wall"
	if explored.has(REACTOR_BOX):
		return "the ship entered the reactor's box: explored %s" % [explored]
	if not doorway:
		return "the reactor is not marked with a clear line from the doorway"
	if not back:
		return "the reactor was forgotten once the ship flew back behind the wall"
	return ""


func test_behind_a_wall_the_reactor_stays_unmarked() -> String:
	var parts: Array = _setup()
	var session: LocalSession = parts[1]
	var wiring: MapWiring = parts[2]
	var shown: Array[bool] = []
	for at: Vector3 in [(parts[0] as LevelDef).start_position(), BEHIND_WALL, Vector3(-4.0, -4.0, -15.0)]:
		_stop_at(session, wiring, at)
		shown.append(wiring.hologram.reactor_marker_shown())
	(parts[3] as Node).free()
	if shown.has(true):
		return "the reactor is marked from the start room: %s" % [shown]
	return ""


func test_a_destroyed_reactor_is_marked_in_the_dead_colour() -> String:
	var parts: Array = _setup()
	var session: LocalSession = parts[1]
	var wiring: MapWiring = parts[2]
	_stop_at(session, wiring, BEHIND_WALL)
	var alive_colour: Color = _reactor_color(wiring)
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	_stop_at(session, wiring, BEHIND_WALL)
	var shown: bool = wiring.hologram.reactor_marker_shown()
	var dead_colour: Color = _reactor_color(wiring)
	var look: Dictionary = wiring.hologram.look()
	(parts[3] as Node).free()
	if alive_colour != look["reactor_color"]:
		return "the living reactor is drawn %s, want %s" % [alive_colour, look["reactor_color"]]
	if not shown:
		return "the destroyed reactor is not marked"
	if dead_colour != look["reactor_dead_color"]:
		return "the destroyed reactor is drawn %s, want %s" % [dead_colour, look["reactor_dead_color"]]
	return ""


func test_the_dead_colour_survives_a_rebuild() -> String:
	var map: MapHologram = MapHologram.new()
	var level: LevelDef = LevelDef.parse_json(LEVEL)
	map.build(level.union, [0])
	map.set_markers(level.start_position(), REACTOR_AT, true, true)
	map.build(level.union, [0, 1])
	var reactor: MeshInstance3D = map.marker_nodes()[1]
	var colour: Color = ((reactor.mesh as SphereMesh).material as StandardMaterial3D).emission
	var want: Color = map.look()["reactor_dead_color"]
	map.free()
	if colour != want:
		return "after a rebuild the destroyed reactor is drawn %s, want %s" % [colour, want]
	return ""


func test_the_exit_is_see_through_and_no_bigger_than_before() -> String:
	var map: MapHologram = MapHologram.new()
	var level: LevelDef = LevelDef.parse_json(LEVEL)
	map.build(level.union, [0])
	map.set_markers(level.start_position(), REACTOR_AT, true)
	var exit: MeshInstance3D = map.marker_nodes()[0]
	var reactor: MeshInstance3D = map.marker_nodes()[1]
	var look: Dictionary = map.look()
	var cube: BoxMesh = exit.mesh as BoxMesh
	var ball: StandardMaterial3D = (reactor.mesh as SphereMesh).material as StandardMaterial3D
	map.free()
	if cube == null:
		return "the exit marker is not a cube"
	# Before #913 the cube's edge was twice `exit_radius_m`.
	var before: float = float(look["exit_radius_m"]) * 2.0
	if cube.size.x > before + 1e-6 or cube.size.y > before + 1e-6 or cube.size.z > before + 1e-6:
		return "the exit cube is %s, bigger than the %.4f m edge it had" % [cube.size, before]
	var material: StandardMaterial3D = cube.material as StandardMaterial3D
	if material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		return "the exit cube is not transparent"
	if material.albedo_color.a > float(look["exit_alpha"]) + 1e-6:
		return "the exit cube's alpha %.3f is above exit_alpha %.3f" % [material.albedo_color.a, look["exit_alpha"]]
	if material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED:
		return "the exit cube writes depth, so it can hide lines behind it"
	if not ball.no_depth_test or ball.render_priority <= material.render_priority:
		return "the reactor ball is not drawn over the exit (no depth test %s, priority %d vs %d)" % [
			ball.no_depth_test, ball.render_priority, material.render_priority]
	return ""


func test_the_shipped_look_holds_the_new_keys() -> String:
	var look: Dictionary = MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	if look.has("error"):
		return "map_look.json was rejected: %s" % look["error"]
	if absf(float(look["exit_alpha"]) - 0.35) > 1e-6:
		return "exit_alpha ships as %s, want 0.35" % look["exit_alpha"]
	var dead: Color = look["reactor_dead_color"]
	var alive: Color = look["reactor_color"]
	if dead.get_luminance() >= alive.get_luminance():
		return "the dead reactor colour %s is not dimmer than %s" % [dead, alive]
	var shipped: String = FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE)
	var bad: Dictionary = {
		'"exit_alpha": 0.35': ['"exit_alpha": 0.0', '"exit_alpha": 1.5'],
		'"reactor_dead_color": [0.45, 0.12, 0.35]': ['"reactor_dead_color": [1.0, 0.0]'],
	}
	for shipped_text: String in bad:
		if not shipped.contains(shipped_text):
			return "map_look.json does not hold %s" % shipped_text
		for text: String in bad[shipped_text]:
			if not MapLook.parse(shipped.replace(shipped_text, text)).has("error"):
				return "%s was accepted" % text
	return ""
