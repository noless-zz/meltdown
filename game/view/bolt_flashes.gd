class_name BoltFlashes
extends Node3D

## Short glowing flashes for bolts (#602, CMB-1, LGT-1): one pool for the
## muzzle flashes, one for the impacts. A flash is an unshaded sphere that
## shrinks to nothing over its lifetime, so it needs no transparency, which
## costs the Quest more than a few extra vertices.
##
## A flash can ride on a ship: it is then placed at a point in that ship's
## own axes on every `follow`, so a muzzle flash stays at the muzzle while the
## ship flies on. Pure view: nothing here is read back by the simulation (MP-2).

const FLASH_PREFIX: String = "Flash"

## Radius at the start of a flash, metres.
var radius_m: float = 0.1
## How long a flash lasts, seconds; 0 turns new flashes off.
var lifetime_s: float = 0.1

var _nodes: Array[MeshInstance3D] = []
## Seconds each pooled flash has shown; at or past `lifetime_s` it is free.
var _ages: Array[float] = []
## The ship index a flash rides on, or -1 for a flash fixed in the world.
var _ships: Array[int] = []
## Where a riding flash sits in its ship's axes.
var _locals: Array[Vector3] = []
var _mesh: SphereMesh = SphereMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()


func _init(node_name: String = "BoltFlashes") -> void:
	name = node_name
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	_mesh.radial_segments = 8
	_mesh.rings = 4
	_mesh.radius = 1.0
	_mesh.height = 2.0
	_mesh.material = _material


func _process(delta: float) -> void:
	age(delta)


## Sets the size, lifetime and colour of the flashes from now on.
func set_look(radius: float, lifetime: float, color: Color) -> void:
	radius_m = radius
	lifetime_s = lifetime
	_material.albedo_color = color
	_material.emission = color
	_rescale()


## Starts a flash at `at`, in this node's space. With `ship` 0 or more, the
## flash rides on that ship at `local`, its own axes, from the next `follow`.
func flash(at: Vector3, ship: int = -1, local: Vector3 = Vector3.ZERO) -> void:
	if lifetime_s <= 0.0:
		return
	var slot: int = _free_slot()
	_ages[slot] = 0.0
	_ships[slot] = ship
	_locals[slot] = local
	_nodes[slot].position = at
	_rescale()


## Places each riding flash on its ship's pose; `poses[i]` is ship `i`'s.
## A flash whose ship has no pose stays where it is.
func follow(poses: Array[Transform3D]) -> void:
	for slot: int in _nodes.size():
		var ship: int = _ships[slot]
		if ship >= 0 and ship < poses.size() and _nodes[slot].visible:
			_nodes[slot].position = poses[ship] * _locals[slot]


## Moves every flash on by `delta` seconds.
func age(delta: float) -> void:
	for slot: int in _ages.size():
		_ages[slot] += delta
	_rescale()


## The flashes showing now, by pool slot.
func shown() -> Array[MeshInstance3D]:
	var showing: Array[MeshInstance3D] = []
	for node: MeshInstance3D in _nodes:
		if node.visible:
			showing.append(node)
	return showing


## Number of flash nodes in the pool, shown or hidden.
func pool_size() -> int:
	return _nodes.size()


func material() -> StandardMaterial3D:
	return _material


func _free_slot() -> int:
	for slot: int in _ages.size():
		if _ages[slot] >= lifetime_s:
			return slot
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "%s%d" % [FLASH_PREFIX, _nodes.size()]
	node.mesh = _mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	_nodes.append(node)
	_ages.append(INF)
	_ships.append(-1)
	_locals.append(Vector3.ZERO)
	return _nodes.size() - 1


func _rescale() -> void:
	for slot: int in _nodes.size():
		var left: float = 0.0 if lifetime_s <= 0.0 else 1.0 - _ages[slot] / lifetime_s
		var node: MeshInstance3D = _nodes[slot]
		node.visible = left > 0.0
		if node.visible:
			node.scale = Vector3.ONE * (radius_m * left)
