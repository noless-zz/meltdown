class_name LevelView
extends Node3D

## Draws the inside of a box-union level (GEN-5): every box's walls, facing
## into the box, with the openings where boxes overlap left open
## (`LevelFaces`). Floor, ceiling and walls are tinted apart and carry a
## world-space grid; dim emissive strips along the box edges let the shape
## read in the dark; the walls darken with distance (#609). The view adds no
## lights of its own: the ship's headlight, weapons and flares light the mine
## (LGT-1).
##
## It only reads the union it is given and never writes to it (MP-2).
##
## The look lives in `res://view/level_look.json` and is parsed by
## `LevelLook`, so it can be retuned without code (ARC-4).

const NODE_NAME: String = "LevelView"
const WALLS_NAME: String = "Walls"
const EDGES_NAME: String = "Edges"
const ENVIRONMENT_NAME: String = "Environment"
const DEFAULT_LOOK_FILE: String = LevelLook.DEFAULT_FILE

## How far edge strips sit off the wall, into the box, so they never share the
## wall's plane and flicker against it.
const EDGE_LIFT_M: float = 0.01

## Look used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = LevelLook.FALLBACK

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK_LOOK
var _quads: Array[Dictionary] = []
var _strips: Array[Dictionary] = []


func _init() -> void:
	name = NODE_NAME
	load_look()


## Parses the text of a look file; see `LevelLook.parse`.
static func parse_look(text: String) -> Dictionary:
	return LevelLook.parse(text)


## Applies the look file at `path`. A missing or rejected file leaves the
## fallback look, sets `look_error` and pushes a warning naming the field.
## Takes effect on the next `build`. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var values: Dictionary = LevelLook.load_file(path)
	_look = FALLBACK_LOOK
	look_error = ""
	if values.has("error"):
		look_error = values["error"]
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
	var edges: StandardMaterial3D = StandardMaterial3D.new()
	var edge_color: Color = _look["edge_color"]
	edges.albedo_color = edge_color
	edges.emission_enabled = true
	edges.emission = edge_color
	edges.emission_energy_multiplier = float(_look["edge_energy"])
	var groups: Array[Array] = []
	var materials: Array[Material] = []
	for surface: String in LevelLook.CLASSES:
		var group: Array[Dictionary] = []
		for quad: Dictionary in _quads:
			if LevelLook.surface_class(quad["normal"]) == surface:
				group.append(quad)
		if group.is_empty():
			continue
		groups.append(group)
		materials.append(LevelLook.wall_material(_look, _look["%s_color" % surface]))
	var walls: MeshInstance3D = _instance(WALLS_NAME, groups, materials)
	# Walls block the headlight (the one shadow-casting light, GFX-4), so it
	# cannot shine through a wall into the next room.
	walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(walls)
	var strips: Array[Array] = [_strips]
	var edge_materials: Array[Material] = [edges]
	add_child(_instance(EDGES_NAME, strips, edge_materials))
	add_child(LevelLook.world_environment(_look, ENVIRONMENT_NAME))


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


## One mesh with a surface per list in `lists`, drawn in the matching material.
static func _instance(node_name: String, lists: Array[Array], materials: Array[Material]) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh: ArrayMesh = ArrayMesh.new()
	for index: int in lists.size():
		var list: Array = lists[index]
		if list.is_empty():
			continue
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
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[index])
	if mesh.get_surface_count() > 0:
		instance.mesh = mesh
	return instance
