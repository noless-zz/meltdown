class_name LevelView
extends Node3D

## Draws the inside of a box-union level (GEN-5): every box's walls, facing
## into the box, with the openings where boxes overlap left open
## (`LevelFaces`). Floor, ceiling and walls are tinted apart and carry a
## world-space grid; the walls darken with distance (#609). The shader picks
## each face's tint, so a box's walls and frames are one surface (#1383).
## Every opening is framed as deep as the wall is thick (`LevelFrames`) and
## every box edge is bevelled, with a dim glow so the shape reads in the dark
## (`LevelBevels`), so walls have mass rather than reading as paper (#1323). The view adds no
## lights of its own: the ship's headlight, weapons and flares light the mine
## (LGT-1).
##
## Each box (room or tunnel) is its own node holding its walls, frames and
## bevels, and each frame only the boxes that can be seen from the camera are
## shown (`LevelVisibility`, #1364, GFX-3): the camera's own box and the boxes
## seen through openings. `level_visibility.json` can switch that off.
##
## It only reads the union it is given and never writes to it (MP-2).
##
## The look lives in `res://view/level_look.json` and is parsed by
## `LevelLook`, so it can be retuned without code (ARC-4).

const NODE_NAME: String = "LevelView"
const WALLS_NAME: String = "Walls"
const BEVELS_NAME: String = "Bevels"
const ENVIRONMENT_NAME: String = "Environment"
## Box nodes are named this followed by the box's index.
const BOX_PREFIX: String = "Box"
## Runs after the rig and the ship have moved the camera this frame.
const PROCESS_PRIORITY: int = 1000
const DEFAULT_LOOK_FILE: String = LevelLook.DEFAULT_FILE

## Look used when the file is missing or rejected.
const FALLBACK_LOOK: Dictionary = LevelLook.FALLBACK

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK_LOOK
var _quads: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
var _bevels: Array[Dictionary] = []
var _boxes: Array[Node3D] = []
var _visibility: LevelVisibility = null
var _settings: Dictionary = LevelVisibility.DEFAULTS
## Set when the visibility file was rejected; empty otherwise.
var visibility_error: String = ""
## Boxes and draw calls shown in the last culled frame, and totals over frames.
var drawn_boxes: int = 0
var drawn_surfaces: int = 0
var culled_frames: int = 0
var drawn_boxes_total: int = 0
var drawn_surfaces_total: int = 0


func _init() -> void:
	name = NODE_NAME
	process_priority = PROCESS_PRIORITY
	load_look()
	load_visibility()


## Applies the visibility settings at `path`; a missing or rejected file keeps
## culling on with `LevelVisibility.DEFAULTS` and pushes a warning naming the
## field. Returns `visibility_error`.
func load_visibility(path: String = LevelVisibilitySettings.DEFAULT_FILE) -> String:
	var values: Dictionary = LevelVisibilitySettings.load_file(path)
	_settings = LevelVisibility.DEFAULTS
	visibility_error = ""
	if values.has("error"):
		visibility_error = values["error"]
		push_warning("LevelView uses the default visibility; %s" % visibility_error)
	else:
		_settings = values
	return visibility_error


## The visibility settings in use.
func visibility_settings() -> Dictionary:
	return _settings


## Switches culling on or off for this view (the dev switch); off shows every box.
func set_culling(enabled: bool) -> void:
	_settings = _settings.duplicate()
	_settings["enabled"] = enabled
	if not enabled:
		for box: Node3D in _boxes:
			box.visible = true


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
	_boxes.clear()
	var per_box: Array[Array] = []
	var bevels_per_box: Array[Array] = []
	for index: int in union.boxes.size():
		per_box.append([])
		bevels_per_box.append([])
	for quad: Dictionary in _quads:
		per_box[int(quad["box"])].append(quad)
	for quad: Dictionary in _frames:
		per_box[frame_box(union, quad)].append(quad)
	for bevel: Dictionary in _bevels:
		bevels_per_box[int(bevel["box"])].append(bevel)
	var wall_material: Material = LevelViewMeshes.kind_material(_look)
	var bevel_material: Material = LevelLook.bevel_material(_look)
	for index: int in union.boxes.size():
		var box: Node3D = Node3D.new()
		box.name = "%s%d" % [BOX_PREFIX, index]
		_add_box_meshes(box, per_box[index], bevels_per_box[index], wall_material, bevel_material)
		add_child(box)
		_boxes.append(box)
	add_child(LevelLook.world_environment(_look, ENVIRONMENT_NAME))
	_visibility = LevelVisibility.new(union)


## The node of box `index` of the last `build`, or null.
func box_node(index: int) -> Node3D:
	return _boxes[index] if index >= 0 and index < _boxes.size() else null


func box_count() -> int:
	return _boxes.size()


## The walls (and frames) mesh of box `index`, or null when it has none.
func walls_of(index: int) -> MeshInstance3D:
	var box: Node3D = box_node(index)
	return box.get_node_or_null(WALLS_NAME) as MeshInstance3D if box != null else null


## The bevels mesh of box `index`, or null when it has none.
func bevels_of(index: int) -> MeshInstance3D:
	var box: Node3D = box_node(index)
	return box.get_node_or_null(BEVELS_NAME) as MeshInstance3D if box != null else null


## Surfaces (one draw call each) that box `index` draws.
func surfaces_of(index: int) -> int:
	var count: int = 0
	for part: MeshInstance3D in [walls_of(index), bevels_of(index)]:
		if part != null and part.mesh != null:
			count += part.mesh.get_surface_count()
	return count


## The visibility graph of the last `build`.
func visibility() -> LevelVisibility:
	return _visibility


## The box whose node draws frame `quad`: a frame is sunk behind its face, into
## the box that opens there, so it is drawn (and hidden) with that box. The
## lowest such box holding the frame's centre; its own box if none does.
static func frame_box(union: BoxUnion, quad: Dictionary) -> int:
	var centre: Vector3 = ((quad["min"] as Vector3) + (quad["max"] as Vector3)) * 0.5
	for index: int in union.boxes.size():
		if index == int(quad["box"]):
			continue
		var box: BoxBounds = union.boxes[index]
		var grow: Vector3 = Vector3.ONE * 1e-3
		if _inside(centre, box.min_corner - grow, box.max_corner + grow):
			return index
	return int(quad["box"])


static func _inside(point: Vector3, low: Vector3, high: Vector3) -> bool:
	return point.x >= low.x and point.y >= low.y and point.z >= low.z \
			and point.x <= high.x and point.y <= high.y and point.z <= high.z


## Shows only the boxes that can be seen from an eye at `eye` looking along -Z
## of `basis`, both in this view's space, and counts what is drawn.
func cull(eye: Vector3, basis: Basis) -> void:
	if _visibility == null:
		return
	var flags: Array[bool] = _visibility.visible(eye, basis, _settings)
	drawn_boxes = 0
	drawn_surfaces = 0
	for index: int in _boxes.size():
		_boxes[index].visible = flags[index]
		if flags[index]:
			drawn_boxes += 1
			drawn_surfaces += surfaces_of(index)
	culled_frames += 1
	drawn_boxes_total += drawn_boxes
	drawn_surfaces_total += drawn_surfaces


func _process(_delta: float) -> void:
	if not bool(_settings["enabled"]) or _boxes.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var to_level: Transform3D = global_transform.affine_inverse() * camera.global_transform
	cull(to_level.origin, to_level.basis)


static func _add_box_meshes(box: Node3D, quads: Array, bevels: Array, wall_material: Material,
		bevel_material: Material) -> void:
	if not quads.is_empty():
		# Floor, wall and ceiling, and the opening frames, in one surface: the
		# shader tints each face by its normal (#1383).
		var lists: Array[Array] = [quads]
		var used: Array[Material] = [wall_material]
		var walls: MeshInstance3D = LevelViewMeshes.walls(WALLS_NAME, lists, used)
		# Walls block the headlight (the one shadow-casting light, GFX-4), so it
		# cannot shine through a wall into the next room.
		walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		box.add_child(walls)
	if not bevels.is_empty():
		var typed: Array[Dictionary] = []
		typed.assign(bevels)
		box.add_child(LevelViewMeshes.bevels(typed, bevel_material))


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
