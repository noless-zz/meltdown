class_name ConsoleGauges
extends Node3D

## Hull, shield and energy as lit instruments on the ship's console (#1461,
## GFX-2, CMF-8, PLT-5, ARC-4). The cockpit frame builds one of these from its
## file's `instruments` list (`CockpitInstrument`) as a child, so the
## instruments are part of the cockpit model: they move only with the frame,
## never with the head, and a preset change rebuilds them with the frame.
##
## Each instrument is a dark bezel with its label at the top and a bar below
## it, the bar's empty part drawn dim in the same colour. Everything is
## unshaded, so it glows at the same brightness in a dark mine and adds no
## light (GFX-4). Five draw calls in all: the bezels in one multimesh, the bars
## and their tracks in another, and one per label.
##
## View only: `show_gauges` takes this frame's `ShipGauges` snapshot, the same
## one the status panel shows, and nothing here reads or writes the simulation
## (ARC-3, MP-2).

const NODE_NAME: String = "ConsoleGauges"
## The face's colour, behind label and bar; dark so both stand out from it
## and it stands out from the lighter dash (`test_console_gauges.gd`).
const BEZEL_COLOR: Color = Color(0.03, 0.035, 0.04)
const LABEL_COLOR: Color = Color(0.85, 0.95, 1.0)
## The empty part of a bar is its colour at this share.
const TRACK_SHARE: float = 0.15
## Bezel depth behind the face, metres.
const BEZEL_DEPTH_M: float = 0.008
## Gap round the bar inside the bezel, metres.
const MARGIN_M: float = 0.006
## The bar's height and centre as shares of the face's height.
const BAR_HEIGHT_SHARE: float = 0.3
const BAR_Y_SHARE: float = -0.22
## The label's centre as a share of the face's height.
const LABEL_Y_SHARE: float = 0.2
## Label text in the status panel's own size (`StatusPanel.SMALL_FONT`).
const LABEL_FONT: int = 32
## Track and bar sit this far in front of the face, metres, so neither fights
## the bezel or the other for depth.
const TRACK_LIFT_M: float = 0.001
const FILL_LIFT_M: float = 0.002

var instruments: Array[CockpitInstrument] = []
## Seconds since the instruments were built; the low state's pulse runs on it.
var time_s: float = 0.0
## Frames shown since built.
var updates: int = 0
## The value each instrument showed last, by id; 1 before any frame.
var shown: Dictionary[String, float] = {}
## Frames each instrument showed its low state, by id.
var low_frames: Dictionary[String, int] = {}

var _bezels: MultiMeshInstance3D = null
var _bars: MultiMeshInstance3D = null
## Each instrument's place on the frame, kept here because a headless renderer
## does not store multimesh transforms for reading back.
var _places: Array[Transform3D] = []
var _bar_colors: Array[Color] = []


func _init(list: Array[CockpitInstrument] = []) -> void:
	name = NODE_NAME
	instruments = list
	_build()


## The gauges child of `frame`, or null when its file declares no instruments
## or there is no frame.
static func of_frame(frame: Node3D) -> ConsoleGauges:
	return frame.get_node_or_null(NODE_NAME) as ConsoleGauges if frame != null else null


## Shows `gauges` on the instruments of `frame`'s console, if it has any, and
## runs their pulse on by `delta` seconds.
static func feed(frame: Node3D, gauges: ShipGauges, delta: float) -> void:
	var console: ConsoleGauges = of_frame(frame)
	if console != null and gauges != null:
		console.show_gauges(gauges, delta)


## Draws this frame's `gauges`.
func show_gauges(gauges: ShipGauges, delta: float) -> void:
	time_s += maxf(delta, 0.0)
	updates += 1
	for index: int in instruments.size():
		var instrument: CockpitInstrument = instruments[index]
		var value: float = instrument.fill(gauges.value(instrument.gauge))
		shown[instrument.id] = value
		if instrument.is_low(value):
			low_frames[instrument.id] = low_frames.get(instrument.id, 0) + 1
		_draw_bar(index, value)


## Whether instrument `id` shows its low state now.
func is_low_shown(id: String) -> bool:
	var instrument: CockpitInstrument = instrument_named(id)
	return instrument != null and instrument.is_low(shown.get(id, 1.0))


## The instrument with `id`, or null.
func instrument_named(id: String) -> CockpitInstrument:
	for instrument: CockpitInstrument in instruments:
		if instrument.id == id:
			return instrument
	return null


## Where instrument `index`'s face sits, in the frame's space.
func place(index: int) -> Transform3D:
	return _places[index]


## The colour the bar of instrument `index` is drawn in now.
func bar_color(index: int) -> Color:
	return _bar_colors[index]


## Angular height, degrees, of a label's text on `instrument` seen from the eye.
static func label_angle_deg(instrument: CockpitInstrument) -> float:
	var height: float = float(LABEL_FONT) * StatusPanel.PIXEL_SIZE
	return rad_to_deg(2.0 * atan(height * 0.5 / instrument.distance_m))


## WCAG contrast ratio of two colours, 1..21, from their relative luminance.
static func contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _build() -> void:
	if instruments.is_empty():
		return
	for instrument: CockpitInstrument in instruments:
		var at: Transform3D = Transform3D(CockpitGeometry.facing_basis(instrument.yaw_deg, instrument.pitch_deg),
			CockpitGeometry.direction(instrument.yaw_deg, instrument.pitch_deg) * instrument.distance_m)
		_places.append(at)
		_bar_colors.append(instrument.color)
		shown[instrument.id] = 1.0
		low_frames[instrument.id] = 0
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	_bezels = _multimesh("Bezels", box, false, instruments.size())
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	# Two instances per instrument: its track at 2i, its bar at 2i + 1.
	_bars = _multimesh("Bars", quad, true, instruments.size() * 2)
	for index: int in instruments.size():
		var instrument: CockpitInstrument = instruments[index]
		var face: Vector3 = Vector3(instrument.size_m.x, instrument.size_m.y, BEZEL_DEPTH_M)
		_bezels.multimesh.set_instance_transform(index,
			_places[index] * Transform3D(Basis.from_scale(face), Vector3(0.0, 0.0, -BEZEL_DEPTH_M * 0.5)))
		_bars.multimesh.set_instance_transform(index * 2, _places[index] * _bar_piece(instrument, 1.0, TRACK_LIFT_M))
		_bars.multimesh.set_instance_color(index * 2, _track_color(instrument.color))
		_draw_bar(index, 1.0)
		if instrument.label != "":
			_add_label(instrument, index)


func _draw_bar(index: int, value: float) -> void:
	var instrument: CockpitInstrument = instruments[index]
	var color: Color = instrument.bar_color(value, time_s)
	_bar_colors[index] = color
	_bars.multimesh.set_instance_transform(index * 2 + 1, _places[index] * _bar_piece(instrument, value, FILL_LIFT_M))
	_bars.multimesh.set_instance_color(index * 2 + 1, color)
	# The track takes the low colour too, so the whole bar reads as low.
	var base: Color = instrument.low_color if instrument.is_low(value) else instrument.color
	_bars.multimesh.set_instance_color(index * 2, _track_color(base))


## A unit quad scaled and moved to the bar's left `fill` share, `lift` in
## front of the face. An empty bar keeps a sliver so the transform stays valid.
static func _bar_piece(instrument: CockpitInstrument, fill: float, lift: float) -> Transform3D:
	var width: float = maxf(instrument.size_m.x - 2.0 * MARGIN_M, 0.001)
	var shown_width: float = maxf(width * fill, 0.0001)
	var height: float = instrument.size_m.y * BAR_HEIGHT_SHARE
	var x: float = -width * 0.5 + shown_width * 0.5
	return Transform3D(Basis.from_scale(Vector3(shown_width, height, 1.0)),
		Vector3(x, instrument.size_m.y * BAR_Y_SHARE, lift))


static func _track_color(base: Color) -> Color:
	return Color(base.r * TRACK_SHARE, base.g * TRACK_SHARE, base.b * TRACK_SHARE)


func _multimesh(part_name: String, mesh: Mesh, colored: bool, count: int) -> MultiMeshInstance3D:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colored
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = part_name
	node.multimesh = multimesh
	node.material_override = _material(BEZEL_COLOR if not colored else Color.WHITE, colored)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _add_label(instrument: CockpitInstrument, index: int) -> void:
	var label: Label3D = Label3D.new()
	label.name = "Label_%s" % instrument.id
	label.text = instrument.label
	label.font_size = LABEL_FONT
	label.pixel_size = StatusPanel.PIXEL_SIZE
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.modulate = LABEL_COLOR
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.transform = _places[index] * Transform3D(Basis.IDENTITY,
		Vector3(0.0, instrument.size_m.y * LABEL_Y_SHARE, FILL_LIFT_M))
	add_child(label)


static func _material(albedo: Color, vertex_colors: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = albedo
	material.vertex_color_use_as_albedo = vertex_colors
	material.vertex_color_is_srgb = vertex_colors  # Instance colours are given like albedo.
	return material


static func _luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
