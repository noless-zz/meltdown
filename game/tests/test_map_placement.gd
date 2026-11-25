extends RefCounted

## Where the map goes for each choice (#1321, MAP-1, MAP-2, CMF-6): in the
## hand as before, or at the cockpit file's spot on the side away from the
## panel; turned with the ship or not; clear of the panel and inside the window
## for every corner, place, turn and preset (preset 1's reduced view
## included); kept through a preset change; and never touching the simulation.

const CHECK: GDScript = preload("res://acceptance/checks/map_places_check.gd")
const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const FRAME: float = 1.0 / 72.0


static func _restore() -> void:
	MapChoice.current_place = MapChoice.PLACE_HAND
	MapChoice.current_turn = MapChoice.TURN_FIXED
	PanelCorner.current = PanelCorner.CENTRE


static func _spec(number: int) -> CockpitSpec:
	return CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))


## A rig with both hands and the cockpit of preset `number`, and a map wiring attached to it.
static func _scene(number: int) -> Array:
	var rig: Node3D = (load(RIG_SCENE) as PackedScene).instantiate() as Node3D
	rig.add_child(CockpitFrame.new(_spec(number)))
	var map: MapWiring = MapWiring.new()
	map.attach(rig, ThumbstickMapping.new())
	return [rig, map]


func test_every_shipped_cockpit_names_a_spot() -> String:
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		var spec: CockpitSpec = _spec(number)
		if spec.error != "":
			return "preset %d: %s" % [number, spec.error]
		var text: String = FileAccess.get_file_as_string(ComfortPresetFiles.load_number(number).cockpit_file)
		if not text.contains("\"%s\"" % CockpitMapMount.KEY):
			return "preset %d's cockpit file has no %s" % [number, CockpitMapMount.KEY]
	return ""


func test_a_bad_mount_is_rejected_naming_the_field() -> String:
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://xr/cockpits/anchored.json"))
	var cases: Dictionary = {
		"map_mount has unknown key": {"yaw_deg": 27, "pitch_deg": -10, "distance_m": 0.4, "size_m": 0.075, "roll_deg": 1},
		"map_mount.size_m is missing": {"yaw_deg": 26, "pitch_deg": -10, "distance_m": 0.4},
		"map_mount.distance_m is 2": {"yaw_deg": 26, "pitch_deg": -10, "distance_m": 2, "size_m": 0.08},
		"map_mount.yaw_deg must be a number": {"yaw_deg": true, "pitch_deg": -10, "distance_m": 0.4, "size_m": 0.08},
	}
	for want: String in cases:
		var data: Dictionary = base.duplicate(true)
		data[CockpitMapMount.KEY] = cases[want]
		var spec: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(data))
		if not spec.error.contains(want):
			return "want an error with \"%s\", got \"%s\"" % [want, spec.error]
	base.erase(CockpitMapMount.KEY)
	var without: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(base))
	if without.error != "" or without.map_mount.size_m != float(CockpitMapMount.FALLBACK["size_m"]):
		return "a file without a mount gave %s, error \"%s\"" % [without.map_mount.size_m, without.error]
	return ""


func test_the_spot_mirrors_away_from_a_panel_on_the_right() -> String:
	var mount: CockpitMapMount = CockpitMapMount.new()
	for corner: String in PanelCorner.names():
		var at: Vector3 = mount.spot(corner)
		var right: bool = CockpitMapMount.RIGHT_CORNERS.has(corner)
		if (at.x < 0.0) != right or at.z >= 0.0 or not is_equal_approx(at.length(), mount.distance_m):
			return "panel %s puts the map at %s" % [corner, at]
	return ""


func test_each_combination_places_the_map_where_the_data_says() -> String:
	var scene: Array = _scene(2)
	var rig: Node3D = scene[0]
	var map: MapWiring = scene[1]
	var problem: String = ""
	var frame: CockpitFrame = MapPlacement.cockpit_frame(rig)
	for corner: String in PanelCorner.names():
		for place: String in MapChoice.PLACES:
			MapChoice.current_place = place
			PanelCorner.current = corner
			map.follow_choice()
			var parent: Node = map.hologram.get_parent()
			if place == MapChoice.PLACE_HAND and (parent == null or parent.name != "LeftHand"
					or map.hologram.position != MapHologram.HAND_OFFSET or map.hologram.mount_scale() != 1.0):
				problem = "hand, %s: under %s at %s" % [corner, parent, map.hologram.position]
			var want: Vector3 = frame.spec.map_mount.spot(corner)
			if place == MapChoice.PLACE_COCKPIT and (parent != frame or not map.hologram.position.is_equal_approx(want)
					or not is_equal_approx(map.hologram.mount_scale(),
					frame.spec.map_mount.size_m / float(map.hologram.look()["size_m"]))):
				problem = "cockpit, %s: under %s at %s, want %s" % [corner, parent, map.hologram.position, want]
			if problem != "":
				break
		if problem != "":
			break
	rig.free()
	_restore()
	return problem


func test_a_map_that_follows_the_ship_points_the_ship_ahead() -> String:
	var map: MapHologram = MapHologram.new()
	var ship: Basis = Basis(Vector3.UP, 1.2) * Basis(Vector3.RIGHT, 0.4)
	map.set_ship_orientation(ship)
	var fixed: Basis = map.basis
	map.set_follows_ship(true)
	var follows: Basis = map.basis * ship
	map.free()
	if not fixed.is_equal_approx(Basis.IDENTITY):
		return "a fixed map is turned %s" % fixed
	if not follows.is_equal_approx(Basis.IDENTITY):
		return "a following map leaves the ship turned %s" % follows
	return ""


func test_map_and_panel_never_overlap_in_any_combination() -> String:
	var checked: int = 0
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		var spec: CockpitSpec = _spec(number)
		for corner: String in PanelCorner.names():
			var problem: String = MapPanelClearance.mount_problem(spec, corner)
			if problem != "":
				return "preset %d, panel %s: %s" % [number, corner, problem]
			checked += 1
	return "" if checked == 20 else "checked %d combinations, want 20" % checked


func test_the_live_check_passes_every_combination_and_puts_things_back() -> String:
	var scene: Array = _scene(1)
	var rig: Node3D = scene[0]
	var map: MapWiring = scene[1]
	var measurements: Dictionary = {}
	var verdict: Array = CHECK.judge_map(map, rig, measurements)
	var after: Array = [MapChoice.current_place, MapChoice.current_turn, PanelCorner.current,
		str(map.hologram.get_parent().name)]
	rig.free()
	_restore()
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "the check said %s" % [verdict]
	# 4 presets x 5 corners x 2 places x 2 turns.
	if int(measurements.get("map_place_cases", 0)) != 80:
		return "the check ran %s cases" % measurements.get("map_place_cases")
	if after != [MapChoice.PLACE_HAND, MapChoice.TURN_FIXED, PanelCorner.CENTRE, "LeftHand"]:
		return "the check left %s" % [after]
	return ""


func test_the_check_fails_a_mount_over_the_panel() -> String:
	var spec: CockpitSpec = _spec(4)  # The widest window, so only the panel is in the way.
	spec.map_mount.yaw_deg = 0.0
	spec.map_mount.pitch_deg = -19.0
	var over: String = MapPanelClearance.mount_problem(spec, PanelCorner.CENTRE)
	spec = _spec(1)
	spec.map_mount.yaw_deg = 60.0
	spec.map_mount.pitch_deg = 0.0
	var outside: String = MapPanelClearance.mount_problem(spec, PanelCorner.CENTRE)
	if not over.contains("overlaps the panel"):
		return "a map on the centre panel gave \"%s\"" % over
	if not outside.contains("leaves the"):
		return "a map outside preset 1's window gave \"%s\"" % outside
	return ""


func test_a_preset_change_keeps_the_mounted_map() -> String:
	var scene: Array = _scene(1)
	var rig: Node3D = scene[0]
	var map: MapWiring = scene[1]
	MapChoice.current_place = MapChoice.PLACE_COCKPIT
	map.follow_choice()
	var frame: CockpitFrame = MapPlacement.cockpit_frame(rig)
	frame.set_spec(_spec(3))
	var kept: bool = is_instance_valid(map.hologram) and map.hologram.get_parent() == frame
	var parts: int = frame.instance_count("Solid")
	rig.free()
	_restore()
	if not kept:
		return "the map did not survive the frame's rebuild"
	return "" if parts > 0 else "the frame was not rebuilt"


func test_changing_the_map_choice_leaves_the_simulation_alone() -> String:
	var hashes: Array[int] = []
	var mounted: bool = false
	for change: bool in [false, true]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		main.call("attach_cockpit_frame")
		var map: MapWiring = main.get("map")
		map.attach(main.get_node("XRRig"), ThumbstickMapping.new())
		for frame: int in 60:
			if change and frame == 20:
				MapChoice.current_place = MapChoice.PLACE_COCKPIT
				MapChoice.current_turn = MapChoice.TURN_FOLLOWS
			var values: Dictionary = ControllerSampler.idle_values()
			values["buttons"] = {"right_button_lower": frame < 30, "left_stick_click": frame == 25}
			main.call("apply_controls", values)
			main.call("advance_frame", FRAME)
		if change:
			mounted = map.hologram.get_parent() is CockpitFrame and map.hologram.follows_ship()
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		main.free()
		_restore()
	if not mounted:
		return "the map did not move to the cockpit"
	if hashes[0] != hashes[1]:
		return "the map choice changed the simulation: %s" % [hashes]
	return ""
