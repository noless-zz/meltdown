class_name LevelView
extends Node3D

## Draws the inside of a box-union level (GEN-5): every box's walls, facing
## into the box, with the openings where boxes overlap left open
## (`LevelFaces`). Floor, ceiling and walls are tinted apart and carry a
## world-space grid; the walls darken with distance (#609). Every opening is
## framed as deep as the wall is thick (`LevelFrames`) and every box edge is
## bevelled, with a dim glow so the shape reads in the dark (`LevelBevels`),
## so walls have mass rather than reading as paper (#1323). The view adds no
## lights of its own: the ship's headlight, weapons and flares light the mine
## (LGT-1).
##
## It only reads the union it is given and never writes to it (MP-2).
##
## The look lives in `res://view/level_look.json` and is parsed by
## `LevelLook`, so it can be retuned without code (ARC-4).

const NODE_NAME: String = "LevelView"
const WALLS_NAME: String = "Walls"
const BEVELS_NAME: String = "Bevels"
const ENVIRONMENT_NAME: String = "Environment"
const DEFAULT_LOOK_FILE: String = LevelLook.DEFAULT_FILE

## Look used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = LevelLook.FALLBACK

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK_LOOK
var _quads: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
var _bevels: Array[Dictionary] = []


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
	_frames = LevelFrames.quads(union, float(_look["frame_depth_m"]), float(_look["frame_width_m"]))
	_bevels = LevelBevels.quads(union, _quads, float(_look["edge_width_m"]))
	var groups: Array[Array] = []
	var materials: Array[Material] = []
	for surface: String in LevelLook.CLASSES:
		var group: Array[Dictionary] = []
		# Frames are drawn in the walls' own surfaces, so they cost no draw call.
		for quad: Dictionary in _quads + _frames:
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
	add_child(_bevel_instance(_bevels, LevelLook.bevel_material(_look)))
	add_child(LevelLook.world_environment(_look, ENVIRONMENT_NAME))


## The wall quads of the last `build`, in `LevelFaces` layout.
func quads() -> Array[Dictionary]:
	return _quads


## The opening frames of the last `build`, in `LevelFaces` layout.
func frames() -> Array[Dictionary]:
	return _frames


## The edge bevels of the last `build`, in `LevelBevels` layout.
func bevels() -> Array[Dictionary]:
	return _bevels


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


## One mesh of `bevels` in `material`. The bevels cast no shadow: they sit in
## the corners, where the walls' own shadow already falls.
static func _bevel_instance(bevels: Array[Dictionary], material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = BEVELS_NAME
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if bevels.is_empty():
		return instance
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for bevel: Dictionary in bevels:
		for corner: Vector3 in LevelBevels.triangles(bevel):
			vertices.append(corner)
			normals.append(bevel["normal"])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	return instance
