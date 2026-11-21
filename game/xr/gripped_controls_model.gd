class_name GrippedControlsModel
extends Node3D

## The visible virtual stick or throttle of the gripped scheme (#740, PLT-5).
## The caller places one at each hand's grab point and passes the same
## grab-relative pose `GrippedStickMapping` reads, so what the pilot sees is
## what the ship gets: the pose is clamped to the mapping's full deflection,
## past which the ship turns or thrusts no harder.
##
## View only: it reads no input device and writes no simulation state (ARC-3).
## Unlit and half see-through so it reads in a dark mine (look in
## `res://xr/gripped_controls_look.json`, ARC-4). Unwired for now.
##
## The stick is a short shaft with a knob that tilts and twists about the grab
## point. The throttle is a fixed base with a handle that moves with the hand.

const STICK: String = "stick"
const THROTTLE: String = "throttle"
const KINDS: Array[String] = [STICK, THROTTLE]
const MOVING_NAME: String = "Moving"

## Which control this is, one of `KINDS`.
var kind: String = STICK
## Set when the look file was rejected and the built-in look is used.
var look_error: String = ""

var _look: Dictionary = GrippedControlsLook.FALLBACK
var _moving: Node3D
var _material: StandardMaterial3D
var _dimmed: bool = true


func _init(control: String = STICK, look_path: String = GrippedControlsLook.DEFAULT_FILE) -> void:
	kind = control if KINDS.has(control) else STICK
	name = "Gripped" + kind.capitalize()
	var loaded: Dictionary = GrippedControlsLook.load_file(look_path)
	_look = loaded["look"]
	look_error = loaded["error"]
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_moving = Node3D.new()
	_moving.name = MOVING_NAME
	add_child(_moving)
	if kind == STICK:
		_build_stick()
	else:
		_build_throttle()
	release()


## Shows a grab-relative hand pose, clamped to full deflection, at full alpha.
func show_pose(pose: Transform3D) -> void:
	if kind == STICK:
		_moving.transform = Transform3D(clamped_stick_basis(pose.basis), Vector3.ZERO)
	else:
		_moving.transform = Transform3D(Basis.IDENTITY, clamped_throttle_offset(pose.origin))
	_set_dimmed(false)


## Centres the control and dims it: the hand let go.
func release() -> void:
	_moving.transform = Transform3D.IDENTITY
	_set_dimmed(true)


func dimmed() -> bool:
	return _dimmed


func alpha() -> float:
	return _material.albedo_color.a


func look() -> Dictionary:
	return _look


## The moving part's transform under the grab point.
func shown_pose() -> Transform3D:
	return _moving.transform


## `rotation` with its tilts and twist, as `GrippedStickMapping.stick_angles`
## reads them, clamped to the angles that give full pitch, roll and yaw.
static func clamped_stick_basis(rotation: Basis) -> Basis:
	var angles: Vector3 = GrippedStickMapping.stick_angles(rotation)
	var tilt: float = GrippedStickMapping.STICK_TILT_FULL_RAD
	var twist_full: float = GrippedStickMapping.STICK_TWIST_FULL_RAD
	var right: float = clampf(angles.x, -tilt, tilt)
	var ahead: float = clampf(angles.z, -tilt, tilt)
	var twist: float = clampf(angles.y, -twist_full, twist_full)
	# The inverse of `stick_angles`: swing the top to the clamped tilts, then
	# twist about the stick's own axis (clockwise from above is negative y).
	var top: Vector3 = Vector3(tan(right), 1.0, -tan(ahead)).normalized()
	var swing: Quaternion = Quaternion(Vector3.UP, top)
	return Basis(swing * Quaternion(Vector3.UP, -twist))


## `offset` with each axis clamped to the throttle's full travel; the mapping
## reads the axes separately, so each is clamped on its own.
static func clamped_throttle_offset(offset: Vector3) -> Vector3:
	var full: float = GrippedStickMapping.THROTTLE_FULL_M
	return Vector3(clampf(offset.x, -full, full), clampf(offset.y, -full, full), clampf(offset.z, -full, full))


func _set_dimmed(value: bool) -> void:
	_dimmed = value
	var colour: Color = _look["color"]
	colour.a = float(_look["dimmed_alpha"] if value else _look["alpha"])
	_material.albedo_color = colour


func _build_stick() -> void:
	var length: float = float(_look["stick_length_m"])
	var shaft: CylinderMesh = CylinderMesh.new()
	shaft.height = length
	shaft.top_radius = float(_look["stick_radius_m"])
	shaft.bottom_radius = float(_look["stick_radius_m"])
	_add_mesh(_moving, "Shaft", shaft, Vector3(0.0, length / 2.0, 0.0))
	var knob: SphereMesh = SphereMesh.new()
	knob.radius = float(_look["knob_radius_m"])
	knob.height = 2.0 * float(_look["knob_radius_m"])
	_add_mesh(_moving, "Knob", knob, Vector3(0.0, length, 0.0))


func _build_throttle() -> void:
	var base: BoxMesh = BoxMesh.new()
	var base_size: float = float(_look["throttle_base_m"])
	base.size = Vector3(base_size, base_size / 6.0, base_size)
	# The base sits below the grab point so the handle starts inside it.
	_add_mesh(self, "Base", base, Vector3(0.0, -float(_look["throttle_handle_m"]) / 2.0, 0.0))
	var handle: BoxMesh = BoxMesh.new()
	handle.size = Vector3.ONE * float(_look["throttle_handle_m"])
	_add_mesh(_moving, "Handle", handle, Vector3.ZERO)


func _add_mesh(parent: Node3D, mesh_name: String, mesh: PrimitiveMesh, at: Vector3) -> void:
	mesh.material = _material
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = mesh_name
	node.mesh = mesh
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
