class_name BoltSparks
extends Node3D

## Spark bursts where bolts end and robots blow up (#1309, GFX-6, CMB-1): short
## glowing streaks that fly out from a point and shrink to nothing. Each burst
## is one `MultiMeshInstance3D`, so a burst costs one draw call whatever its
## spark count, and nothing is drawn full screen. The spread is fixed by the
## spark's index, not random, so screenshots of a replay are the same each time.
##
## Pure view: it is told where bursts start and reads nothing back (MP-2).

const BURST_PREFIX: String = "Sparks"
## Size of one spark at its start, metres: thin and drawn out along its flight.
const SPARK_SIZE: Vector3 = Vector3(0.015, 0.12, 0.015)
## Radians between one spark's way round the spiral and the next's.
const GOLDEN_ANGLE: float = 2.39996323

var _nodes: Array[MultiMeshInstance3D] = []
## Per pooled burst: seconds shown, lifetime, start, normal, speed, whole sphere.
var _ages: Array[float] = []
var _lifetimes: Array[float] = []
var _starts: Array[Vector3] = []
var _normals: Array[Vector3] = []
var _speeds: Array[float] = []
var _spheres: Array[bool] = []
var _mesh: BoxMesh = BoxMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()


func _init(node_name: String = "BoltSparks") -> void:
	name = node_name
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_mesh.size = Vector3.ONE
	_mesh.material = _material


func _process(delta: float) -> void:
	age(delta)


## Starts a burst of `count` sparks of `color` at `at`, flying at up to
## `speed` m/s for `lifetime` seconds: over the half space around `normal`, or
## every way when `whole_sphere`. A count or lifetime of 0 starts nothing.
func burst(at: Vector3, normal: Vector3, count: int, speed: float, lifetime: float, color: Color,
		whole_sphere: bool = false) -> void:
	if count <= 0 or lifetime <= 0.0:
		return
	var slot: int = _free_slot()
	var multimesh: MultiMesh = _nodes[slot].multimesh
	multimesh.instance_count = count
	for index: int in count:
		multimesh.set_instance_color(index, color)
	_ages[slot] = 0.0
	_lifetimes[slot] = lifetime
	_starts[slot] = at
	_normals[slot] = normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP
	_speeds[slot] = speed
	_spheres[slot] = whole_sphere
	_place(slot)


## Moves every burst on by `delta` seconds.
func age(delta: float) -> void:
	for slot: int in _nodes.size():
		if _nodes[slot].visible:
			_ages[slot] += delta
			_place(slot)


## The bursts showing now.
func shown() -> Array[MultiMeshInstance3D]:
	var showing: Array[MultiMeshInstance3D] = []
	for node: MultiMeshInstance3D in _nodes:
		if node.visible:
			showing.append(node)
	return showing


## Number of burst nodes in the pool, shown or hidden.
func pool_size() -> int:
	return _nodes.size()


## The way spark `index` of `count` flies, on the unit sphere (a golden-angle
## spiral, so the sparks spread evenly), folded onto the side of `normal`
## unless `whole_sphere`.
static func direction(index: int, count: int, normal: Vector3, whole_sphere: bool) -> Vector3:
	var y: float = 1.0 - 2.0 * (float(index) + 0.5) / float(maxi(count, 1))
	var ring: float = sqrt(maxf(0.0, 1.0 - y * y))
	var turn: float = GOLDEN_ANGLE * float(index)
	var way: Vector3 = Vector3(cos(turn) * ring, y, sin(turn) * ring)
	if not whole_sphere and way.dot(normal) < 0.0:
		way -= 2.0 * way.dot(normal) * normal
	return way.normalized()


func _place(slot: int) -> void:
	var t: float = _ages[slot] / _lifetimes[slot]
	var node: MultiMeshInstance3D = _nodes[slot]
	node.visible = t < 1.0
	if not node.visible:
		return
	node.position = _starts[slot]
	var multimesh: MultiMesh = node.multimesh
	var count: int = multimesh.instance_count
	# Fast out of the hit and slowing, as sparks in air do.
	var travel: float = _speeds[slot] * _lifetimes[slot] * (t - 0.5 * t * t)
	var shrink: float = 1.0 - t
	for index: int in count:
		var way: Vector3 = direction(index, count, _normals[slot], _spheres[slot])
		# Each spark at its own share of the speed, so the burst has depth.
		var share: float = 0.55 + 0.45 * fposmod(float(index) * 0.618034, 1.0)
		var basis: Basis = ProjectileView.bolt_basis(way).scaled(SPARK_SIZE * shrink)
		multimesh.set_instance_transform(index, Transform3D(basis, way * travel * share))


func _free_slot() -> int:
	for slot: int in _nodes.size():
		if not _nodes[slot].visible:
			return slot
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "%s%d" % [BURST_PREFIX, _nodes.size()]
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _mesh
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	_nodes.append(node)
	_ages.append(0.0)
	_lifetimes.append(1.0)
	_starts.append(Vector3.ZERO)
	_normals.append(Vector3.UP)
	_speeds.append(0.0)
	_spheres.append(false)
	return _nodes.size() - 1
