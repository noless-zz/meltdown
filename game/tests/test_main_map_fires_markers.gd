extends RefCounted

## Burning fire on the main scene's hand-held map (#520, MAP-2, RUN-4, ARC-3,
## CMF-8): with the #499 fixture (one solid and one fire entry) no fire is
## marked before the fire's fall tick, one marker sits at the fire's fitted
## position after both falls and none for the solid entry, and the marks freeze
## while paused and go once the run ends. Unexplored space, a level without
## fire, the marker data and the state hash are in
## `test_main_map_fires_scope.gd`, which shares the fixtures below.
##
## Fires are marked only in explored boxes (#562). The fixture's fire is centred
## 1 m inside rock, so these tests use a copy with it moved into box 3 and mark
## that box explored on the map.

const TICK: float = 1.0 / 60.0
const FIXTURE: String = "res://tests/fixtures/fire_debris_level.json"
const SOLID: int = 0
const FIRE: int = 1
## Ticks after the reactor's death until each entry falls (the fixture's 0.5 s and 1 s).
const SOLID_FALL_TICKS: int = 30
const FIRE_FALL_TICKS: int = 60
const EPSILON: float = 0.0001
## The fixture with the fire centred in box 3, written by `moved_fixture`.
const MOVED: String = "user://test_main_map_fires_level.json"
const MOVED_FIRE_X: float = 21.0


## `FIXTURE` with the fire entry's centre moved into box 3, at `MOVED`.
static func moved_fixture() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	data["debris"][FIRE]["position"][0] = MOVED_FIRE_X
	var file: FileAccess = FileAccess.open(MOVED, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return MOVED


static func main_scene(path: String) -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if path == FIXTURE:
		path = moved_fixture()
	var used: bool = path == "" or main.call("use_level", path)
	if path == MOVED:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MOVED))
	if not used:
		main.free()
		return null
	main.call("_ready")
	return main


static func advance_ticks(main: Node, ticks: int) -> void:
	for i: int in ticks:
		main.call("advance_frame", TICK)


static func session_of(main: Node) -> LocalSession:
	return main.get("session") as LocalSession


static func map_of(main: Node) -> MapWiring:
	return main.get("map") as MapWiring


static func fires_of(main: Node) -> MapFires:
	return map_of(main).hologram.fires()


## The box of `walls` holding `point`, or -1.
static func box_holding(walls: BoxUnion, point: Vector3) -> int:
	for index: int in walls.boxes.size():
		if walls.boxes[index].holds(point, 0.0):
			return index
	return -1


## Marks the box holding the fire entry explored on `main`'s map, view side only,
## as if the ship had passed through it; the next frame rebuilds the map.
static func explore_fire_box(main: Node) -> void:
	map_of(main).explored.visit(session_of(main).sim.debris.position(FIRE))


## `path`'s main scene one tick in, the ship moved into the reactor's room so it
## does not escape at once, and the reactor destroyed: the next tick is the
## meltdown's first. With `explore_fire`, the fire's box is explored on the map
## too (#562). Null when the level is rejected.
static func melting(path: String = FIXTURE, explore_fire: bool = true) -> Node:
	var main: Node = main_scene(path)
	if main == null:
		return null
	main.call("advance_frame", 0.0)
	advance_ticks(main, 1)
	var session: LocalSession = session_of(main)
	var walls: BoxUnion = session.replay.walls()
	var reactor: ReactorState = session.sim.reactor
	var box: int = box_holding(walls, reactor.position())
	if box >= 0:
		var bounds: BoxBounds = walls.boxes[box]
		session.sim.ships[0].position = (bounds.min_corner + bounds.max_corner) / 2.0
		session.sim.ships[0].velocity = Vector3.ZERO
	reactor.apply_damage(reactor.hull)
	if explore_fire and path == FIXTURE:
		explore_fire_box(main)
	return main


## Where the hologram fits level-space `point`, as `MapHologram.build` fits the lines.
static func fitted(main: Node, point: Vector3) -> Vector3:
	var map: MapWiring = map_of(main)
	var segments: PackedVector3Array = MapWireframe.segments(
		session_of(main).replay.walls(), map.explored.explored())
	return MapHologram.fit_transform(segments, float(map.hologram.look()["size_m"])) * point



func test_no_fire_marker_before_the_fires_tick() -> String:
	var main: Node = melting()
	if main == null:
		return "the fixture level was rejected"
	advance_ticks(main, FIRE_FALL_TICKS - 2)
	var debris: MeltdownDebris = session_of(main).sim.debris
	var problem: String = ""
	if not debris.is_solid(SOLID) or debris.is_burning(FIRE):
		problem = "the solid entry has not fallen or the fire burns early"
	elif map_of(main).route_wiring.route == null:
		problem = "no route during the meltdown"
	elif fires_of(main).marker_count() != 0:
		problem = "%d fire markers before the fire's tick" % fires_of(main).marker_count()
	main.free()
	return problem


func test_one_fire_marker_at_the_fitted_position_after_both_fall() -> String:
	var main: Node = melting()
	if main == null:
		return "the fixture level was rejected"
	advance_ticks(main, FIRE_FALL_TICKS + 1)
	var session: LocalSession = session_of(main)
	var debris: MeltdownDebris = session.sim.debris
	var fires: MapFires = fires_of(main)
	var problem: String = ""
	if session.sim.outcome() != ExitRule.Outcome.RUNNING:
		problem = "the run ended before the fire fell"
	elif not debris.is_solid(SOLID) or not debris.is_burning(FIRE):
		problem = "the entries have not both fallen"
	elif fires.marker_count() != 1:
		problem = "%d fire markers after both falls, want 1" % fires.marker_count()
	else:
		var at: Vector3 = fires.marker_positions()[0]
		var want: Vector3 = fitted(main, debris.position(FIRE))
		if at.distance_to(want) > EPSILON:
			problem = "the fire marker is at %s, want %s" % [at, want]
		elif at.distance_to(fitted(main, debris.position(SOLID))) <= EPSILON:
			problem = "the marker sits on the solid entry"
	main.free()
	return problem


func test_the_fire_marker_appears_on_the_tick_the_fire_catches() -> String:
	var main: Node = melting()
	if main == null:
		return "the fixture level was rejected"
	var debris: MeltdownDebris = session_of(main).sim.debris
	var frames: int = 0
	while not debris.is_burning(FIRE) and frames < FIRE_FALL_TICKS + 30:
		advance_ticks(main, 1)
		frames += 1
	var count: int = fires_of(main).marker_count()
	main.free()
	if count != 1:
		return "%d fire markers on the tick the fire caught, want 1" % count
	return ""


func test_pausing_freezes_the_fire_markers() -> String:
	var main: Node = melting()
	if main == null:
		return "the fixture level was rejected"
	var session: LocalSession = session_of(main)
	advance_ticks(main, FIRE_FALL_TICKS - 10)
	session.paused = true
	advance_ticks(main, 60)
	var before_fire: int = fires_of(main).marker_count()
	session.paused = false
	advance_ticks(main, 20)
	var positions: PackedVector3Array = fires_of(main).marker_positions()
	session.paused = true
	advance_ticks(main, 120)
	var paused_positions: PackedVector3Array = fires_of(main).marker_positions()
	main.free()
	if before_fire != 0:
		return "a fire marker appeared while paused before the fire's tick"
	if positions.size() != 1:
		return "%d fire markers after resuming past the fire's tick" % positions.size()
	if paused_positions != positions:
		return "the fire markers changed while paused: %s then %s" % [positions, paused_positions]
	return ""


func test_no_fire_markers_once_the_run_is_lost() -> String:
	var main: Node = melting()
	if main == null:
		return "the fixture level was rejected"
	advance_ticks(main, FIRE_FALL_TICKS + 1)
	var session: LocalSession = session_of(main)
	var during: int = fires_of(main).marker_count()
	session.sim.reactor.meltdown_ticks_left = 1
	advance_ticks(main, 3)
	var outcome: ExitRule.Outcome = session.sim.outcome()
	var after: int = fires_of(main).marker_count()
	main.free()
	if during != 1:
		return "%d fire markers during the meltdown, want 1" % during
	if outcome != ExitRule.Outcome.LOST:
		return "the run did not end lost"
	if after != 0:
		return "%d fire markers after the loss" % after
	return ""
