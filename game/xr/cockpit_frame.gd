class_name CockpitFrame
extends Node3D

## The cockpit frame around the eye point, built from a `CockpitSpec` with
## primitive meshes only: no imported models, no collision (CMF-1, NAM-3).
##
## This node's origin is the eye point and -Z is straight ahead. The frame is
## a shell over the forward half of the view at `frame_distance_m`: solid
## panels outside the window, tinted glass inside it, and struts along the
## window's edges. Each kind is one `MultiMeshInstance3D`, so the whole frame
## costs three draw calls on the headset.
##
## The frame reads only its spec. It never reads or writes simulation state
## (ARC-3, MP-2); a preset change rebuilds it and touches nothing else.

## Largest angle one shell panel or strut segment spans, degrees. Smaller
## panels follow the curve more closely and cost more instances.
const CELL_DEG: float = 10.0
## Panels are drawn this much larger than their cell so neighbours overlap
## and no gap shows between them.
const OVERLAP: float = 1.05
## Gap between the struts and the shell, metres, so they never z-fight.
const STRUT_GAP_M: float = 0.002

const SOLID_COLOR: Color = Color(0.16, 0.17, 0.19)
const STRUT_COLOR: Color = Color(0.3, 0.32, 0.36)
const GLASS_COLOR: Color = Color(0.55, 0.75, 0.85)

var spec: CockpitSpec = null
## Instance transforms of each built part, by part name. Kept here because a
## headless renderer does not store multimesh transforms for reading back.
var _transforms: Dictionary[String, Array] = {}


func _init(p_spec: CockpitSpec = null) -> void:
	name = "CockpitFrame"
	if p_spec != null:
		set_spec(p_spec)


## Replaces the frame with one built from `p_spec`.
func set_spec(p_spec: CockpitSpec) -> void:
	spec = p_spec
	_transforms.clear()
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_build()


## The built part named `part_name` ("Solid", "Glass" or "Struts"), or null
## when this frame has none.
func part(part_name: String) -> MultiMeshInstance3D:
	return get_node_or_null(part_name) as MultiMeshInstance3D


## Number of instances in part `part_name`; 0 when it is missing.
func instance_count(part_name: String) -> int:
	return instance_transforms(part_name).size()


## Where each instance of part `part_name` sits, in this node's space.
func instance_transforms(part_name: String) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.assign(_transforms.get(part_name, []))
	return result


func _build() -> void:
	var yaw_breaks: PackedFloat32Array = _breaks(spec.window_half_angle_h_deg)
	var pitch_breaks: PackedFloat32Array = _breaks(spec.window_half_angle_v_deg)
	var solid: Array[Transform3D] = []
	var glass: Array[Transform3D] = []
	for i: int in yaw_breaks.size() - 1:
		for j: int in pitch_breaks.size() - 1:
			var yaw_a: float = yaw_breaks[i]
			var yaw_b: float = yaw_breaks[i + 1]
			var pitch_a: float = pitch_breaks[j]
			var pitch_b: float = pitch_breaks[j + 1]
			var inside: bool = absf((yaw_a + yaw_b) * 0.5) < spec.window_half_angle_h_deg \
				and absf((pitch_a + pitch_b) * 0.5) < spec.window_half_angle_v_deg
			var panel: Transform3D = _panel(yaw_a, yaw_b, pitch_a, pitch_b)
			if inside:
				glass.append(panel)
			else:
				solid.append(panel)
	_add_part("Solid", _quad(), _material(SOLID_COLOR), solid)
	if spec.glass_tint_alpha > 0.0:
		var tint: Color = GLASS_COLOR
		tint.a = spec.glass_tint_alpha
		_add_part("Glass", _quad(), _material(tint), glass)
	_add_part("Struts", _box(), _material(STRUT_COLOR), _struts(yaw_breaks, pitch_breaks))


## Edges of the shell's cells along one axis, degrees from -90 to 90. The
## window's edges at -`half` and `half` are always among them, so every cell
## lies wholly inside or wholly outside the window.
static func _breaks(half: float) -> PackedFloat32Array:
	var breaks: PackedFloat32Array = [-90.0]
	for span: Vector2 in [Vector2(-90.0, -half), Vector2(-half, half), Vector2(half, 90.0)]:
		var length: float = span.y - span.x
		if length <= 0.0:
			continue
		var steps: int = ceili(length / CELL_DEG)
		for k: int in range(1, steps + 1):
			breaks.append(span.x + length * k / steps)
	return breaks


## Unit vector from the eye at `yaw` degrees right and `pitch` degrees up.
static func direction(yaw: float, pitch: float) -> Vector3:
	var y: float = deg_to_rad(yaw)
	var p: float = deg_to_rad(pitch)
	return Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))


## A basis whose X runs along increasing yaw, Y along increasing pitch, and Z
## back toward the eye, so a quad on it faces the eye.
static func _facing_basis(yaw: float, pitch: float) -> Basis:
	var y: float = deg_to_rad(yaw)
	var p: float = deg_to_rad(pitch)
	var along_yaw: Vector3 = Vector3(cos(y), 0.0, sin(y))
	var along_pitch: Vector3 = Vector3(-sin(y) * sin(p), cos(p), cos(y) * sin(p))
	return Basis(along_yaw, along_pitch, -direction(yaw, pitch))


## One flat shell panel covering the cell, at the frame distance, facing the eye.
func _panel(yaw_a: float, yaw_b: float, pitch_a: float, pitch_b: float) -> Transform3D:
	var yaw: float = (yaw_a + yaw_b) * 0.5
	var pitch: float = (pitch_a + pitch_b) * 0.5
	var d: float = spec.frame_distance_m
	# The cell is widest on the edge nearest the horizon.
	var widest: float = cos(deg_to_rad(minf(absf(pitch_a), absf(pitch_b)))) \
		if signf(pitch_a) == signf(pitch_b) else 1.0
	var width: float = d * widest * deg_to_rad(yaw_b - yaw_a) * OVERLAP
	var height: float = d * deg_to_rad(pitch_b - pitch_a) * OVERLAP
	var basis: Basis = _facing_basis(yaw, pitch).scaled_local(Vector3(width, height, 1.0))
	return Transform3D(basis, direction(yaw, pitch) * d)


## Strut segments along the window's edges. An edge at 90 degrees is the rim
## of the shell, so it gets no strut.
func _struts(yaw_breaks: PackedFloat32Array, pitch_breaks: PackedFloat32Array) -> Array[Transform3D]:
	var h: float = spec.window_half_angle_h_deg
	var v: float = spec.window_half_angle_v_deg
	var segments: Array[Transform3D] = []
	for j: int in pitch_breaks.size() - 1:
		if pitch_breaks[j] < -v or pitch_breaks[j + 1] > v or h >= 90.0:
			continue
		for side: float in [-h, h]:
			segments.append(_strut(Vector2(side, pitch_breaks[j]), Vector2(side, pitch_breaks[j + 1])))
	for i: int in yaw_breaks.size() - 1:
		if yaw_breaks[i] < -h or yaw_breaks[i + 1] > h or v >= 90.0:
			continue
		for side: float in [-v, v]:
			segments.append(_strut(Vector2(yaw_breaks[i], side), Vector2(yaw_breaks[i + 1], side)))
	return segments


## A square strut from angle `a` to angle `b` (x yaw, y pitch), just inside the shell.
func _strut(a: Vector2, b: Vector2) -> Transform3D:
	var w: float = spec.strut_width_m
	var radius: float = spec.frame_distance_m - STRUT_GAP_M - w * 0.5
	var start: Vector3 = direction(a.x, a.y) * radius
	var end: Vector3 = direction(b.x, b.y) * radius
	var middle: Vector3 = (start + end) * 0.5
	var along: Vector3 = (end - start).normalized()
	var back: Vector3 = -middle.normalized()
	back = (back - along * back.dot(along)).normalized()
	var basis: Basis = Basis(along, back.cross(along), back)
	basis = basis.scaled_local(Vector3(start.distance_to(end) + w, w, w))
	return Transform3D(basis, middle)


func _add_part(part_name: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	_transforms[part_name] = transforms
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for k: int in transforms.size():
		multimesh.set_instance_transform(k, transforms[k])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = part_name
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


static func _quad() -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2.ONE
	return mesh


static func _box() -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
