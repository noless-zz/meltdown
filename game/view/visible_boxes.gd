class_name VisibleBoxes
extends RefCounted

## Whether a point of the level lies in a box drawn this frame (#1382, GFX-3,
## PRF-2, PRF-4), so robots, pickups and effects in a box `LevelView` hides are
## hidden with it. The views ask while setting `visible` as they already do; a
## view given no `VisibleBoxes` (the test tunnel, or tests) draws everything.
##
## A thing is drawn when the sphere of `radius` around it reaches into any shown
## box, or when no box holds it at all (it is outside the walls, so hiding it
## could only hide something that should be seen). Culling switched off, or no
## cull yet, shows everything. It reads the union once and keeps its own copy;
## the simulation is never touched (MP-2).

var _mins: Array[Vector3] = []
var _maxs: Array[Vector3] = []
## Indices of the boxes shown by the last `set_flags`; empty with `_all` set.
var _shown: Array[int] = []
var _all: bool = true

## Things answered hidden since the last `set_flags`, the per-frame count.
var hidden: int = 0


func _init(union: BoxUnion = null) -> void:
	if union == null:
		return
	for box: BoxBounds in union.boxes:
		_mins.append(box.min_corner)
		_maxs.append(box.max_corner)


## Takes the per-box flags of a cull (`LevelVisibility.visible`); an empty or
## all-true array shows everything. Starts a new frame's `hidden` count.
func set_flags(flags: Array[bool]) -> void:
	hidden = 0
	_shown.clear()
	_all = true
	for index: int in mini(flags.size(), _mins.size()):
		if flags[index]:
			_shown.append(index)
		else:
			_all = false
	if _all:
		_shown.clear()


## Shows every box, as culling switched off does.
func show_all() -> void:
	set_flags([] as Array[bool])


func box_count() -> int:
	return _mins.size()


## Whether a thing at `point` reaching `radius` metres round it is drawn. Every
## hidden answer counts towards `hidden`.
func shows(point: Vector3, radius: float = 0.0) -> bool:
	if _all:
		return true
	# Shown boxes are few, so they are tried first; a hidden box is only
	# looked for when none of them holds the point.
	for index: int in _shown:
		if _holds(index, point, radius):
			return true
	for index: int in _mins.size():
		if _holds(index, point, radius):
			hidden += 1
			return false
	return true


## The boxes the level view under `world` draws this frame, culled from the
## camera now if it was not yet, so the item views drawn after it agree with
## the walls; null when `world` holds no level view (the test tunnel).
static func of_world(world: Node) -> VisibleBoxes:
	var view: LevelView = world.get_node_or_null(LevelView.NODE_NAME) as LevelView if world != null else null
	if view == null:
		return null
	view.cull_camera()
	return view.shown_boxes()


## `boxes.shows(point, radius)`, or true when `boxes` is null.
static func allows(boxes: VisibleBoxes, point: Vector3, radius: float = 0.0) -> bool:
	return boxes == null or boxes.shows(point, radius)


func _holds(index: int, point: Vector3, radius: float) -> bool:
	var low: Vector3 = _mins[index]
	var high: Vector3 = _maxs[index]
	return point.x >= low.x - radius and point.y >= low.y - radius and point.z >= low.z - radius \
			and point.x <= high.x + radius and point.y <= high.y + radius and point.z <= high.z + radius
