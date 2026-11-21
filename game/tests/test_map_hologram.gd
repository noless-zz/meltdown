extends RefCounted

## The map hologram held in the hand (#314, MAP-1, CMF-6, ARC-3): hidden until
## `show_map` is pressed, open until the next press (#914), one line segment
## per `MapWireframe` segment, the ship marker fitted like the lines, a broken
## look file falls back, and nothing it does reaches the simulation or comfort.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const SCRATCH_PATH: String = "user://test_map_look.json"
const EPSILON: float = 1e-4
## Classes the hologram must never name: simulation state, the session and
## comfort settings.
const FORBIDDEN: Array[String] = [
	"Sim", "ShipState", "LocalSession", "LatestInputSource", "ComfortWiring",
	"ComfortPreset", "ComfortPresetFiles", "ComfortInputFilter",
]


func _g2() -> BoxUnion:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE)).union


func _one_box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	return BoxUnion.new(boxes)


func _all(union: BoxUnion) -> Array[int]:
	var indices: Array[int] = []
	for i: int in union.boxes.size():
		indices.append(i)
	return indices


## Feeds `pattern` to `press`, one frame each; returns `visible` after each.
func _frames(map: MapHologram, pattern: Array[bool]) -> Array[bool]:
	var seen: Array[bool] = []
	for pressed: bool in pattern:
		map.press(pressed)
		seen.append(map.visible)
	return seen


func test_hidden_by_default() -> String:
	var map: MapHologram = MapHologram.new()
	var shown: bool = map.visible
	map.free()
	return "the map starts shown" if shown else ""


func test_a_press_opens_it_and_the_next_closes_it() -> String:
	var map: MapHologram = MapHologram.new()
	map.build(_one_box(), [0])
	var seen: Array[bool] = _frames(map, [true, true, true, false, false, true, false, true])
	map.close()
	var closed: bool = map.visible
	map.free()
	if seen != [true, true, true, true, true, false, false, true]:
		return "presses gave %s" % str(seen)
	if closed:
		return "close left it open"
	return ""


func test_show_map_is_read_through_the_layout() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var map: MapHologram = MapHologram.new()
	map.read(mapping, {"left_stick_click": true})
	var right_handed: bool = map.visible
	map.read(mapping, {})
	var released: bool = map.visible
	map.close()
	mapping.left_handed = true
	map.read(mapping, {"left_stick_click": true})
	map.read(mapping, {})
	var wrong_hand: bool = map.visible
	map.read(mapping, {"right_stick_click": true})
	var left_handed: bool = map.visible
	map.free()
	if not right_handed or not released:
		return "right-handed: pressed %s, released %s" % [right_handed, released]
	if wrong_hand or not left_handed:
		return "left-handed: left click %s, right click %s" % [wrong_hand, left_handed]
	return ""


func test_a_remapped_show_map_follows_the_layout_file() -> String:
	var text: String = FileAccess.get_file_as_string(ThumbstickMapping.DEFAULT_LAYOUT_FILE)
	text = text.replace('"show_map": {"left_stick_click": 1.0}', '"show_map": {"left_button_upper": 1.0}')
	var mapping: ThumbstickMapping = ThumbstickMapping.from_json(text)
	if mapping.error != "":
		return "remapped file rejected: %s" % mapping.error
	if mapping.action_held("show_map", {"left_stick_click": true}):
		return "the old control still shows the map"
	if not mapping.action_held("show_map", {"left_button_upper": true}):
		return "the new control does not show the map"
	return ""


func test_segment_count_equals_the_wireframe() -> String:
	var union: BoxUnion = _g2()
	var first: Array[int] = [0]
	var none: Array[int] = []
	var explored_sets: Array[Array] = [_all(union), first, none]
	for set_index: int in explored_sets.size():
		var explored: Array[int] = []
		explored.assign(explored_sets[set_index])
		var map: MapHologram = MapHologram.new()
		map.build(union, explored)
		var drawn: int = map.segment_count()
		map.free()
		var want: int = MapWireframe.segments(union, explored).size() / 2
		if drawn != want:
			return "explored %s: %d segments drawn, wireframe has %d" % [explored, drawn, want]
	return ""


func test_the_map_fits_its_size() -> String:
	var map: MapHologram = MapHologram.new()
	map.build(_one_box(), [0])
	var mesh: ArrayMesh = (map.get_node(MapHologram.LINES_NAME) as MeshInstance3D).mesh as ArrayMesh
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var size: float = float(map.look()["size_m"])
	map.free()
	var high: Vector3 = Vector3.ZERO
	for point: Vector3 in points:
		high = high.max(point.abs())
	# The box is 4 by 6 by 8 m: its 8 m side becomes `size_m`.
	if not is_equal_approx(high.z * 2.0, size) or not is_equal_approx(high.x * 2.0, size * 0.5):
		return "half extents %s for size %s" % [high, size]
	return ""


func test_the_ship_marker_sits_at_the_fitted_ship_position() -> String:
	var map: MapHologram = MapHologram.new()
	map.build(_one_box(), [0])
	var size: float = float(map.look()["size_m"])
	map.set_ship_position(Vector3.ZERO)
	var centre: Vector3 = map.marker_position()
	var corner: Vector3 = Vector3(2, -3, 4)
	map.set_ship_position(corner)
	var at_corner: Vector3 = map.marker_position()
	map.free()
	var fitted: PackedVector3Array = MapWireframe.fit_to_cube(MapWireframe.segments(_one_box(), [0]), size)
	var raw: PackedVector3Array = MapWireframe.segments(_one_box(), [0])
	var want: Vector3 = Vector3.INF
	for i: int in raw.size():
		if raw[i].is_equal_approx(corner):
			want = fitted[i]
	if centre.length() > EPSILON:
		return "ship at the box centre gave marker %s, want the origin" % centre
	if want == Vector3.INF or at_corner.distance_to(want) > EPSILON:
		return "ship on a corner gave marker %s, the fitted corner is %s" % [at_corner, want]
	return ""


func test_the_look_file_loads() -> String:
	var map: MapHologram = MapHologram.new()
	var error: String = map.look_error
	var look: Dictionary = map.look()
	map.free()
	if error != "":
		return "map_look.json rejected: %s" % error
	if look != MapLook.parse(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE)):
		return "the loaded look is not the file's"
	return ""


func test_a_broken_look_file_falls_back_and_names_the_field() -> String:
	var cases: Dictionary = {
		'{"line_color": [0.3, 0.85], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1, 0.6, 0.15], "marker_radius_m": 0.008}': "line_color",
		'{"line_color": [0.3, 0.85, 1], "line_energy": 1.5, "size_m": 3, "marker_color": [1, 0.6, 0.15], "marker_radius_m": 0.008}': "size_m",
		'{"line_color": [0.3, 0.85, 1], "line_energy": true, "size_m": 0.25, "marker_color": [1, 0.6, 0.15], "marker_radius_m": 0.008}': "line_energy",
		'{"line_color": [0.3, 0.85, 1], "line_energy": 1.5, "size_m": 0.25, "marker_color": [1, 0.6, 0.15]}': "marker_radius_m",
		'{"line_colour": [0.3, 0.85, 1]}': "line_colour",
	}
	for text: String in cases:
		var file: FileAccess = FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var map: MapHologram = MapHologram.new()
		var error: String = map.load_look(SCRATCH_PATH)
		var look: Dictionary = map.look()
		map.build(_one_box(), [0])
		var drawn: int = map.segment_count()
		map.free()
		if error.find(str(cases[text])) < 0:
			return "error '%s' does not name %s" % [error, cases[text]]
		if look != MapHologram.FALLBACK_LOOK:
			return "a rejected file did not leave the built-in look"
		if drawn != 12:
			return "the fallback look drew %d segments" % drawn
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))
	return ""


func test_it_hangs_in_the_hand_that_clicks() -> String:
	var scene: PackedScene = load(RIG_SCENE) as PackedScene
	if scene == null:
		return "%s did not load" % RIG_SCENE
	var rig: Node = scene.instantiate()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var map: MapHologram = MapHologram.new()
	var attached: bool = map.attach_to(rig, mapping)
	var right_handed: String = str(map.get_parent().name) if map.get_parent() != null else ""
	var offset: Vector3 = map.position
	mapping.left_handed = true
	map.attach_to(rig, mapping)
	var left_handed: String = str(map.get_parent().name) if map.get_parent() != null else ""
	var follows: bool = not map.top_level
	rig.free()
	if not attached or right_handed != "LeftHand":
		return "right-handed map hangs under '%s'" % right_handed
	if left_handed != "RightHand":
		return "left-handed map hangs under '%s'" % left_handed
	if not offset.is_equal_approx(MapHologram.HAND_OFFSET):
		return "offset %s, want %s" % [offset, MapHologram.HAND_OFFSET]
	if not follows:
		return "top_level is set, so the map would not turn with the controller"
	return ""


## ARC-3, CMF-6: the hologram reads copies only and never names simulation,
## session or comfort classes, and using it leaves the mapping as it was.
func test_it_never_touches_simulation_or_comfort() -> String:
	var source: String = FileAccess.get_file_as_string("res://xr/map_hologram.gd")
	for class_id: String in FORBIDDEN:
		if RegEx.create_from_string("\\b%s\\b" % class_id).search(source) != null:
			return "map_hologram.gd names %s" % class_id
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var before: String = var_to_str([mapping.layout, mapping.left_handed, mapping.invert_pitch])
	var map: MapHologram = MapHologram.new()
	map.build(_g2(), _all(_g2()))
	for i: int in 40:
		map.read(mapping, {"left_stick_click": i % 10 < 3})
	map.set_ship_position(Vector3(1, 2, 3))
	map.free()
	if var_to_str([mapping.layout, mapping.left_handed, mapping.invert_pitch]) != before:
		return "using the map changed the mapping"
	return ""
