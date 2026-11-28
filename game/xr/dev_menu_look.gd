class_name DevMenuLook
extends RefCounted

## How the development menu's rows are drawn beside their words (#1458,
## record 0012's "menus were overwhelming because of the text"): the sizes,
## colours and draw order of its icons, value drawings and backing plate, and
## the materials they share. Presentation only (ARC-3, MP-2).
##
## A row reads, left to right: its icon, its label, its value drawing and,
## on the highlighted row only, the value's words. The plate behind the rows
## is the base screens' face colour, so the menu is held to the base's
## readability thresholds (#1359): words and lit marks at least
## `MIN_TEXT_CONTRAST` against it, dim marks and icons at least
## `MIN_SHAPE_CONTRAST`, as the station icons are.

const ICON_M: float = 0.045
const GAP_M: float = 0.02
## The value drawing's column: a switch, a row of marks or a bar fits it.
const DRAW_W_M: float = 0.09
const DRAW_H_M: float = 0.028
const SWITCH_W_M: float = 0.06
const MARK_M: float = 0.014
const BAR_H_M: float = 0.014
## Margin of the plate round the rows.
const PAD_M: float = 0.03
## Words a hair in front of the plate and the shapes, though none of them
## is depth tested: the order is the render priorities below.
const TEXT_Z_M: float = 0.004
const PLATE_Z_M: float = -0.004
## Under the menu's words (`DevMenu.RENDER_PRIORITY`); the plate first, then
## each shape's parts in order, at most `SHAPE_LAYERS` deep.
const PLATE_PRIORITY: int = Material.RENDER_PRIORITY_MAX - 9
const SHAPE_PRIORITY: int = Material.RENDER_PRIORITY_MAX - 8
const SHAPE_LAYERS: int = 5

## The base screens' face (`hub_screen.json` `screen_color`).
const PLATE_COLOR: Color = Color(0.02, 0.035, 0.05)
const LIT_COLOR: Color = Color(0.93, 0.97, 1.0)
const DIM_COLOR: Color = Color(0.36, 0.4, 0.45)
const ON_TRACK_COLOR: Color = Color(0.25, 0.62, 0.36)
const OFF_KNOB_COLOR: Color = Color(0.62, 0.66, 0.72)
const MIN_TEXT_CONTRAST: float = 7.0
const MIN_SHAPE_CONTRAST: float = 3.0
## Average glyph width over font size, for a font that measures nothing.
const GLYPH_WIDTH: float = 0.55

static var _materials: Dictionary[String, StandardMaterial3D] = {}


## An unshaded material that draws over everything, after lower `priority`.
static func material(color: Color, priority: int) -> StandardMaterial3D:
	var key: String = "%s@%d" % [color.to_html(), priority]
	if _materials.has(key):
		return _materials[key]
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # So the priorities order it with the words.
	made.no_depth_test = true
	made.cull_mode = BaseMaterial3D.CULL_DISABLED
	made.albedo_color = color
	made.render_priority = priority
	_materials[key] = made
	return made


## The priority of a shape's `layer`-th part, deeper parts held at the last.
static func shape_priority(layer: int) -> int:
	return SHAPE_PRIORITY + mini(layer, SHAPE_LAYERS - 1)


## A flat rectangle `size` across, centred at `at`, drawn at `layer`.
static func rect(size: Vector2, at: Vector3, color: Color, layer: int, layers: int) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position = at
	mesh.material_override = material(color, shape_priority(layer))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.layers = layers
	return mesh


## How wide `text` is drawn at `font_size` and `pixel_size`, in metres.
static func text_width_m(text: String, font_size: int, pixel_size: float) -> float:
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x \
		if font != null else 0.0
	if width <= 0.0:
		width = text.length() * font_size * GLYPH_WIDTH
	return width * pixel_size
