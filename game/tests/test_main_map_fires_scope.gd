extends RefCounted

## Burning fire on the main scene's hand-held map (#520, #562, MAP-2, RUN-4,
## ARC-3, MP-2): a fire in unexplored space is not marked, a level without fire
## marks nothing, only burning fire entries are read, and the run's state hash
## is the same with or without the map. The fixtures are
## `test_main_map_fires_markers.gd`'s.

const Markers := preload("res://tests/test_main_map_fires_markers.gd")
const FIXTURE: String = Markers.FIXTURE
const FIRE: int = Markers.FIRE
const FIRE_FALL_TICKS: int = Markers.FIRE_FALL_TICKS


## The map wiring with its frame work switched off, for the run without it.
class NoWiring:
	extends MapWiring

	func update(_session: LocalSession, _delta_seconds: float, _shared: ClickHold = null) -> void:
		pass


func test_a_fire_in_unexplored_space_is_not_marked() -> String:
	var main: Node = Markers.melting(FIXTURE, false)
	if main == null:
		return "the fixture level was rejected"
	var fire_box: int = Markers.box_holding(Markers.session_of(main).replay.walls(),
		Markers.session_of(main).sim.debris.position(FIRE))
	if fire_box < 0 or Markers.map_of(main).explored.explored().has(fire_box):
		main.free()
		return "the fire is in box %d, which must exist and be unexplored" % fire_box
	Markers.advance_ticks(main, FIRE_FALL_TICKS + 1)
	var burning: bool = Markers.session_of(main).sim.debris.is_burning(FIRE)
	var count: int = Markers.fires_of(main).marker_count()
	main.free()
	if not burning:
		return "the fire has not caught"
	if count != 0:
		return "%d fire markers for a fire in unexplored space, want 0" % count
	return ""


func test_a_level_without_fire_marks_none() -> String:
	var main: Node = Markers.melting(LevelSwitch.path_for("g2"))
	if main == null:
		return "g2 was rejected"
	Markers.advance_ticks(main, 60)  # G2's short meltdown ends the run soon after.
	var route: bool = Markers.map_of(main).route_wiring.route != null
	var count: int = Markers.fires_of(main).marker_count()
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
		var main: Node = Markers.main_scene(FIXTURE)
		if main == null:
			return "the fixture level was rejected"
		if not with_map:
			main.set("map", NoWiring.new())
		var session: LocalSession = Markers.session_of(main)
		main.call("advance_frame", 0.0)
		Markers.advance_ticks(main, 1)
		var walls: BoxUnion = session.replay.walls()
		var box: int = Markers.box_holding(walls, session.sim.reactor.position())
		if box >= 0:
			session.sim.ships[0].position = (walls.boxes[box].min_corner + walls.boxes[box].max_corner) / 2.0
			session.sim.ships[0].velocity = Vector3.ZERO
		session.sim.reactor.apply_damage(session.sim.reactor.hull)
		if with_map:
			Markers.explore_fire_box(main)
		Markers.advance_ticks(main, FIRE_FALL_TICKS + 30)
		hashes.append(session.sim.state_hash())
		var hologram: MapHologram = Markers.map_of(main).hologram
		marked.append(hologram != null and hologram.fires().marker_count() == 1)
		main.free()
	if marked != [true, false]:
		return "fire was marked %s, expected [true, false]" % [marked]
	if hashes[0] != hashes[1]:
		return "the state hash is %d with the map and %d without" % [hashes[0], hashes[1]]
	return ""
