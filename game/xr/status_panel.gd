class_name StatusPanel
extends Node3D

## A small panel fixed in the cockpit, low and ahead of the eye point, that
## shows at a glance what the owner could not tell in the headset (#146): the
## active comfort preset, the ship's speed, the energy pool, the shield and
## hull (#227), whether the afterburner is boosting or locked out, the part in
## the hold (#290), and which build is running.
##
## It is given plain values every frame and keeps no reference to the ship or
## the session, so it can never read more than it is handed or write
## simulation state (ARC-3, MP-2). Unshaded labels and flat bars: no
## lights, no textures, nothing per-pixel beyond the glyphs (PRF-2).

const NODE_NAME: String = "StatusPanel"
const PRESET_NAME: String = "Preset"
const PRESET_LARGE_NAME: String = "PresetLarge"
const SPEED_NAME: String = "Speed"
const BOOST_NAME: String = "Boost"
const BUILD_NAME: String = "Build"
const ENERGY_LABEL_NAME: String = "EnergyLabel"
const ENERGY_BAR_NAME: String = "EnergyBar"
const ENERGY_TRACK_NAME: String = "EnergyTrack"
const SHIELD_LABEL_NAME: String = "ShieldLabel"
const SHIELD_BAR_NAME: String = "ShieldBar"
const SHIELD_TRACK_NAME: String = "ShieldTrack"
const HULL_LABEL_NAME: String = "HullLabel"
const HULL_BAR_NAME: String = "HullBar"
const HULL_TRACK_NAME: String = "HullTrack"
const HOLD_NAME: String = "Hold"
## The hold line reads "Hold <part>" or this, so an empty hold is said, not
## left blank: a blank line looks the same as an unwired panel.
const HOLD_EMPTY: String = "Hold empty"
const BOOST_ON: String = "BOOST"
const BOOST_RECHARGING: String = "recharging"

## How long a new preset is shown large. Two seconds is long enough to read
## the name after pressing Y without leaving a big label in view during flight.
const PRESET_LARGE_SECONDS: float = 2.0
## Where the panel sits in the cockpit, from the eye point: 0.3 m down and
## 0.55 m ahead, about 30 degrees below straight ahead, so it is read by
## glancing down and leaves the tunnel ahead clear. Inside the ship's 1 m
## collision sphere, so no wall can come between it and the eyes.
const COCKPIT_POSITION: Vector3 = Vector3(0.0, -0.3, -0.55)
## Tilted back (top away from the eyes) by about the same angle, so its face
## points up at the eyes rather than straight back along the ship.
const TILT_DEGREES: float = 30.0
## Metres per font pixel. With `SMALL_FONT` the text is about 1.3 cm tall,
## roughly 1.3 degrees at 0.63 m: comfortably readable on Quest 3.
const PIXEL_SIZE: float = 0.0004
const SMALL_FONT: int = 32
const LARGE_FONT: int = 96
const TEXT_COLOR: Color = Color(0.85, 0.95, 1.0)
const BOOST_COLOR: Color = Color(1.0, 0.6, 0.15)
const RECHARGING_COLOR: Color = Color(0.6, 0.6, 0.6)
const BAR_COLOR: Color = Color(0.3, 0.85, 1.0)
## Shield is a cool blue, set apart from the energy bar's cyan; hull is a warm
## amber. Read by colour at a glance, not by the small labels (#227).
const SHIELD_COLOR: Color = Color(0.4, 0.5, 1.0)
const HULL_COLOR: Color = Color(1.0, 0.72, 0.3)
## At or below this hull fraction the hull label turns `HULL_WARNING_COLOR`.
const HULL_WARNING_FRACTION: float = 0.25
const HULL_WARNING_COLOR: Color = Color(1.0, 0.2, 0.15)
## Rows, top to bottom, 3 cm apart: the bars sit under the energy bar, the
## hold line under the hull bar (#290), and the build line moves down below it.
const PRESET_Y: float = 0.045
const SPEED_Y: float = 0.015
const ENERGY_Y: float = -0.015
const SHIELD_Y: float = -0.045
const HULL_Y: float = -0.075
const HOLD_Y: float = -0.105
const BUILD_Y: float = -0.135
const LABEL_X: float = -0.12
## The panel draws without a depth test, over whatever lies between it and the
## eyes: the solid shell of cockpit presets 1 and 2 is nearer than the panel
## (#199). Its render priority sits above the cockpit frame's materials, which
## keep the default 0, so the panel lands on top of the shell, and well below
## the reset fade quad (`Material.RENDER_PRIORITY_MAX`), so the fade still
## covers the panel.
const RENDER_PRIORITY: int = 10
## Labels and the filled bar draw one step above the bar's track, so the
## track never covers them now that depth no longer decides.
const RENDER_PRIORITY_TOP: int = RENDER_PRIORITY + 1

## How many times the hold label's text was replaced. Only tests read it: it
## shows that a per-frame call with the same part leaves the glyphs alone.
var hold_text_changes: int = 0
## Seconds the large preset label has left; 0 when it is hidden.
var large_seconds_left: float = 0.0

## The preset number last shown; 0 before the first values, so the preset the
## game starts on is also shown large once.
var _shown_preset: int = 0
var _preset: Label3D
var _preset_large: Label3D
var _speed: Label3D
var _boost: Label3D
var _build: Label3D
var _hold: Label3D
var _hull_label: Label3D
var _energy_bar: PanelBar
var _shield_bar: PanelBar
var _hull_bar: PanelBar


func _init() -> void:
	name = NODE_NAME
	_preset = _label(PRESET_NAME, Vector3(LABEL_X, PRESET_Y, 0.0), SMALL_FONT)
	_speed = _label(SPEED_NAME, Vector3(LABEL_X, SPEED_Y, 0.0), SMALL_FONT)
	_label(ENERGY_LABEL_NAME, Vector3(LABEL_X, ENERGY_Y, 0.0), SMALL_FONT).text = "Energy"
	_label(SHIELD_LABEL_NAME, Vector3(LABEL_X, SHIELD_Y, 0.0), SMALL_FONT).text = "Shield"
	_hull_label = _label(HULL_LABEL_NAME, Vector3(LABEL_X, HULL_Y, 0.0), SMALL_FONT)
	_hull_label.text = "Hull"
	_boost = _label(BOOST_NAME, Vector3(0.04, SPEED_Y, 0.0), SMALL_FONT)
	_hold = _label(HOLD_NAME, Vector3(LABEL_X, HOLD_Y, 0.0), SMALL_FONT)
	_hold.text = HOLD_EMPTY
	_build = _label(BUILD_NAME, Vector3(LABEL_X, BUILD_Y, 0.0), SMALL_FONT)
	_build.font_size = SMALL_FONT * 3 / 4
	_preset_large = _label(PRESET_LARGE_NAME, Vector3(0.0, 0.11, 0.0), LARGE_FONT)
	_preset_large.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preset_large.visible = false
	_energy_bar = PanelBar.new(self, ENERGY_TRACK_NAME, ENERGY_BAR_NAME, BAR_COLOR, ENERGY_Y, RENDER_PRIORITY)
	_shield_bar = PanelBar.new(self, SHIELD_TRACK_NAME, SHIELD_BAR_NAME, SHIELD_COLOR, SHIELD_Y, RENDER_PRIORITY)
	_hull_bar = PanelBar.new(self, HULL_TRACK_NAME, HULL_BAR_NAME, HULL_COLOR, HULL_Y, RENDER_PRIORITY)
	# Full until `show_defence` is first called, so an unwired panel does not
	# look like a dying ship.
	show_defence(1.0, 1.0)


## Shows this frame's values. `boost` is `""`, `BOOST_ON` or
## `BOOST_RECHARGING`. A preset number different from the last one shows the
## preset large for `PRESET_LARGE_SECONDS`.
func show_values(preset_number: int, preset_name: String, speed_mps: float,
		energy_fraction: float, boost: String, build_text: String) -> void:
	var preset_text: String = "Preset %d %s" % [preset_number, preset_name]
	if preset_number != _shown_preset:
		_shown_preset = preset_number
		large_seconds_left = PRESET_LARGE_SECONDS
	_set_text(_preset, preset_text)
	_set_text(_preset_large, preset_text)
	_set_text(_speed, "Speed %d m/s" % roundi(speed_mps))
	_set_text(_boost, boost)
	_boost.modulate = RECHARGING_COLOR if boost == BOOST_RECHARGING else BOOST_COLOR
	_set_text(_build, build_text)
	_energy_bar.set_fraction(energy_fraction)
	_show_large(large_seconds_left > 0.0)


## Shows the shield and hull as fractions of their maximums, each clamped to
## 0..1. A hull at or below `HULL_WARNING_FRACTION` turns the hull label
## `HULL_WARNING_COLOR`.
func show_defence(shield_fraction: float, hull_fraction: float) -> void:
	_shield_bar.set_fraction(shield_fraction)
	var hull: float = _hull_bar.set_fraction(hull_fraction)
	_hull_label.modulate = HULL_WARNING_COLOR if hull <= HULL_WARNING_FRACTION else TEXT_COLOR


## Shows the part in the hold by name; an empty string shows `HOLD_EMPTY`.
## Safe to call every frame: the label is only rebuilt when the text changes.
func show_hold(part_name: String) -> void:
	if _set_text(_hold, HOLD_EMPTY if part_name.is_empty() else "Hold %s" % part_name):
		hold_text_changes += 1


## Runs the large preset label's timer by `delta` seconds.
func advance(delta: float) -> void:
	if large_seconds_left <= 0.0:
		return
	large_seconds_left = maxf(large_seconds_left - maxf(delta, 0.0), 0.0)
	_show_large(large_seconds_left > 0.0)


## The text each label shows, by node name, for tests and logs.
func texts() -> Dictionary:
	var shown: Dictionary = {}
	for child: Node in get_children():
		if child is Label3D:
			shown[String(child.name)] = (child as Label3D).text
	return shown


func large_preset_visible() -> bool:
	return _preset_large.visible


## The energy bar's length as a fraction of the full bar, 0..1.
func energy_bar_scale() -> float:
	return _energy_bar.fraction()


func shield_bar_scale() -> float:
	return _shield_bar.fraction()


func hull_bar_scale() -> float:
	return _hull_bar.fraction()


## Whether the hull label shows the low-hull warning colour.
func hull_warning_shown() -> bool:
	return _hull_label.modulate == HULL_WARNING_COLOR


## Large and small never show together, so the preset is not read twice.
func _show_large(large: bool) -> void:
	_preset_large.visible = large
	_preset.visible = not large


## Label3D rebuilds its glyph mesh on every assignment; most frames change nothing.
## Returns whether the text was replaced.
static func _set_text(label: Label3D, text: String) -> bool:
	if label.text == text:
		return false
	label.text = text
	return true


func _label(label_name: String, at: Vector3, font_size: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.position = at
	label.pixel_size = PIXEL_SIZE
	label.font_size = font_size
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.modulate = TEXT_COLOR
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = RENDER_PRIORITY_TOP
	add_child(label)
	return label


## The panel's transform under the rig origin. `cockpit` is where the ship's
## centre (the eye point) sits in the rig's tracked space, so the panel moves
## with the ship and not with the head.
static func rig_transform(cockpit: Transform3D) -> Transform3D:
	var local: Transform3D = Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(TILT_DEGREES)), COCKPIT_POSITION)
	return cockpit * local
