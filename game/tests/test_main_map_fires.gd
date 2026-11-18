extends RefCounted

## Burning fire on the main scene's hand-held map (#520, MAP-2, RUN-4, ARC-3,
## MP-2, CMF-8): with the #499 fixture (one solid and one fire entry) no fire is
## marked before the fire's fall tick, one marker sits at the fire's fitted
## position after both falls and none for the solid entry, the marks freeze
## while paused and go once the run ends, a level without fire marks nothing,
## and the run's state hash is the same with or without the map.

const TICK: float = 1.0 / 60.0
const FIXTURE: String = "res://tests/fixtures/fire_debris_level.json"
const SOLID: int = 0
const FIRE: int = 1
## Ticks after the reactor's death until each entry falls (the fixture's 0.5 s and 1 s).
const SOLID_FALL_TICKS: int = 30
const FIRE_FALL_TICKS: int = 60
const EPSILON: float = 0.0001


## The map wiring with its frame work switched off, for the run without it.
class NoWiring:
	extends MapWiring

	func update(_session: LocalSession, _delta_seconds: float, _shared: ClickHold = null) -> void:
		pass


func _main(path: String) -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if path != "" and not main.call("use_level", path):
		main.free()
		return null
	main.call("_ready")
	return main


func _ticks(main: Node, ticks: int) -> void:
	for i: int in ticks:
		main.call("advance_frame", TICK)


func _session(main: Node) -> LocalSession:
	return main.get("session") as LocalSession


func _map(main: Node) -> MapWiring:
	return main.get("map") as MapWiring


func _fires(main: Node) -> MapFires:
	return _map(main).hologram.fires()


## The box of `walls` holding `point`, or -1.
func _box_holding(walls: BoxUnion, point: Vector3) -> int:
	for index: int in walls.boxes.size():
		if walls.boxes[index].holds(point, 0.0):
			return index
	return -1


## `path`'s main scene one tick in, the ship moved into the reactor's room so it
## does not escape at once, and the reactor destroyed: the next tick is the
## meltdown's first. Null when the level is rejected.
func _melting(path: String = FIXTURE) -> Node:
	var main: Node = _main(path)
	if main == null:
		return null
	main.call("advance_frame", 0.0)
	_ticks(main, 1)
	var session: LocalSession = _session(main)
	var walls: BoxUnion = session.replay.walls()
	var reactor: ReactorState = session.sim.reactor
	var box: int = _box_holding(walls, reactor.position())
	if box >= 0:
		var bounds: BoxBounds = walls.boxes[box]
		session.sim.ships[0].position = (bounds.min_corner + bounds.max_corner) / 2.0
		session.sim.ships[0].velocity = Vector3.ZERO
	reactor.apply_damage(reactor.hull)
	return main


## Where the hologram fits level-space `point`, as `MapHologram.build` fits the lines.
func _fitted(main: Node, point: Vector3) -> Vector3:
	var map: MapWiring = _map(main)
	var segments: PackedVector3Array = MapWireframe.segments(
		_session(main).replay.walls(), map.explored.explored())
	return MapHologram.fit_transform(segments, float(map.hologram.look()["size_m"])) * point


func test_no_fire_marker_before_the_fires_tick() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, FIRE_FALL_TICKS - 2)
	var debris: MeltdownDebris = _session(main).sim.debris
	var problem: String = ""
	if not debris.is_solid(SOLID) or debris.is_burning(FIRE):
		problem = "the solid entry has not fallen or the fire burns early"
	elif _map(main).route_wiring.route == null:
		problem = "no route during the meltdown"
	elif _fires(main).marker_count() != 0:
		problem = "%d fire markers before the fire's tick" % _fires(main).marker_count()
	main.free()
	return problem


func test_one_fire_marker_at_the_fitted_position_after_both_fall() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, FIRE_FALL_TICKS + 1)
	var session: LocalSession = _session(main)
	var debris: MeltdownDebris = session.sim.debris
	var fires: MapFires = _fires(main)
	var problem: String = ""
	if session.sim.outcome() != ExitRule.Outcome.RUNNING:
		problem = "the run ended before the fire fell"
	elif not debris.is_solid(SOLID) or not debris.is_burning(FIRE):
		problem = "the entries have not both fallen"
	elif fires.marker_count() != 1:
		problem = "%d fire markers after both falls, want 1" % fires.marker_count()
	else:
		var at: Vector3 = fires.marker_positions()[0]
		var want: Vector3 = _fitted(main, debris.position(FIRE))
		if at.distance_to(want) > EPSILON:
			problem = "the fire marker is at %s, want %s" % [at, want]
		elif at.distance_to(_fitted(main, debris.position(SOLID))) <= EPSILON:
			problem = "the marker sits on the solid entry"
	main.free()
	return problem


func test_the_fire_marker_appears_on_the_tick_the_fire_catches() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	var debris: MeltdownDebris = _session(main).sim.debris
	var frames: int = 0
	while not debris.is_burning(FIRE) and frames < FIRE_FALL_TICKS + 30:
		_ticks(main, 1)
		frames += 1
	var count: int = _fires(main).marker_count()
	main.free()
	if count != 1:
		return "%d fire markers on the tick the fire caught, want 1" % count
	return ""


func test_pausing_freezes_the_fire_markers() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	var session: LocalSession = _session(main)
	_ticks(main, FIRE_FALL_TICKS - 10)
	session.paused = true
	_ticks(main, 60)
	var before_fire: int = _fires(main).marker_count()
	session.paused = false
	_ticks(main, 20)
	var positions: PackedVector3Array = _fires(main).marker_positions()
	session.paused = true
	_ticks(main, 120)
	var paused_positions: PackedVector3Array = _fires(main).marker_positions()
	main.free()
	if before_fire != 0:
		return "a fire marker appeared while paused before the fire's tick"
	if positions.size() != 1:
		return "%d fire markers after resuming past the fire's tick" % positions.size()
	if paused_positions != positions:
		return "the fire markers changed while paused: %s then %s" % [positions, paused_positions]
	return ""


func test_no_fire_markers_once_the_run_is_lost() -> String:
	var main: Node = _melting()
	if main == null:
		return "the fixture level was rejected"
	_ticks(main, FIRE_FALL_TICKS + 1)
	var session: LocalSession = _session(main)
	var during: int = _fires(main).marker_count()
	session.sim.reactor.meltdown_ticks_left = 1
	_ticks(main, 3)
	var outcome: ExitRule.Outcome = session.sim.outcome()
	var after: int = _fires(main).marker_count()
	main.free()
	if during != 1:
		return "%d fire markers during the meltdown, want 1" % during
	if outcome != ExitRule.Outcome.LOST:
		return "the run did not end lost"
	if after != 0:
		return "%d fire markers after the loss" % after
	return ""


func test_a_level_without_fire_marks_none() -> String:
	var main: Node = _melting(LevelSwitch.path_for("g2"))
	if main == null:
		return "g2 was rejected"
	_ticks(main, 60)  # G2's short meltdown ends the run soon after.
	var route: bool = _map(main).route_wiring.route != null
	var count: int = _fires(main).marker_count()
	main.free()
	if not route:
		return "no route during g2's meltdown"
	if count != 0:
		return "g2 without fire shows %d fire markers" % count
	return ""


func test_burning_fires_reads_only_burning_fire_entries() -> String:
	var debris: MeltdownDebris = MeltdownDebris.parse([
		{"position": [0.0, 0.0, 0.0], "radius": 1.0, "after_seconds": 1.0},
		{"position": [5.0, 0.0, 0.0], "radius": 2.0, "after_seconds": 1.0, "kind": "fire",
			"damage_per_second": 10.0},
		{"position": [9.0, 0.0, 0.0], "radius": 3.0, "after_seconds": 5.0, "kind": "fire",
			"damage_per_second": 10.0}])
	if debris.error != "":
		return "the debris did not parse: %s" % debris.error
	var none: Array = MeltdownWiring.burning_fires(SessionSnapshots.debris(debris))
	if (none[0] as PackedVector3Array).size() != 0:
		return "fires burn before the meltdown's clock starts"
	debris.elapsed_ticks = 60
	var fires: Array = MeltdownWiring.burning_fires(SessionSnapshots.debris(debris))
	var centres: PackedVector3Array = fires[0]
	var radii: PackedFloat32Array = fires[1]
	if centres != PackedVector3Array([Vector3(5.0, 0.0, 0.0)]) or radii != PackedFloat32Array([2.0]):
		return "burning fires are %s with radii %s" % [centres, radii]
	var empty: Array = MeltdownWiring.burning_fires(SessionSnapshots.debris(null))
	if (empty[0] as PackedVector3Array).size() != 0 or (empty[1] as PackedFloat32Array).size() != 0:
		return "no debris gives fires"
	return ""


func test_the_state_hash_is_the_same_without_the_map() -> String:
	var hashes: Array[int] = []
	var marked: Array[bool] = []
	for with_map: bool in [true, false]:
		var main: Node = _main(FIXTURE)
		if main == null:
			return "the fixture level was rejected"
		if not with_map:
			main.set("map", NoWiring.new())
		var session: LocalSession = _session(main)
		main.call("advance_frame", 0.0)
		_ticks(main, 1)
		var walls: BoxUnion = session.replay.walls()
		var box: int = _box_holding(walls, session.sim.reactor.position())
		if box >= 0:
			session.sim.ships[0].position = (walls.boxes[box].min_corner + walls.boxes[box].max_corner) / 2.0
			session.sim.ships[0].velocity = Vector3.ZERO
		session.sim.reactor.apply_damage(session.sim.reactor.hull)
		_ticks(main, FIRE_FALL_TICKS + 30)
		hashes.append(session.sim.state_hash())
		var hologram: MapHologram = _map(main).hologram
		marked.append(hologram != null and hologram.fires().marker_count() == 1)
		main.free()
	if marked != [true, false]:
		return "fire was marked %s, expected [true, false]" % [marked]
	if hashes[0] != hashes[1]:
		return "the state hash is %d with the map and %d without" % [hashes[0], hashes[1]]
	return ""
