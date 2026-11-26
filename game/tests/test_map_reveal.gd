extends RefCounted

## The Surveyor's map reveal (#1393, CRW-1, CRW-3, ARC-3, ARC-4, MP-2): with
## `map_reveal` in the run's crew totals the held map draws every box of the
## level from the first frame, the unflown ones on a dimmer surface whose look
## is data; without it the map is as before; a flown box moves to the explored
## look; the run wiring hands the map a copy of the totals for the run's level
## only, and nothing is written back to the simulation.

const FRAME: float = 1.0 / 60.0
const RUN_SEED: int = 12345
const PROFILE_PATH: String = "user://test_map_reveal_profile.json"
## A start room, a corridor down -z and a far room, as in `test_wide_radar.gd`.
const LEVEL: String = '{"boxes": [' \
	+ '{"min": [-5.0, -5.0, -20.0], "max": [5.0, 5.0, 5.0]},' \
	+ '{"min": [-2.0, -2.0, -40.0], "max": [2.0, 2.0, -18.0]},' \
	+ '{"min": [-10.0, -10.0, -70.0], "max": [10.0, 10.0, -38.0]}],' \
	+ '"start": {"position": [4.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]}, "robots": []}'
const REVEAL: Dictionary = {"map_reveal": 1}


func _session() -> LocalSession:
	return LocalSession.for_level(LevelDef.parse_json(LEVEL))


## A wiring attached to a bare rig with `totals` as every session's crew
## totals, or with no crew callable when `totals` is null.
func _wiring(rig: Node3D, totals: Variant) -> MapWiring:
	var hand: Node3D = Node3D.new()
	hand.name = "LeftHand"
	rig.add_child(hand)
	var wiring: MapWiring = MapWiring.new()
	var crew: Callable = Callable() if totals == null else func(_s: LocalSession) -> Dictionary: return totals
	wiring.attach(rig, ThumbstickMapping.new(), crew)
	return wiring


func test_with_a_surveyor_every_box_is_drawn_from_the_first_frame() -> String:
	var rig: Node3D = Node3D.new()
	var wiring: MapWiring = _wiring(rig, REVEAL)
	wiring.update(_session(), FRAME)
	var result: Array = [wiring.revealed, wiring.start_boxes, wiring.explored.explored().size(),
		wiring.hologram.segment_count(), wiring.hologram.revealed_segment_count()]
	rig.free()
	if not result[0] or result[1] != 3:
		return "revealed %s, %d boxes drawn at the first frame, expected all 3" % [result[0], result[1]]
	if result[2] != 1 or result[3] == 0 or result[4] == 0:
		return "%d explored boxes, %d explored lines, %d dim lines" % [result[2], result[3], result[4]]
	return ""


func test_without_the_benefit_the_map_is_as_before() -> String:
	var counts: Array = []
	for totals: Variant in [null, {}, {"shield_max": 5}, {"map_reveal": 0}]:
		var rig: Node3D = Node3D.new()
		var wiring: MapWiring = _wiring(rig, totals)
		wiring.update(_session(), FRAME)
		counts.append([wiring.revealed, wiring.start_boxes, wiring.hologram.segment_count(),
			wiring.hologram.revealed_segment_count(), wiring.rebuilds])
		rig.free()
	for entry: Array in counts:
		if entry != counts[0] or entry[0] or entry[1] != 1 or entry[3] != 0:
			return "maps without the benefit differ: %s" % [counts]
	return ""


func test_a_flown_box_takes_the_explored_look_and_the_map_keeps_its_size() -> String:
	var rig: Node3D = Node3D.new()
	var wiring: MapWiring = _wiring(rig, REVEAL)
	var session: LocalSession = _session()
	wiring.update(session, FRAME)
	var lines_before: int = wiring.hologram.segment_count()
	var dim_before: int = wiring.hologram.revealed_segment_count()
	var exit_before: Vector3 = wiring.hologram.exit_marker_position()
	session.sim.ships[0].position = Vector3(0.0, 0.0, -30.0)  # In the corridor.
	session.reset_ship_snapshots()
	wiring.update(session, FRAME)
	var result: Array = [wiring.explored.explored(), wiring.hologram.segment_count(),
		wiring.hologram.revealed_segment_count(), wiring.hologram.exit_marker_position()]
	rig.free()
	if result[0] != ([0, 1] as Array[int]):
		return "explored %s after flying into the corridor" % [result[0]]
	if result[1] <= lines_before or result[2] >= dim_before or result[2] == 0:
		return "explored lines %d -> %d, dim lines %d -> %d" % [lines_before, result[1], dim_before, result[2]]
	if not (result[3] as Vector3).is_equal_approx(exit_before):
		return "the exit marker moved from %s to %s: the revealed map was refitted" % [exit_before, result[3]]
	return ""


func test_the_reveal_writes_nothing_to_the_simulation() -> String:
	var hashes: Array[int] = []
	for totals: Dictionary in [{}, REVEAL]:
		var rig: Node3D = Node3D.new()
		var wiring: MapWiring = _wiring(rig, totals)
		var session: LocalSession = _session()
		for frame: int in 30:
			session.advance(FRAME)
			wiring.update(session, FRAME)
		hashes.append(session.sim.state_hash())
		rig.free()
	if hashes[0] != hashes[1]:
		return "the session hash is %d without the reveal and %d with it" % [hashes[0], hashes[1]]
	return ""


func test_the_dim_look_is_data() -> String:
	var look: Dictionary = MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	if look.has("error"):
		return "the shipped look was rejected: %s" % look["error"]
	if float(look["unexplored_alpha"]) >= 1.0:
		return "unexplored lines are not see-through"
	var dim: Color = look["unexplored_color"]
	var bright: Color = look["line_color"]
	if dim.get_luminance() >= bright.get_luminance():
		return "unexplored lines %s are not dimmer than the lines %s" % [dim, bright]
	var material: StandardMaterial3D = MapShapes.dim(look)
	if not material.albedo_color.is_equal_approx(Color(dim.r, dim.g, dim.b, float(look["unexplored_alpha"]))):
		return "the dim material is %s" % material.albedo_color
	var base: String = '{"line_color": [1, 1, 1], "line_energy": 1, "size_m": 0.25, "marker_color": [1, 1, 1], "marker_radius_m": 0.01'
	var older: Dictionary = MapLook.parse(base + "}")
	if older.has("error") or older["unexplored_alpha"] != MapLook.FALLBACK["unexplored_alpha"]:
		return "a file without the unexplored keys did not keep the built-in ones: %s" % [older]
	for bad: String in [', "unexplored_alpha": 0.0}', ', "unexplored_alpha": 1.5}', ', "unexplored_color": [1, 1]}']:
		var rejected: Dictionary = MapLook.parse(base + bad)
		if not rejected.has("error") or String(rejected["error"]).find("unexplored_") < 0:
			return "%s was not rejected by name: %s" % [bad, rejected]
	return ""


func test_an_outline_of_revealed_boxes_only_still_draws() -> String:
	var mesh: ArrayMesh = MapShapes.outline(PackedVector3Array(), 0.25, MapLook.FALLBACK,
		PackedVector3Array([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)]))
	if MapShapes.segments_in(mesh, MapShapes.REVEALED_SURFACE) != 1 \
			or MapShapes.segments_in(mesh, MapShapes.EXPLORED_SURFACE) != 0:
		return "a revealed segment alone did not make one dim line"
	return ""


func _clean() -> void:
	for each: String in [PROFILE_PATH, SafeFileWrite.temp_path(PROFILE_PATH)]:
		if FileAccess.file_exists(each):
			DirAccess.remove_absolute(each)


func test_the_run_hands_the_map_a_copy_of_its_crew_totals_for_its_level_only() -> String:
	_clean()
	var level_start: LevelStart = LevelStart.new()
	level_start.run = RunWiring.new(RUN_SEED, ProfileStore.new(PROFILE_PATH), Callable(), "", false)
	level_start.run.ship.enabled = false
	level_start.run.profile.crew.append({Profile.CREW_ID: "crew-1", Profile.CREW_ROLE: "surveyor"})
	level_start.source = level_start.run.level_source()
	var world: Node3D = Node3D.new()
	var run_level: LocalSession = level_start.session_for(world, level_start.source, null)
	var handed: Dictionary = level_start.crew_totals_for(run_level)
	handed["map_reveal"] = 0
	var again: Dictionary = level_start.crew_totals_for(run_level)
	var alone: LocalSession = level_start.session_for(world, LevelSwitch.seed_source(31), null)
	var other: Dictionary = level_start.crew_totals_for(alone)
	var stale: Dictionary = level_start.crew_totals_for(run_level)
	world.free()
	_clean()
	if run_level == null or again != {"map_reveal": 1}:
		return "the run's level was handed %s" % [again]
	if not other.is_empty() or not stale.is_empty():
		return "a level the run does not fly was handed %s, the old session %s" % [other, stale]
	if not level_start.crew_totals_for(null).is_empty():
		return "no session was handed crew totals"
	return ""
