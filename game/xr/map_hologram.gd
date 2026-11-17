class_name MapHologram
extends Node3D

## The map of the explored mine as a small hologram held in the hand (MAP-1,
## #314): the `MapWireframe` outline of the explored boxes as one emissive line
## mesh, fitted into a cube of `size_m`, with a marker where the ship is.
##
## It hangs under a controller, so it turns with the hand. It shows only while
## the `show_map` action has been held for `HOLD_SECONDS`; a shorter click of
## the same button stays the label toggle. When both share that button, the
## map takes its answer from the label wiring's `ClickHold` (#335), so one
## press can never both show the map and flip the labels.
##
## It is handed copies (the union, the explored indices, the ship position) and
## keeps no reference to the session, so it can never write simulation state
## or comfort settings (ARC-3, CMF-6, MP-2).
##
## The look lives in `res://xr/map_look.json` (ARC-4), read like
## `level_look.json`:
##
##     {"line_color": [r, g, b], "line_energy": 0..8, "size_m": 0.05..0.6,
##      "marker_color": [r, g, b], "marker_radius_m": 0.002..0.05}

const NODE_NAME: String = "MapHologram"
const LINES_NAME: String = "Lines"
const MARKER_NAME: String = "Marker"
const DEFAULT_LOOK_FILE: String = "res://xr/map_look.json"
## How long `show_map` must be held before the map shows. Long enough that a
## click for the labels never flashes the map, short enough not to feel slow.
const HOLD_SECONDS: float = 0.4
## The map's centre from the controller: above the hand and a little ahead,
## so the hand does not cover it and lowering the hand takes it out of view.
const HAND_OFFSET: Vector3 = Vector3(0.0, 0.12, -0.08)

const LOOK_KEYS: Array[String] = ["line_color", "line_energy", "size_m", "marker_color", "marker_radius_m"]
const COLOR_KEYS: Array[String] = ["line_color", "marker_color"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"line_energy": [0.0, 8.0],
	"size_m": [0.05, 0.6],
	"marker_radius_m": [0.002, 0.05],
}
## Look used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = {
	"line_color": Color(0.3, 0.85, 1.0),
	"line_energy": 1.5,
	"size_m": 0.25,
	"marker_color": Color(1.0, 0.6, 0.15),
	"marker_radius_m": 0.008,
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## How long `show_map` has been held; 0 while it is released.
var held_seconds: float = 0.0

var _look: Dictionary = FALLBACK_LOOK
## Level space -> hologram space, as `MapWireframe.fit_to_cube` fits the lines.
var _fit: Transform3D = Transform3D.IDENTITY
var _lines: MeshInstance3D = MeshInstance3D.new()
var _marker: MeshInstance3D = MeshInstance3D.new()


func _init() -> void:
	name = NODE_NAME
	visible = false
	_lines.name = LINES_NAME
	_marker.name = MARKER_NAME
	for child: MeshInstance3D in [_lines, _marker]:
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(child)
	load_look()


## Parses the text of a look file. Returns the look with colours as `Color`
## and numbers as floats, or a dictionary holding only `"error"`, which names
## the field.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not LOOK_KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in LOOK_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var look: Dictionary = {}
	for key: String in COLOR_KEYS:
		var parts: Variant = data[key]
		if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
			return _rejected("\"%s\" must be [red, green, blue]" % key)
		for part: Variant in parts:
			if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
				return _rejected("\"%s\" must hold numbers" % key)
			if float(part) < 0.0 or float(part) > 1.0:
				return _rejected("\"%s\" has %s, must be within 0..1" % [key, part])
		look[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("\"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		look[key] = float(value)
	return look


## Applies the look file at `path`. A missing or rejected file leaves the
## built-in look, sets `look_error` and pushes a warning naming the field.
## Takes effect on the next `build`. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = parse_look(FileAccess.get_file_as_string(path))
	else:
		values = _rejected("file not found")
	_look = FALLBACK_LOOK
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("MapHologram uses the built-in look; %s" % look_error)
	else:
		_look = values
	return look_error


## The look the next `build` uses.
func look() -> Dictionary:
	return _look


## Redraws the map from the boxes of `union` listed in `explored`.
func build(union: BoxUnion, explored: Array[int]) -> void:
	var points: PackedVector3Array = MapWireframe.segments(union, explored)
	var size: float = float(_look["size_m"])
	_fit = fit_transform(points, size)
	_lines.mesh = null
	if not points.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = MapWireframe.fit_to_cube(points, size)
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		mesh.surface_set_material(0, _glow(_look["line_color"], float(_look["line_energy"])))
		_lines.mesh = mesh
	var sphere: SphereMesh = SphereMesh.new()
	var radius: float = float(_look["marker_radius_m"])
	sphere.radius = radius
	sphere.height = radius * 2.0
	# A dot this small needs few triangles (PRF-2).
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _glow(_look["marker_color"], float(_look["line_energy"]))
	_marker.mesh = sphere


## Number of line segments drawn by the last `build`.
func segment_count() -> int:
	var mesh: ArrayMesh = _lines.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / 2


## Moves the marker to the ship's level-space `position` (a copy), fitted
## like the lines.
func set_ship_position(position: Vector3) -> void:
	_marker.position = _fit * position


## The marker's position in the hologram.
func marker_position() -> Vector3:
	return _marker.position


## Records whether `show_map` is held this frame of `delta` seconds. The map
## shows once the hold reaches `HOLD_SECONDS` and hides on release.
func hold(held: bool, delta: float) -> void:
	held_seconds = held_seconds + delta if held else 0.0
	visible = held and held_seconds >= HOLD_SECONDS


## Reads `show_map` through `mapping` from sampled `buttons` and calls `hold`.
## With `shared` (the label button's `ClickHold`, given only while that button
## also shows the map), the map shows exactly while `shared` reports a long
## hold instead; call this after `shared` was fed for the frame.
func read(mapping: ThumbstickMapping, buttons: Dictionary, delta: float,
		shared: ClickHold = null) -> void:
	if shared == null:
		hold(mapping.action_held("show_map", buttons), delta)
		return
	held_seconds = held_seconds + delta if shared.is_held() else 0.0
	visible = shared.is_long_hold()


## The hand that clicks `show_map`, so the map sits in the hand that holds it:
## left by default, right when left-handed mode or a remap moves the click.
static func hand_for(mapping: ThumbstickMapping) -> String:
	for control: String in mapping.physical_controls("show_map"):
		if control.begins_with("right_"):
			return "right"
	return "left"


## Hangs this map under the `LeftHand` or `RightHand` node of `rig`, as
## `hand_for` picks, at `HAND_OFFSET`. Returns false when the rig has no such hand.
func attach_to(rig: Node, mapping: ThumbstickMapping) -> bool:
	var node_name: String = "RightHand" if hand_for(mapping) == "right" else "LeftHand"
	var hand: Node3D = rig.get_node_or_null(node_name) as Node3D
	if hand == null:
		return false
	if get_parent() != null:
		get_parent().remove_child(self)
	hand.add_child(self)
	position = HAND_OFFSET
	return true


## Level space -> hologram space: the uniform scale and centring that
## `MapWireframe.fit_to_cube(points, edge_m)` applies to `points`.
static func fit_transform(points: PackedVector3Array, edge_m: float) -> Transform3D:
	if points.is_empty():
		return Transform3D.IDENTITY
	var low: Vector3 = points[0]
	var high: Vector3 = points[0]
	for point: Vector3 in points:
		low = low.min(point)
		high = high.max(point)
	var centre: Vector3 = (low + high) * 0.5
	var longest: float = (high - low)[(high - low).max_axis_index()]
	var scale: float = edge_m / longest if longest > MapWireframe.EPSILON_M else 1.0
	return Transform3D(Basis.from_scale(Vector3.ONE * scale), -centre * scale)


## A black, non-reflective material that only glows, so the map reads the same
## in a lit room or a dark tunnel.
static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.metallic_specular = 0.0
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
