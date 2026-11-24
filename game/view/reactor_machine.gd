class_name ReactorMachine
extends Node3D

## The reactor drawn as a machine around its glowing core (#1310, GFX-2,
## RUN-2): a cage of ribs between two caps, so the core shows through the gaps,
## and coolant pipes running out to the walls. Destroyed, it is a breached,
## burning wreck: some ribs are gone, the rest are scorched, the top cap is
## knocked askew and flames and embers rise from the core (`ReactorFlames`).
##
## Everything is built once from primitives and text materials (ARC-5) in a
## unit space where 1 is the reactor's radius; `set_radius` scales the node.
## Pipe lengths are in metres, from `set_pipe_reach`. It adds no light (GFX-4)
## and no collision, reads no simulation state and writes none (MP-2). The
## look is a parsed `ReactorMachineLook` (ARC-4).

const NODE_NAME: String = "Machine"
const RIB_PREFIX: String = "Rib"
const PIPE_PREFIX: String = "Pipe"

## Times the meshes were built, for tests: built once, never per frame.
var mesh_builds: int = 0

var _look: Dictionary = {}
var _ribs: Array[MeshInstance3D] = []
var _pipes: Array[MeshInstance3D] = []
var _top: MeshInstance3D
var _bottom: MeshInstance3D
var _flames: GPUParticles3D
var _embers: GPUParticles3D
var _housing: StandardMaterial3D
var _pipe_material: StandardMaterial3D
var _scorched: StandardMaterial3D
var _radius: float = 1.0
var _reach_m: PackedFloat32Array = PackedFloat32Array()
var _destroyed: bool = false


## Builds the machine for `look`, a parsed `ReactorMachineLook`.
func _init(look: Dictionary) -> void:
	name = NODE_NAME
	_look = look
	_housing = _material(look["housing_material"])
	_pipe_material = _material(look["pipe_material"])
	_scorched = _material(look["scorched_material"])
	_build_cage()
	_build_pipes()
	_flames = ReactorFlames.flames(look)
	_embers = ReactorFlames.embers(look)
	add_child(_flames)
	add_child(_embers)
	set_radius(1.0)
	set_destroyed(false)


## The look the machine was built from.
func look() -> Dictionary:
	return _look


## Scales the machine to a reactor of `radius` metres and refits the pipes.
func set_radius(radius: float) -> void:
	_radius = maxf(radius, 0.001)
	scale = Vector3.ONE * _radius
	_fit_pipes()


## Sets how far each pipe may run, in metres from the reactor's centre, one
## value per pipe in `pipe_directions` order. Missing values use
## `pipe_max_length_m`.
func set_pipe_reach(reach_m: PackedFloat32Array) -> void:
	_reach_m = reach_m
	_fit_pipes()


## Shows the intact machine or the breached, burning wreck. Cheap to call every
## frame: it only changes visibility, materials and one transform.
func set_destroyed(destroyed: bool) -> void:
	_destroyed = destroyed
	var breached: int = int(_look["breached_ribs"]) if destroyed else 0
	for index: int in _ribs.size():
		_ribs[index].visible = index >= breached
		_ribs[index].material_override = _scorched if destroyed else _housing
	_top.material_override = _scorched if destroyed else _housing
	_bottom.material_override = _scorched if destroyed else _housing
	var tilt: float = deg_to_rad(float(_look["wreck_cap_tilt_deg"])) if destroyed else 0.0
	var top_y: float = float(_look["housing_height_r"]) * 0.5
	_top.transform = Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0.0, top_y, sin(tilt) * float(_look["cap_radius_r"]) * 0.5))
	_flames.emitting = destroyed and int(_flames.get_meta("amount_wanted")) > 0
	_embers.emitting = destroyed and int(_embers.get_meta("amount_wanted")) > 0


## Holds the flames still while the session is paused (CMF-8).
func set_frozen(frozen: bool) -> void:
	_flames.speed_scale = 0.0 if frozen else 1.0
	_embers.speed_scale = 0.0 if frozen else 1.0


func destroyed() -> bool:
	return _destroyed


func ribs() -> Array[MeshInstance3D]:
	return _ribs


func pipes() -> Array[MeshInstance3D]:
	return _pipes


func top_cap() -> MeshInstance3D:
	return _top


func flames() -> GPUParticles3D:
	return _flames


func embers() -> GPUParticles3D:
	return _embers


## Unit directions the pipes leave the reactor in, evenly round the vertical
## axis from `pipe_angle_deg`.
func pipe_directions() -> Array[Vector3]:
	return directions(_look)


## The pipes' directions for `look`, in order.
static func directions(look: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count: int = int(look["pipes"])
	for index: int in count:
		var angle: float = deg_to_rad(float(look["pipe_angle_deg"])) + TAU * float(index) / float(count)
		result.append(Vector3(cos(angle), 0.0, sin(angle)))
	return result


## Where the pipes leave from, relative to the reactor's centre, in metres.
static func pipe_origin(look: Dictionary, radius: float) -> Vector3:
	return Vector3(0.0, float(look["pipe_height_r"]) * radius, 0.0)


## Metres from the reactor's centre, along each pipe, that `walls` stay open
## for, to at most `pipe_max_length_m`; the pipe ends where it meets the rock.
## `walls` is read only (view may read core).
static func reach_in(walls: BoxUnion, look: Dictionary, centre: Vector3, radius: float) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	var origin: Vector3 = centre + pipe_origin(look, radius)
	var longest: float = float(look["pipe_max_length_m"])
	for direction: Vector3 in directions(look):
		var reach: float = 0.0
		var step: float = 0.25
		while reach + step <= longest and walls.holds(origin + direction * (reach + step), 0.0):
			reach += step
		# Half a step more puts the pipe's end inside the rock, not short of it.
		result.append(minf(reach + step * 0.5, longest))
	return result


func _build_cage() -> void:
	var rib_mesh: BoxMesh = BoxMesh.new()
	rib_mesh.size = Vector3(float(_look["rib_width_r"]), float(_look["housing_height_r"]), float(_look["rib_depth_r"]))
	mesh_builds += 1
	var count: int = int(_look["ribs"])
	var ring: float = float(_look["housing_radius_r"])
	for index: int in count:
		var angle: float = TAU * float(index) / float(count)
		var rib: MeshInstance3D = _instance("%s%d" % [RIB_PREFIX, index], rib_mesh)
		var outward: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		rib.transform = Transform3D(Basis(Vector3.UP, -angle + PI * 0.5), outward * ring)
		_ribs.append(rib)
	var cap: CylinderMesh = CylinderMesh.new()
	cap.top_radius = float(_look["cap_radius_r"])
	cap.bottom_radius = float(_look["cap_radius_r"])
	cap.height = float(_look["cap_height_r"])
	cap.radial_segments = 16
	cap.rings = 1
	mesh_builds += 1
	_top = _instance("TopCap", cap)
	_bottom = _instance("BottomCap", cap)
	_bottom.position = Vector3(0.0, -float(_look["housing_height_r"]) * 0.5, 0.0)


func _build_pipes() -> void:
	if int(_look["pipes"]) == 0:
		return
	var pipe: CylinderMesh = CylinderMesh.new()
	pipe.top_radius = float(_look["pipe_radius_r"])
	pipe.bottom_radius = float(_look["pipe_radius_r"])
	pipe.height = 1.0
	pipe.radial_segments = 8
	pipe.rings = 1
	mesh_builds += 1
	var directions_now: Array[Vector3] = pipe_directions()
	for index: int in directions_now.size():
		var node: MeshInstance3D = _instance("%s%d" % [PIPE_PREFIX, index], pipe)
		node.material_override = _pipe_material
		_pipes.append(node)


## Lays each pipe from the housing out to its reach. Pipe lengths are metres,
## the node is in radius units, so they are refitted when the radius changes.
func _fit_pipes() -> void:
	var directions_now: Array[Vector3] = pipe_directions()
	var start: float = float(_look["housing_radius_r"])
	var height: float = float(_look["pipe_height_r"])
	for index: int in _pipes.size():
		var reach_m: float = _reach_m[index] if index < _reach_m.size() else float(_look["pipe_max_length_m"])
		var length: float = reach_m / _radius - start
		var pipe: MeshInstance3D = _pipes[index]
		pipe.visible = length > 0.0
		if not pipe.visible:
			continue
		var direction: Vector3 = directions_now[index]
		# The cylinder runs along y; turn y onto the pipe's direction.
		var basis: Basis = Basis(direction.cross(Vector3.UP).normalized(), -PI * 0.5) * Basis.from_scale(Vector3(1.0, length, 1.0))
		var middle: Vector3 = direction * (start + length * 0.5) + Vector3(0.0, height, 0.0)
		pipe.transform = Transform3D(basis, middle)


func _instance(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


static func _material(values: Dictionary) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = values["color"]
	material.metallic = float(values["metallic"])
	material.roughness = float(values["roughness"])
	return material
