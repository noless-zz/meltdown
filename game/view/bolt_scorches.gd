class_name BoltScorches
extends Node3D

## Scorch marks where bolts strike walls (#1309, GFX-6): a dark round decal
## laid on the wall that fades out over `fade_s`. The decal's texture is a
## radial gradient made in code, so no image file is shipped (ARC-5). The
## pool is capped: past `MAX_SCORCHES` the oldest mark is reused.
##
## Pure view: nothing here is read back by the simulation (MP-2).

const SCORCH_PREFIX: String = "Scorch"
## Most marks at once; a firefight leaves the newest.
const MAX_SCORCHES: int = 24
## How far in front of and behind the wall the decal reaches, metres.
const DEPTH_M: float = 0.4
const TEXTURE_SIZE: int = 32

## Radius of a new mark, metres.
var radius_m: float = 0.25
## Seconds a mark takes to fade out; 0 turns new marks off.
var fade_s: float = 0.0
## Colour of a new mark.
var color: Color = Color(0.05, 0.04, 0.03)

var _nodes: Array[Decal] = []
var _ages: Array[float] = []
var _texture: GradientTexture2D = null


func _init(node_name: String = "BoltScorches") -> void:
	name = node_name
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_texture = GradientTexture2D.new()
	_texture.gradient = gradient
	_texture.width = TEXTURE_SIZE
	_texture.height = TEXTURE_SIZE
	_texture.fill = GradientTexture2D.FILL_RADIAL
	_texture.fill_from = Vector2(0.5, 0.5)
	_texture.fill_to = Vector2(1.0, 0.5)


func _process(delta: float) -> void:
	age(delta)


## Sets the size, fade time and colour of marks from now on.
func set_look(radius: float, fade: float, mark_color: Color) -> void:
	radius_m = radius
	fade_s = fade
	color = mark_color


## Lays a mark at `at` on the wall whose face points along `normal`.
func mark(at: Vector3, normal: Vector3) -> void:
	if fade_s <= 0.0:
		return
	var slot: int = _free_slot()
	var decal: Decal = _nodes[slot]
	# A decal projects along its own -Y, so its Y is the wall's outward normal.
	decal.transform = Transform3D(ProjectileView.bolt_basis(normal), at)
	decal.size = Vector3(radius_m * 2.0, DEPTH_M, radius_m * 2.0)
	_ages[slot] = 0.0
	_paint(slot)


## Moves every mark on by `delta` seconds.
func age(delta: float) -> void:
	for slot: int in _nodes.size():
		if _nodes[slot].visible:
			_ages[slot] += delta
			_paint(slot)


## The marks showing now.
func shown() -> Array[Decal]:
	var showing: Array[Decal] = []
	for decal: Decal in _nodes:
		if decal.visible:
			showing.append(decal)
	return showing


func _paint(slot: int) -> void:
	var left: float = 0.0 if fade_s <= 0.0 else 1.0 - _ages[slot] / fade_s
	var decal: Decal = _nodes[slot]
	decal.visible = left > 0.0
	decal.modulate = Color(color, clampf(left, 0.0, 1.0))


func _free_slot() -> int:
	var oldest: int = 0
	for slot: int in _nodes.size():
		if not _nodes[slot].visible:
			return slot
		if _ages[slot] > _ages[oldest]:
			oldest = slot
	if _nodes.size() >= MAX_SCORCHES:
		return oldest
	var decal: Decal = Decal.new()
	decal.name = "%s%d" % [SCORCH_PREFIX, _nodes.size()]
	decal.texture_albedo = _texture
	decal.visible = false
	add_child(decal)
	_nodes.append(decal)
	_ages.append(0.0)
	return _nodes.size() - 1
