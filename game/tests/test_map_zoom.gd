extends RefCounted

## Zooming the map hologram (#549, MAP-1, ARC-3, ARC-4, CMF-6): `MapZoom`
## moves exponentially at `zoom_per_second`, clamps to the look's limits and
## resets to 1.0; the look file's zoom keys are optional and validated;
## `MapHologram.set_zoom` scales positions about the hand anchor, keeps the
## fire marker's floor at `min_zoom` and survives `build`; and zooming leaves
## the simulation's state hash unchanged.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const ZOOM_SOURCE: String = "res://xr/map_zoom.gd"
const EPSILON: float = 1e-4
const FRAME: float = 1.0 / 90.0
const OLD_LOOK: String = '{"line_color": [0.3, 0.85, 1.0], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1.0, 0.6, 0.15], "marker_radius_m": 0.008}'
## Classes the zoom must never name: simulation state, the session and comfort.
const FORBIDDEN: Array[String] = [
	"Sim", "ShipState", "LocalSession", "LatestInputSource", "ComfortWiring",
	"ComfortPreset", "ComfortPresetFiles", "ComfortInputFilter",
]


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


## `OLD_LOOK` with `extra` keys added, as JSON text.
func _look_with(extra: Dictionary) -> String:
	var data: Dictionary = JSON.parse_string(OLD_LOOK)
	data.merge(extra, true)
	return JSON.stringify(data)


func test_zoom_starts_at_one_and_moves_exponentially_at_the_rate() -> String:
	var zoom: MapZoom = MapZoom.new()
	if absf(zoom.factor - 1.0) > EPSILON:
		return "a new zoom is %s, want 1.0" % zoom.factor
	# Ninety frames of 1/90 s are one second: 1.0 * 1.5.
	for i: int in 90:
		zoom.change(1.0, FRAME)
	if absf(zoom.factor - 1.5) > EPSILON:
		return "one second zooming in gave %s, want 1.5" % zoom.factor
	zoom.change(-1.0, 1.0)
	if absf(zoom.factor - 1.0) > EPSILON:
		return "one second zooming out from 1.5 gave %s, want 1.0" % zoom.factor
	zoom.change(0.5, 2.0)
	if absf(zoom.factor - 1.5) > EPSILON:
		return "half tilt for two seconds gave %s, want 1.5" % zoom.factor
	return ""


func test_zoom_clamps_to_the_limits_and_full_tilt() -> String:
	var zoom: MapZoom = MapZoom.new()
	zoom.change(1.0, 60.0)
	if absf(zoom.factor - 3.0) > EPSILON:
		return "a minute zooming in gave %s, want max_zoom 3.0" % zoom.factor
	zoom.change(-1.0, 60.0)
	if absf(zoom.factor - 0.5) > EPSILON:
		return "a minute zooming out gave %s, want min_zoom 0.5" % zoom.factor
	zoom.reset()
	zoom.change(5.0, 1.0)
	if absf(zoom.factor - 1.5) > EPSILON:
		return "direction 5 for a second gave %s, want full rate 1.5" % zoom.factor
	zoom.change(1.0, -1.0)
	if absf(zoom.factor - 1.5) > EPSILON:
		return "a negative frame time moved the zoom to %s" % zoom.factor
	return ""


func test_reset_returns_to_one() -> String:
	var zoom: MapZoom = MapZoom.new()
	zoom.change(1.0, 1.7)
	zoom.reset()
	if absf(zoom.factor - 1.0) > EPSILON:
		return "reset left %s, want 1.0" % zoom.factor
	return ""


func test_zoom_takes_limits_and_rate_from_the_look() -> String:
	var look: Dictionary = MapLook.parse(_look_with({"min_zoom": 0.25, "max_zoom": 2.0, "zoom_per_second": 2.0}))
	if look.has("error"):
		return "a valid zoom look was rejected: %s" % look["error"]
	var zoom: MapZoom = MapZoom.new()
	zoom.change(1.0, 1.0)
	zoom.use_look(look)
	if absf(zoom.factor - 1.5) > EPSILON:
		return "use_look moved a zoom inside the new limits to %s" % zoom.factor
	zoom.change(1.0, 10.0)
	if absf(zoom.factor - 2.0) > EPSILON:
		return "max_zoom 2 gave %s" % zoom.factor
	zoom.reset()
	zoom.change(-1.0, 1.0)
	if absf(zoom.factor - 0.5) > EPSILON:
		return "zoom_per_second 2 for a second out gave %s, want 0.5" % zoom.factor
	zoom.change(-1.0, 10.0)
	if absf(zoom.factor - 0.25) > EPSILON:
		return "min_zoom 0.25 gave %s" % zoom.factor
	return ""


func test_the_zoom_keys_are_optional_and_the_file_sets_them() -> String:
	var old: Dictionary = MapLook.parse(OLD_LOOK)
	if old.has("error"):
		return "a look file without zoom keys was rejected: %s" % old["error"]
	for key: String in ["min_zoom", "max_zoom", "zoom_per_second"]:
		if old[key] != MapLook.FALLBACK[key]:
			return "a file without %s gave %s, want the built-in %s" % [key, old[key], MapLook.FALLBACK[key]]
	var file: Dictionary = MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	if file.has("error"):
		return "map_look.json rejected: %s" % file["error"]
	if [file["min_zoom"], file["max_zoom"], file["zoom_per_second"]] != [0.5, 3.0, 1.5]:
		return "map_look.json zoom keys are %s" % [[file["min_zoom"], file["max_zoom"], file["zoom_per_second"]]]
	return ""


func test_bad_or_crossed_zoom_keys_are_reported_not_used() -> String:
	var cases: Array[Dictionary] = [
		{"min_zoom": "half"},
		{"min_zoom": true},
		{"max_zoom": 20.0},
		{"min_zoom": 0.05},
		{"zoom_per_second": 1.0},
		{"zoom_per_second": 11.0},
		{"min_zoom": 0.8, "max_zoom": 0.6},
		{"min_zoom": 1.0, "max_zoom": 1.0},
		{"min_zoom": 1.5, "max_zoom": 3.0},
		{"min_zoom": 0.2, "max_zoom": 0.8},
	]
	for extra: Dictionary in cases:
		var parsed: Dictionary = MapLook.parse(_look_with(extra))
		if not parsed.has("error"):
			return "%s was accepted" % [extra]
		var named: bool = false
		for key: String in extra:
			named = named or (parsed["error"] as String).contains(key)
		if not named:
			return "%s was rejected without naming the key: %s" % [extra, parsed["error"]]
	return ""


func test_set_zoom_scales_positions_about_the_hand_anchor() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0, 1])
	var start: Vector3 = level.start_position()
	var exit_at: Vector3 = start + Vector3(1.0, 0.0, -2.0)
	var reactor_at: Vector3 = start + Vector3(0.0, -3.0, -20.0)
	var fire_at: Vector3 = start + Vector3(0.0, 1.0, -5.0)
	map.set_ship_position(start)
	map.set_markers(exit_at, reactor_at, true)
	map.show_fires(PackedVector3Array([fire_at]), PackedFloat32Array([0.5]))
	var before: Array[Vector3] = [map.marker_position(), map.exit_marker_position(),
			map.reactor_marker_position(), map.fires().marker_positions()[0]]
	map.set_zoom(2.0)
	var after: Array[Vector3] = [map.marker_position(), map.exit_marker_position(),
			map.reactor_marker_position(), map.fires().marker_positions()[0]]
	var lines_scale: Vector3 = map.get_node(MapHologram.LINES_NAME).scale
	var zoomed: float = map.zoom()
	map.free()
	if absf(zoomed - 2.0) > EPSILON:
		return "zoom() is %s after set_zoom(2)" % zoomed
	if lines_scale.distance_to(Vector3.ONE * 2.0) > EPSILON:
		return "the lines are scaled %s, want 2" % lines_scale
	# Scaling about the origin is the anchor staying put: every point moves
	# straight away from it by the factor, so the point at the origin stays.
	for i: int in before.size():
		if after[i].distance_to(before[i] * 2.0) > EPSILON:
			return "marker %d moved from %s to %s, want %s" % [i, before[i], after[i], before[i] * 2.0]
	return ""


func test_the_held_point_stays_in_the_hand() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	var fit: Transform3D = MapHologram.fit_transform(MapWireframe.segments(level.union, [0]), float(map.look()["size_m"]))
	# The level point the fit puts at the hologram's origin, the hand anchor.
	var held: Vector3 = fit.affine_inverse() * Vector3.ZERO
	var seen: Array[Vector3] = []
	for factor: float in [0.5, 1.0, 2.0, 3.0]:
		map.set_zoom(factor)
		map.set_ship_position(held)
		seen.append(map.marker_position())
	map.free()
	for at: Vector3 in seen:
		if at.length() > EPSILON:
			return "the held point drifted to %s while zooming" % at
	return ""


func test_set_zoom_clamps_and_build_keeps_it() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	map.set_zoom(100.0)
	var high: float = map.zoom()
	map.set_zoom(0.01)
	var low: float = map.zoom()
	map.set_zoom(2.0)
	map.set_markers(level.start_position() + Vector3(1.0, 0.0, 0.0), level.start_position(), false)
	map.build(level.union, [0, 1])
	var kept: float = map.zoom()
	var fit: Transform3D = MapHologram.fit_transform(MapWireframe.segments(level.union, [0, 1]), float(map.look()["size_m"]))
	var want: Vector3 = (fit * (level.start_position() + Vector3(1.0, 0.0, 0.0))) * 2.0
	var exit: Vector3 = map.exit_marker_position()
	map.free()
	if absf(high - 3.0) > EPSILON or absf(low - 0.5) > EPSILON:
		return "set_zoom clamped to %s and %s, want 3.0 and 0.5" % [high, low]
	if absf(kept - 2.0) > EPSILON:
		return "build changed the zoom to %s" % kept
	if exit.distance_to(want) > EPSILON:
		return "after build the exit is at %s, want the zoomed fit %s" % [exit, want]
	return ""


func test_the_fire_marker_floor_holds_at_min_zoom() -> String:
	var level: LevelDef = _level()
	var map: MapHologram = MapHologram.new()
	map.build(level.union, [0])
	var least: float = float(map.look()["fire_size_m"])
	map.show_fires(PackedVector3Array([level.start_position()]), PackedFloat32Array([0.0]))
	map.set_zoom(float(map.look()["min_zoom"]))
	var sizes: PackedFloat32Array = map.fires().marker_sizes()
	map.free()
	if sizes.size() != 1 or sizes[0] < least - 1e-6:
		return "at min_zoom the fire spans %s, want at least fire_size_m %s" % [sizes, least]
	return ""


func test_the_zoom_names_no_simulation_or_comfort_class() -> String:
	var source: String = FileAccess.get_file_as_string(ZOOM_SOURCE)
	for name: String in FORBIDDEN:
		var pattern: RegEx = RegEx.create_from_string("\\b%s\\b" % name)
		if pattern.search(source) != null:
			return "map_zoom.gd names %s" % name
	return ""


func test_zooming_leaves_the_state_hash_unchanged() -> String:
	var hashes: Array[int] = []
	var zooms: Array[float] = []
	for with_zoom: bool in [true, false]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		main.get_node("XRRig").call("build")
		main.call("use_level", LevelSwitch.path_for("g2"))
		main.call("_ready")
		var input: ShipInput = ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE))
		(main.get("input_source") as LatestInputSource).set_input(input)
		var zoom: MapZoom = MapZoom.new()
		for frame: int in 240:
			if with_zoom:
				var hologram: MapHologram = (main.get("map") as MapWiring).hologram
				hologram.set_zoom(zoom.change(1.0 if frame < 160 else -1.0, FRAME))
			main.call("advance_frame", FRAME)
		var session: LocalSession = main.get("session")
		hashes.append(session.sim.state_hash())
		zooms.append(zoom.factor)
		main.free()
	if absf(zooms[0] - 1.0) < 0.1:
		return "the zoomed run never zoomed (ended at %s)" % zooms[0]
	if hashes[0] != hashes[1]:
		return "the state hash is %d after zooming and %d without" % [hashes[0], hashes[1]]
	return ""
