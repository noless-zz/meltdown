class_name StatusPanel
extends Node3D

## A small panel fixed in the cockpit, below and ahead of the eye point (#146).
## In flight it draws what a pilot needs in a fight (#1207): hull, shield and
## energy (#227), the countdown (#315), every primary slot, the one that fires
## marked (#1210), the hold (#290), its tally (#1356) and how the level ended (#361). Its other
## rows (speed, preset, build, level, #747) take their values but draw only if
## the look's `rows` names them (`StatusPanelRowList`); the dev menu shows them.
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
## The first weapon row; the others are `StatusPanelWeaponRows.node_name`.
const WEAPON_NAME: String = StatusPanelWeaponRows.FIRST_NAME
const MELTDOWN_NAME: String = "Meltdown"
const OUTCOME_NAME: String = "Outcome"
const LEVEL_NAME: String = "Level"
const ESCAPED_TEXT: String = "ESCAPED"
const LOST_TEXT: String = "SHIP LOST"
## An empty hold is said, not left blank, which looks like an unwired panel.
const HOLD_EMPTY: String = "Hold empty"
const BOOST_ON: String = "BOOST"
const BOOST_RECHARGING: String = "recharging"

## How long a new preset is shown large. Two seconds is long enough to read
## the name after pressing Y without leaving a big label in view during flight.
const PRESET_LARGE_SECONDS: float = 2.0
## Metres per font pixel. With `SMALL_FONT` the text is about 1.3 cm tall,
## roughly 1.4 degrees at 0.55 m: comfortably readable on Quest 3.
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
## Under this many seconds the meltdown row turns `HULL_WARNING_COLOR`: the
## same red as a failing hull, so red on the panel always means "act now".
const MELTDOWN_WARNING_SECONDS: float = 30.0
## Rows 2.7 cm apart (#605): what decides the next seconds comes first,
## nearest the line of sight. One weapon row per primary slot follows energy
## (#1210); the hold, then speed and the preset come under the last of them,
## so leaving speed and the preset out (#1207) leaves no gap between drawn
## rows. The top stays where it was, clear of the large preset label.
const ROW_PITCH: float = 0.027
const MELTDOWN_Y: float = 3.5 * ROW_PITCH
const HULL_Y: float = 2.5 * ROW_PITCH
const SHIELD_Y: float = 1.5 * ROW_PITCH
const ENERGY_Y: float = 0.5 * ROW_PITCH
const WEAPON_Y: float = -0.5 * ROW_PITCH
const LABEL_X: float = -0.12
## The large outcome row sits above everything, clear of the large preset label.
const OUTCOME_Y: float = 0.2
## No depth test, so the panel draws over the nearer shell of cockpit presets
## 1 and 2 (#199): its priority is above the cockpit frame's default 0 and
## well below the reset fade quad's, so the fade still covers it.
const RENDER_PRIORITY: int = 10
## Labels and the filled bar draw above the track, which must never cover them.
const RENDER_PRIORITY_TOP: int = RENDER_PRIORITY + 1

## How many times each row's text was replaced. Only tests read them: they
## show that a per-frame call with the same value leaves the glyphs alone.
var hold_text_changes: int:
	get:
		return _hold_row.text_changes if _hold_row != null else 0
var meltdown_text_changes: int:
	get:
		return _meltdown_row.text_changes if _meltdown_row != null else 0
var outcome_text_changes: int:
	get:
		return _outcome_row.text_changes if _outcome_row != null else 0
var level_text_changes: int:
	get:
		return _level_row.text_changes if _level_row != null else 0
## Seconds the large preset label has left; 0 when it is hidden.
var large_seconds_left: float:
	get:
		return preset_row.seconds_left if preset_row != null else 0.0

## The gauges last shown (`show_gauges`); full and no countdown at first.
var gauges: ShipGauges = ShipGauges.new()
## The rows the panel draws, from the look file's `rows` (#1207).
var rows: Array[String] = []
## The preset row; `RigViews.show_swivel` tags it (#792).
var preset_row: StatusPanelPresetRow
var _level_row: StatusPanelLevelRow
var _speed: Label3D
var _boost: Label3D
var _hold_row: StatusPanelHoldRow
var tally_row: StatusPanelTallyRow = StatusPanelTallyRow.new(self, StatusPanelLook.shared(), StatusPanelTally.shipped_names())
## One row per primary slot (#1210).
var weapon_rows: StatusPanelWeaponRows
var _meltdown_row: StatusPanelMeltdownRow
var _outcome_row: StatusPanelOutcomeRow
var _hull_label: Label3D
var _energy_bar: PanelBar
var _shield_bar: PanelBar
var _hull_bar: PanelBar


func _init() -> void:
	name = NODE_NAME
	preset_row = StatusPanelPresetRow.new(self)
	# Rows under the weapon rows are placed by `StatusPanelWeaponRows.place_all`, once the slots are known.
	_speed = StatusPanelLabels.make(self, SPEED_NAME, Vector3(LABEL_X, 0.0, 0.0), SMALL_FONT)
	StatusPanelLabels.make(self, ENERGY_LABEL_NAME, Vector3(LABEL_X, ENERGY_Y, 0.0), SMALL_FONT).text = "Energy"
	StatusPanelLabels.make(self, SHIELD_LABEL_NAME, Vector3(LABEL_X, SHIELD_Y, 0.0), SMALL_FONT).text = "Shield"
	_hull_label = StatusPanelLabels.make(self, HULL_LABEL_NAME, Vector3(LABEL_X, HULL_Y, 0.0), SMALL_FONT)
	_hull_label.text = "Hull"
	_boost = StatusPanelLabels.make(self, BOOST_NAME, Vector3(0.04, 0.0, 0.0), SMALL_FONT)
	_hold_row = StatusPanelHoldRow.new(
		StatusPanelLabels.make(self, HOLD_NAME, Vector3(LABEL_X, 0.0, 0.0), SMALL_FONT),
		float(StatusPanelLook.shared()["message_seconds"]))
	weapon_rows = StatusPanelWeaponRows.new(self, Vector3(LABEL_X, WEAPON_Y, 0.0))
	_meltdown_row = StatusPanelMeltdownRow.new(
		StatusPanelLabels.make(self, MELTDOWN_NAME, Vector3(LABEL_X, MELTDOWN_Y, 0.0), SMALL_FONT))
	preset_row.add_large(self)
	_level_row = StatusPanelLevelRow.new(self, StatusPanelLook.shared())
	_outcome_row = StatusPanelOutcomeRow.new(
		StatusPanelLabels.make(self, OUTCOME_NAME, Vector3(0.0, OUTCOME_Y, 0.0), LARGE_FONT),
		StatusPanelLook.shared()["escaped_color"])
	_energy_bar = PanelBar.new(self, ENERGY_TRACK_NAME, ENERGY_BAR_NAME, BAR_COLOR, ENERGY_Y, RENDER_PRIORITY)
	_shield_bar = PanelBar.new(self, SHIELD_TRACK_NAME, SHIELD_BAR_NAME, SHIELD_COLOR, SHIELD_Y, RENDER_PRIORITY)
	_hull_bar = PanelBar.new(self, HULL_TRACK_NAME, HULL_BAR_NAME, HULL_COLOR, HULL_Y, RENDER_PRIORITY)
	# Full until the first gauges arrive, so an unwired panel does not look
	# like a dying ship.
	show_gauges(gauges)
	weapon_rows.place_all(self)
	show_rows(StatusPanelLook.shared()["rows"])


## Draws the rows named in `p_rows` (`StatusPanelRowList.NODES`) and no others.
func show_rows(p_rows: Array[String]) -> void:
	rows = p_rows.duplicate()
	StatusPanelRowList.apply(self, rows)
	weapon_rows.set_layers(StatusPanelRowList.DRAWN_LAYERS if rows.has("weapon") else 0)


## Shows this frame's values. `boost` is `""`, `BOOST_ON` or
## `BOOST_RECHARGING`. A preset number different from the last one shows the
## preset large for `PRESET_LARGE_SECONDS`.
func show_values(preset_number: int, preset_name: String, speed_mps: float,
		boost: String, build_text: String) -> void:
	preset_row.show(preset_number, preset_name, build_text)
	StatusPanelLabels.set_text(_speed, "Speed %d m/s" % roundi(speed_mps))
	StatusPanelLabels.set_text(_boost, boost)
	_boost.modulate = RECHARGING_COLOR if boost == BOOST_RECHARGING else BOOST_COLOR


## Shows this frame's `ShipGauges` (#1216): the only way the hull, shield and
## energy bars and the countdown row get their values. A hull at or below the
## look's `low_hull_fraction` (#616) turns the hull label and bar
## `HULL_WARNING_COLOR`; no countdown hides its row (#315). Safe every frame.
func show_gauges(p_gauges: ShipGauges) -> void:
	gauges = p_gauges
	_energy_bar.set_fraction(gauges.energy)
	_shield_bar.set_fraction(gauges.shield)
	_shield_bar.set_color(SHIELD_COLOR)  # Undoes last frame's hit flash (#618).
	var hull: float = _hull_bar.set_fraction(gauges.hull)
	var low: bool = hull <= float(StatusPanelLook.shared()["low_hull_fraction"])
	_hull_label.modulate = HULL_WARNING_COLOR if low else TEXT_COLOR
	_hull_bar.set_color(HULL_WARNING_COLOR if low else HULL_COLOR)
	_meltdown_row.show(gauges.countdown)


## Mixes `color` over the hull bar (`hull`) or the shield bar by `amount`,
## 0..1, for a hit (#618). Call it after `show_gauges`, which undoes it.
func flash_bar(hull: bool, color: Color, amount: float) -> void:
	var bar: PanelBar = _hull_bar if hull else _shield_bar
	bar.set_color(bar.color().lerp(color, clampf(amount, 0.0, 1.0)))


## Shows the part in the hold by name; an empty string shows `HOLD_EMPTY`.
## While a message from `show_hold_message` is up, the row keeps the message.
## Safe to call every frame: the label is only rebuilt when the text changes.
func show_hold(part_name: String) -> void:
	_hold_row.show_part(part_name)


## Puts `message` on the hold row for the look's `message_seconds` (#605).
func show_hold_message(message: String) -> void:
	_hold_row.show_message(message)


## Seconds the hold message has left; 0 when the row shows the hold.
func hold_message_seconds_left() -> float:
	return _hold_row.seconds_left


## Shows one row per primary slot: `names` holds each slot's weapon name, ""
## for an empty slot. Every filled slot fires (#1261) and carries the mark. A
## slot filled this frame shows this frame. Safe to call every frame.
func show_weapons(names: Array[String]) -> void:
	if weapon_rows.show_slots(names):
		weapon_rows.place_all(self)  # A ship with another slot count: the rows below move.


func meltdown_visible() -> bool:
	return _meltdown_row.visible()


## Whether the meltdown row shows the warning colour.
func meltdown_warning_shown() -> bool:
	return _meltdown_row.warning_shown()


## Shows how the level ended, from `ExitRule.Outcome` (#361); see
## `StatusPanelOutcomeRow.show`. Safe to call every frame.
func show_outcome(outcome: int) -> void:
	_outcome_row.show(outcome)


func outcome_visible() -> bool:
	return _outcome_row.visible()


## Names what this launch flies (#747); see `StatusPanelLevelRow.show_level`.
## Safe to call every frame.
func show_level(level_seed: String, level_name: String) -> void:
	_level_row.show_level(level_seed, level_name)


## Runs the large preset label's and the hold message's timers by `delta`
## seconds.
func advance(delta: float) -> void:
	_hold_row.advance(delta)
	preset_row.advance(delta)


## The text each label shows, by node name, for tests and logs.
func texts() -> Dictionary:
	var shown: Dictionary = {}
	for child: Node in get_children():
		if child is Label3D:
			shown[String(child.name)] = (child as Label3D).text
	return shown


func large_preset_visible() -> bool:
	return preset_row.large_visible()


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


## The panel's transform under the rig origin. `cockpit` is where the ship's
## centre (the eye point) sits in the rig's tracked space, so the panel moves
## with the ship and not with the head. Where it sits comes from the look file
## (#605) and the corner the owner chose (#752, `PanelCorner.current`).
static func rig_transform(cockpit: Transform3D) -> Transform3D:
	return cockpit * StatusPanelLook.placement(StatusPanelLook.shared(), PanelCorner.current)


## Where a row at panel height `row_y` sits from the eye point, in the
## cockpit's space.
static func row_point(row_y: float) -> Vector3:
	return rig_transform(Transform3D.IDENTITY) * Vector3(0.0, row_y, 0.0)
