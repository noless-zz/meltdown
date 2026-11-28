class_name PickupMarks
extends Node3D

## A short mark where a component heap lay, once the local ship has taken it
## (#1375, CRF-1, CMF-3, ARC-4). The owner's G4 note: a heap just vanished,
## with nothing to say it was collected there. The mark is a soft shell in the
## kind's colour that grows a little and fades out within its `fade_seconds`.
##
## It is never a flash (CMF-3): it starts no brighter than its data's
## `peak_energy` and `peak_alpha`, both capped below in `RANGES`, only ever
## dims, and is not drawn while the eye is inside it or within
## `eye_clearance_m` of its surface. The ship flies through the heap to take
## it, so the eye starts at the mark; its back faces are culled as well, so
## from inside it never fills the view.
##
## It reads the copies of `COMPONENT_COLLECTED` events it is handed and writes
## nothing back (MP-2). Its clock is the view's own. The look lives in
## `res://view/pickup_mark_look.json`, every key required (ARC-4).

const NODE_NAME: String = "PickupMarks"
const MARK_PREFIX: String = "Mark"
const DEFAULT_LOOK_FILE: String = "res://view/pickup_mark_look.json"
const KEYS: Array[String] = ["fade_seconds", "start_size", "end_size", "peak_alpha", "peak_energy",
	"eye_clearance_m", "max_marks"]
## Allowed range of every key, inclusive. The upper ends are the comfort limits
## (CMF-3): gone within a second, never wider than 1.5 m, never brighter than a
## heap is drawn, never opaque.
const RANGES: Dictionary = {
	"fade_seconds": [0.1, 1.0], "start_size": [0.05, 1.5], "end_size": [0.05, 1.5],
	"peak_alpha": [0.05, 0.8], "peak_energy": [0.0, 3.0], "eye_clearance_m": [0.0, 3.0],
	"max_marks": [1, 16],
}
const FALLBACK_LOOK: Dictionary = {
	"fade_seconds": 0.6, "start_size": 0.35, "end_size": 0.9, "peak_alpha": 0.5, "peak_energy": 1.2,
	"eye_clearance_m": 0.5, "max_marks": 8,
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Marks started since this view was built, and the most seconds one was drawn
## for; acceptance and tests read them.
var started_count: int = 0
var longest_drawn_seconds: float = 0.0
## Marks drawn on at least one frame.
var drawn_count: int = 0
## The furthest a mark started from the nearest heap drawn before it was taken.
var largest_offset_m: float = 0.0

var _look: Dictionary = FALLBACK_LOOK
var _mesh: SphereMesh = null
var _nodes: Array[MeshInstance3D] = []
## Seconds since each pooled mark started; at or past the fade it is free.
var _ages: Array[float] = []
var _drawn: Array[bool] = []


func _init() -> void:
	name = NODE_NAME
	_mesh = SphereMesh.new()
	# Unit diameter, so a node's scale is its size in metres.
	_mesh.radius = 0.5
	_mesh.height = 1.0
	_mesh.radial_segments = 16
	_mesh.rings = 8
	load_look()


## Parses the text of a look file. Returns the look with numbers as floats
## (`max_marks` an int), or a dictionary holding only `"error"` naming the key.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return {"error": "unknown key \"%s\"" % str(key)}
	var look: Dictionary = {}
	for key: String in KEYS:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
		var problem: String = MinerLook.check_number(key, data[key], RANGES[key])
		if problem != "":
			return {"error": problem}
		look[key] = float(data[key])
	if look["max_marks"] != floorf(look["max_marks"]):
		return {"error": "\"max_marks\" must be a whole number"}
	look["max_marks"] = int(look["max_marks"])
	return look


## Applies the look file at `path`. A missing or rejected file keeps the
## fallback look, sets `look_error` and pushes a warning. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var look: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		look = parse_look(FileAccess.get_file_as_string(path))
	_look = FALLBACK_LOOK
	look_error = ""
	if look.has("error"):
		look_error = "%s: %s" % [path, look["error"]]
		push_warning("PickupMarks uses the fallback look; %s" % look_error)
	else:
		_look = look
	return look_error


func look() -> Dictionary:
	return _look


## Starts a mark at `at` in `color`. `heaps` are where heaps were drawn before
## this one was taken, to record how far the mark is from where the pilot saw
## it. With every mark in use, the oldest is reused. It shows from the next
## `advance`.
func start(at: Vector3, color: Color, heaps: Array[Vector3] = []) -> void:
	var index: int = _free_index()
	var instance: MeshInstance3D = _nodes[index]
	instance.position = at
	(instance.material_override as StandardMaterial3D).albedo_color = color
	(instance.material_override as StandardMaterial3D).emission = color
	_ages[index] = 0.0
	_drawn[index] = false
	started_count += 1
	if not heaps.is_empty():
		var nearest: float = INF
		for heap: Vector3 in heaps:
			nearest = minf(nearest, heap.distance_to(at))
		largest_offset_m = maxf(largest_offset_m, nearest)
	# Drawn from the next `advance`, which knows where the eye is.
	instance.visible = false


## Runs every mark on by `delta` seconds and draws it as seen from `viewer`,
## a point in this node's space (`Vector3.INF` when there is no eye).
func advance(delta: float, viewer: Vector3 = Vector3.INF) -> void:
	for index: int in _nodes.size():
		if _ages[index] < _look["fade_seconds"]:
			_ages[index] += maxf(delta, 0.0)
		_show(index, viewer)


## How much of its peak a mark shows `age` seconds after it started: 1 at the
## start, falling to 0 at `fade_seconds`, never rising (CMF-3).
func strength_at(age: float) -> float:
	return clampf(1.0 - age / float(_look["fade_seconds"]), 0.0, 1.0)


## A mark's size in metres `age` seconds after it started; it grows quickly at
## first and settles, so it reads as spreading from the heap.
func size_at(age: float) -> float:
	var t: float = clampf(age / float(_look["fade_seconds"]), 0.0, 1.0)
	return lerpf(_look["start_size"], _look["end_size"], 1.0 - (1.0 - t) * (1.0 - t))


## Marks drawn now.
func shown_count() -> int:
	var shown: int = 0
	for instance: MeshInstance3D in _nodes:
		if instance.visible:
			shown += 1
	return shown


func node_count() -> int:
	return _nodes.size()


## The pooled mark at `index`, for tests.
func node(index: int) -> MeshInstance3D:
	return _nodes[index]


func _show(index: int, viewer: Vector3) -> void:
	var instance: MeshInstance3D = _nodes[index]
	var age: float = _ages[index]
	var strength: float = strength_at(age)
	var size: float = size_at(age)
	var clear: bool = viewer == Vector3.INF \
		or viewer.distance_to(instance.position) > size * 0.5 + float(_look["eye_clearance_m"])
	instance.visible = strength > 0.0 and clear
	if not instance.visible:
		return
	instance.scale = Vector3.ONE * size
	var material: StandardMaterial3D = instance.material_override as StandardMaterial3D
	material.albedo_color.a = float(_look["peak_alpha"]) * strength
	material.emission_energy_multiplier = float(_look["peak_energy"]) * strength
	if not _drawn[index]:
		_drawn[index] = true
		drawn_count += 1
	longest_drawn_seconds = maxf(longest_drawn_seconds, age)


## A mark that has faded, a new one while under `max_marks`, or the oldest.
func _free_index() -> int:
	var oldest: int = -1
	for index: int in _nodes.size():
		if _ages[index] >= _look["fade_seconds"]:
			return index
		if oldest < 0 or _ages[index] > _ages[oldest]:
			oldest = index
	if _nodes.size() < int(_look["max_marks"]):
		_add_node()
		return _nodes.size() - 1
	return oldest


func _add_node() -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "%s%d" % [MARK_PREFIX, _nodes.size()]
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	# Back faces stay culled: from inside the shell nothing is drawn.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	instance.material_override = material
	add_child(instance)
	_nodes.append(instance)
	_ages.append(INF)
	_drawn.append(true)
