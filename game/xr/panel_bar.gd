class_name PanelBar
extends RefCounted

## One horizontal bar on the status panel: a dark track and a coloured fill
## that empties towards the left. Split out of `StatusPanel` when the shield
## and hull bars joined the energy bar (#227), so all three are built and
## drawn the same way and the panel stays short.
##
## The two meshes are added straight under the panel, so anything that walks
## the panel's children (the depth and priority tests, #199) sees them.

const WIDTH: float = 0.12
const HEIGHT: float = 0.012
## Centre of the full bar on the panel; the bar's label sits to its left.
const CENTRE_X: float = 0.0
const TRACK_COLOR: Color = Color(0.15, 0.2, 0.25)
## The track sits a millimetre behind the fill. Depth no longer decides what
## draws on top (render priority does), but it keeps the order sensible if a
## material ever gets its depth test back.
const TRACK_DEPTH: float = -0.001

var track: MeshInstance3D
var fill: MeshInstance3D


## Adds the track and the fill, named as given, under `panel` at height `y`. The track draws at `priority`, the fill one step above it so the
## track never covers it.
func _init(panel: Node3D, track_name: String, fill_name: String, color: Color,
		y: float, priority: int) -> void:
	track = _quad(track_name, TRACK_COLOR, Vector3(CENTRE_X, y, TRACK_DEPTH), priority)
	fill = _quad(fill_name, color, Vector3(CENTRE_X, y, 0.0), priority + 1)
	panel.add_child(track)
	panel.add_child(fill)
	set_fraction(1.0)


## Sets the fill to `fraction` of the full bar, clamped to 0..1; anything not
## finite counts as empty. Returns the fraction drawn.
func set_fraction(fraction: float) -> float:
	var clamped: float = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0
	fill.scale = Vector3(clamped, 1.0, 1.0)
	# Anchored at the left end, so the bar empties towards the left.
	fill.position.x = CENTRE_X + WIDTH * (clamped - 1.0) * 0.5
	return clamped


## The fill's length as a fraction of the full bar, 0..1.
func fraction() -> float:
	return fill.scale.x


static func _quad(quad_name: String, color: Color, at: Vector3, priority: int) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = priority
	var bar: MeshInstance3D = MeshInstance3D.new()
	bar.name = quad_name
	bar.mesh = quad
	bar.material_override = material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position = at
	return bar
