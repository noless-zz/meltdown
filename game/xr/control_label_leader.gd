class_name ControlLabelLeader
extends MeshInstance3D

## The leader line from one control label to its part (PLT-5, #1316): a flat
## strip `width` metres wide lying in the plane that faces the eye, so its
## width is data (`ControlLabelLayout` `leader_width_m`); a line primitive is
## always one screen pixel, too thin to follow at arm's length.

const PREFIX: String = "Leader_"

var start: Vector3 = Vector3.ZERO
var end: Vector3 = Vector3.ZERO
var width: float = 0.0
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _material: Material = null


func _init(control: String, material: Material) -> void:
	name = PREFIX + control
	_material = material
	mesh = _mesh


## Redraws the strip from `p_start` to `p_end`, `p_width` across, flat to
## `facing` (towards the eye). A strip of zero length draws nothing.
func draw(p_start: Vector3, p_end: Vector3, p_width: float, facing: Vector3) -> void:
	start = p_start
	end = p_end
	width = p_width
	_mesh.clear_surfaces()
	var along: Vector3 = p_end - p_start
	var across: Vector3 = facing.cross(along)
	if along.is_zero_approx() or across.is_zero_approx():
		return
	across = across.normalized() * 0.5 * p_width
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for corner: Vector3 in [p_start - across, p_start + across, p_end + across,
			p_start - across, p_end + across, p_end - across]:
		_mesh.surface_add_vertex(corner)
	_mesh.surface_end()
