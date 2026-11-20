class_name HitFlashOverlay
extends Node3D

## The edge flash of `HitFlash` (#618): four strips just in front of the eyes,
## one along each edge of the view, that fade from the outer edge inwards.
## A hit lights the strip on its side; `HitFlash.FRONT` lights all four.
##
## It hangs under the camera so it stays at the edges whichever way the head
## turns, and it never moves the camera or anything else (CMF-8). Unshaded,
## alpha-blended quads with a tiny gradient texture, drawn over everything and
## hidden when not flashing, so it costs nothing between hits (PRF-2).

const NODE_NAME: String = "HitFlashOverlay"
## As close as the reset fade (`FadeOverlay.DISTANCE`), inside any wall.
const DISTANCE: float = 0.1
## Length of each strip along its edge, metres: past the view's corners.
const LENGTH: float = 0.3
## Below the reset fade and the destroyed screen, which must cover the flash.
const RENDER_PRIORITY: int = Material.RENDER_PRIORITY_MAX - 3

var _strips: Dictionary[String, MeshInstance3D] = {}


## Builds the four strips from `flash`'s inset and width.
func _init(flash: HitFlash = HitFlash.new()) -> void:
	name = NODE_NAME
	position = Vector3(0.0, 0.0, -DISTANCE)
	var middle: float = flash.edge_inset_m + flash.edge_width_m * 0.5
	# Each strip's local +X points outwards, where the gradient is opaque.
	_strips[HitFlash.RIGHT] = _strip(HitFlash.RIGHT, flash, Vector3(middle, 0.0, 0.0), 0.0)
	_strips[HitFlash.TOP] = _strip(HitFlash.TOP, flash, Vector3(0.0, middle, 0.0), PI * 0.5)
	_strips[HitFlash.LEFT] = _strip(HitFlash.LEFT, flash, Vector3(-middle, 0.0, 0.0), PI)
	_strips[HitFlash.BOTTOM] = _strip(HitFlash.BOTTOM, flash, Vector3(0.0, -middle, 0.0), -PI * 0.5)
	for strip: MeshInstance3D in _strips.values():
		add_child(strip)
	show_flash("", 0.0, flash.edge_color)


## Lights the strip on `side` (all four for `HitFlash.FRONT`) in `color` at
## `opacity`, 0..1, and hides the rest. An opacity of 0 or an empty side hides all.
func show_flash(side: String, opacity: float, color: Color) -> void:
	var alpha: float = clampf(opacity, 0.0, 1.0)
	for strip_side: String in _strips:
		var strip: MeshInstance3D = _strips[strip_side]
		var lit: bool = alpha > 0.0 and (side == strip_side or side == HitFlash.FRONT)
		strip.visible = lit
		if lit:
			(strip.material_override as StandardMaterial3D).albedo_color = Color(color, alpha)


## The sides whose strip shows now, for tests.
func lit_sides() -> Array[String]:
	var lit: Array[String] = []
	for strip_side: String in _strips:
		if _strips[strip_side].visible:
			lit.append(strip_side)
	return lit


static func _strip(strip_name: String, flash: HitFlash, at: Vector3, turn: float) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(flash.edge_width_m, LENGTH)
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 1.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 1
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = RENDER_PRIORITY
	material.albedo_texture = texture
	var strip: MeshInstance3D = MeshInstance3D.new()
	strip.name = "Edge_%s" % strip_name
	strip.mesh = quad
	strip.material_override = material
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.extra_cull_margin = 16384.0
	strip.ignore_occlusion_culling = true
	strip.transform = Transform3D(Basis(Vector3.BACK, turn), at)
	return strip
