class_name RobotBursts
extends Node3D

## The destruction bursts of `RobotView` (#604, CMB-3): a sphere in the burst
## colour that swells to `burst_radii` of the robot's radius and fades out over
## `burst_seconds`, where a robot left the array. Pooled like the robots.

const NODE_NAME: String = "Bursts"

var _nodes: Array[MeshInstance3D] = []
var _mesh: PrimitiveMesh = RobotView.build_mesh("sphere")


func _init() -> void:
	name = NODE_NAME


## Draws `bursts` (`RobotHitTracker.bursts`) at time `now` with `effects`.
func show_bursts(bursts: Array[Dictionary], effects: Dictionary, now: float) -> void:
	var seconds: float = effects["burst_seconds"]
	while _nodes.size() < bursts.size():
		_add_node()
	for index: int in _nodes.size():
		var instance: MeshInstance3D = _nodes[index]
		instance.visible = index < bursts.size()
		if not instance.visible:
			continue
		var burst: Dictionary = bursts[index]
		var t: float = clampf((now - float(burst["start"])) / seconds, 0.0, 1.0)
		# Fast at first and slowing, as a blast does.
		var grow: float = lerpf(0.5, float(effects["burst_radii"]), 1.0 - pow(1.0 - t, 3.0))
		instance.transform = Transform3D(Basis.from_scale(Vector3.ONE * float(burst["radius"]) * grow),
				burst["position"])
		var color: Color = effects["burst_color"]
		(instance.material_override as StandardMaterial3D).albedo_color = Color(color, 1.0 - t)


## Bursts drawn by the last `show_bursts`.
func visible_count() -> int:
	var count: int = 0
	for instance: MeshInstance3D in _nodes:
		if instance.visible:
			count += 1
	return count


func _add_node() -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = _mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_nodes.append(instance)
