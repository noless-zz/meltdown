class_name LevelView
extends Node3D

## Draws the inside of a box-union level (GEN-5): every box's walls, facing
## into the box, with the openings where boxes overlap left open
## (`LevelFaces`). The walls are dark and unlit by themselves; dim emissive
## strips along the box edges let the shape read in the dark. The view adds
## no lights of its own: the ship's lights, weapons and flares light the mine
## (LGT-1).
##
## It only reads the union it is given and never writes to it (MP-2).
##
## The look lives in `res://view/level_look.json`, so it can be retuned
## without code (ARC-4):
##
##     {"wall_color": [r, g, b], "roughness": 0..1, "edge_color": [r, g, b],
##      "edge_energy": 0..1, "edge_width_m": 0.02..1}

const NODE_NAME: String = "LevelView"
const WALLS_NAME: String = "Walls"
const EDGES_NAME: String = "Edges"
const DEFAULT_LOOK_FILE: String = "res://view/level_look.json"

const LOOK_KEYS: Array[String] = ["wall_color", "roughness", "edge_color", "edge_energy", "edge_width_m"]
## Inclusive ranges of the number keys. Edge energy stays at or below 1 so the
## strips stay dim: they outline the mine, they do not light it.
const RANGES: Dictionary[String, Array] = {
	"roughness": [0.0, 1.0],
	"edge_energy": [0.0, 1.0],
	"edge_width_m": [0.02, 1.0],
}
## How far edge strips sit off the wall, into the box, so they never share the
## wall's plane and flicker against it.
const EDGE_LIFT_M: float = 0.01

## Look used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = {
	"wall_color": Color(0.16, 0.15, 0.14),
	"roughness": 0.9,
	"edge_color": Color(0.25, 0.45, 0.6),
	"edge_energy": 0.4,
	"edge_width_m": 0.15,
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK_LOOK
var _quads: Array[Dictionary] = []
var _strips: Array[Dictionary] = []


func _init() -> void:
	name = NODE_NAME
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
	for key: String in ["wall_color", "edge_color"]:
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
## fallback look, sets `look_error` and pushes a warning naming the field.
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
		push_warning("LevelView uses the fallback look; %s" % look_error)
	else:
		_look = values
	return look_error


## The look the next `build` uses.
func look() -> Dictionary:
	return _look


## Replaces whatever was drawn with the inside of `union`.
func build(union: BoxUnion) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_quads = LevelFaces.quads(union)
	_strips.clear()
	var width: float = float(_look["edge_width_m"])
	for quad: Dictionary in _quads:
		_strips.append_array(LevelFaces.edge_strips(quad, union.boxes[quad["box"]], width, EDGE_LIFT_M))
	var walls: StandardMaterial3D = StandardMaterial3D.new()
	walls.albedo_color = _look["wall_color"]
	walls.roughness = float(_look["roughness"])
	var edges: StandardMaterial3D = StandardMaterial3D.new()
	var edge_color: Color = _look["edge_color"]
	edges.albedo_color = edge_color
	edges.emission_enabled = true
	edges.emission = edge_color
	edges.emission_energy_multiplier = float(_look["edge_energy"])
	add_child(_instance(WALLS_NAME, _quads, walls))
	add_child(_instance(EDGES_NAME, _strips, edges))


## The wall quads of the last `build`, in `LevelFaces` layout.
func quads() -> Array[Dictionary]:
	return _quads


## The edge strips of the last `build`, in `LevelFaces` layout.
func strips() -> Array[Dictionary]:
	return _strips


## The six corners of the two triangles that draw `quad`. Godot draws the
## side from which a triangle's corners run clockwise, so the order is picked
## to make that the side the quad's normal points to: into its box.
static func triangles(quad: Dictionary) -> Array[Vector3]:
	var axis: int = quad["axis"]
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var low: Vector3 = quad["min"]
	var high: Vector3 = quad["max"]
	var c00: Vector3 = low
	var c10: Vector3 = low
	c10[u] = high[u]
	var c11: Vector3 = high
	var c01: Vector3 = low
	c01[v] = high[v]
	# Corners c00, c10, c11 run counter-clockwise seen from +axis.
	if float((quad["normal"] as Vector3)[axis]) > 0.0:
		return [c00, c11, c10, c00, c01, c11]
	return [c00, c10, c11, c00, c11, c01]


static func _instance(node_name: String, list: Array[Dictionary], material: StandardMaterial3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if list.is_empty():
		return instance
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for quad: Dictionary in list:
		for corner: Vector3 in triangles(quad):
			vertices.append(corner)
			normals.append(quad["normal"])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	return instance


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
