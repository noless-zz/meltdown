class_name DevMenuModel
extends RefCounted

## What the in-headset development menu (#753, part 2 of #748) has selected,
## and what a press of each named action does. No nodes: `DevMenu` draws it.
##
## Input arrives as named actions held this frame (`ACTIONS`), so the
## controller layout (decision record 0004) is not edited here; the wiring
## (#763) says which buttons they are. Each action counts once, on the frame
## it is pressed, never while it is held.
##
## `press` returns what was confirmed, or "" when nothing was:
## `corner:<name>`, `controls:<scheme>` (#778), `hands:<left|right>` and
## `pitch:<normal|inverted>` (#790), `comfort:<1..4>` (#805) or `comfort:5`, the custom mode (#837),
## `break:<on|off>` (#821), `refresh:<90|120>` (#852), `swivel:<on|off>` (#853),
## `auto_level:<on|off>` (#1247),
## `foveation:<0..3>:<on|off>` with the second part dynamic (#871),
## `level:<source>` where the source is in the form
## `LevelStart.source` uses ("" for the test tunnel, a level file path,
## `seed:<n>`) or `random` for a fresh pick (see `DevMenuLevels`), `restart`,
## `flight_test` (#839), `update` or `close`.
## The update entry is skipped while `update_version` is empty. The menu
## only returns these; it never reads or writes the simulation (MP-2, ARC-3).

const UP: String = "menu_up"
const DOWN: String = "menu_down"
const LEFT: String = "menu_left"
const RIGHT: String = "menu_right"
const CONFIRM: String = "menu_confirm"
## Step the seed while the level entry shows a seed: by 1, and by 10 (`FAR`).
const SEED_DOWN: String = "menu_seed_down"
const SEED_UP: String = "menu_seed_up"
const SEED_DOWN_FAR: String = "menu_seed_down_far"
const SEED_UP_FAR: String = "menu_seed_up_far"
const ACTIONS: Array[String] = [UP, DOWN, LEFT, RIGHT, CONFIRM, SEED_DOWN, SEED_UP,
	SEED_DOWN_FAR, SEED_UP_FAR]
const SEED_STEPS: Dictionary = {SEED_DOWN: -1, SEED_UP: 1, SEED_DOWN_FAR: -10, SEED_UP_FAR: 10}
const CORNER_PREFIX: String = "corner:"
const CONTROLS_PREFIX: String = "controls:"
const HANDS_PREFIX: String = "hands:"
const PITCH_PREFIX: String = "pitch:"
const COMFORT_PREFIX: String = "comfort:"
const BREAK_PREFIX: String = "break:"
const BREAK_ON: String = "on"
const BREAK_OFF: String = "off"
const REFRESH_PREFIX: String = "refresh:"
const REFRESH_HIGH: String = RefreshChoice.ON
const REFRESH_STANDARD: String = RefreshChoice.OFF
const SWIVEL_PREFIX: String = "swivel:"
const SWIVEL_ON: String = "on"
const SWIVEL_OFF: String = "off"
const AUTO_LEVEL_PREFIX: String = "auto_level:"
const AUTO_LEVEL_ON: String = "on"
const AUTO_LEVEL_OFF: String = "off"
const FOVEATION_PREFIX: String = "foveation:"
## The hand and pitch choices, in the order left / right steps through them.
const HANDS: Array[String] = ["right", "left"]
const PITCHES: Array[String] = ["normal", "inverted"]
const LEVEL_PREFIX: String = "level:"
const RANDOM: String = DevMenuLevels.RANDOM
const RESTART: String = "restart"
const FLIGHT_TEST: String = "flight_test"
const CLOSE: String = "close"
const UPDATE: String = "update"

## The entries confirming acts on with no value to step (`value` gives null).
const ACTION_KINDS: Array[String] = [DevMenuSpec.KIND_RESTART, DevMenuSpec.KIND_FLIGHT_TEST,
	DevMenuSpec.KIND_UPDATE, DevMenuSpec.KIND_CLOSE]

var spec: DevMenuSpec
## Index of the highlighted entry in `spec.entries`.
var selected: int = 0
## The Level entry's choices and seed.
var levels: DevMenuLevels
## The waiting build the update entry names; "" hides the entry (#763).
var update_version: String = ""
## True while that build downloads: the entry then cancels it.
var update_busy: bool = false
## The valid custom comfort file's base preset (1..4), or 0 when there is none (#837).
var custom_base: int:
	get: return _comfort.custom_base
	set(value): _comfort.custom_base = value
## Whether the Break reminder entry shows On (#821, CMF-10).
var break_on: bool:
	get: return _break.on
	set(value): _break.on = value
## Whether the Refresh entry shows 120 Hz (#852), and whether the active
## preset allows it; the wiring sets both (`set_refresh`).
var refresh_high: bool:
	get: return _refresh.on
	set(value): _refresh.on = value
var refresh_allowed: bool:
	get: return not _refresh.noted
	set(value): _refresh.noted = not value
## Whether the Swivel chair entry shows On, and whether the custom comfort file
## decides it so left / right leave it alone (#853); the wiring sets both.
var swivel_on: bool:
	get: return _swivel.on
	set(value): _swivel.on = value
var swivel_locked: bool:
	get: return _swivel.locked
	set(value): _swivel.locked = value
## The Foveation entry's setting as a `FoveationSwitch.MENU_STEPS` value (#871).
var foveation: Vector2i:
	get: return _foveation.setting
	set(value): _foveation.setting = value

var _held: Dictionary = {}
## Each value entry kind's value helper (#908).
var _values: Dictionary[String, DevMenuValue] = {}
var _corner: DevMenuValueList
var _scheme: DevMenuValueList
var _hands: DevMenuValueList
var _pitch: DevMenuValueList
var _comfort: DevMenuValueComfort
var _break: DevMenuValueToggle
var _refresh: DevMenuValueToggle
var _swivel: DevMenuValueToggle
var _foveation: DevMenuValueFoveation


## A menu from `spec` offering the level files at `level_paths`.
func _init(p_spec: DevMenuSpec, level_paths: Array[String]) -> void:
	spec = p_spec
	levels = DevMenuLevels.new(level_paths)
	_corner = DevMenuValueList.new(CORNER_PREFIX, spec.corners)
	_scheme = DevMenuValueList.new(CONTROLS_PREFIX, spec.schemes)
	_hands = DevMenuValueList.new(HANDS_PREFIX, HANDS,
		[spec.right_handed_text, spec.left_handed_text] as Array[String])
	_pitch = DevMenuValueList.new(PITCH_PREFIX, PITCHES,
		[spec.normal_pitch_text, spec.inverted_pitch_text] as Array[String])
	_comfort = DevMenuValueComfort.new(COMFORT_PREFIX, spec.custom_text)
	_break = DevMenuValueToggle.new(BREAK_PREFIX, BREAK_ON, BREAK_OFF, spec.break_on_text,
		spec.break_off_text, "", true)
	_refresh = DevMenuValueToggle.new(REFRESH_PREFIX, REFRESH_HIGH, REFRESH_STANDARD,
		spec.refresh_120_text, spec.refresh_90_text, spec.refresh_note_text)
	_swivel = DevMenuValueToggle.new(SWIVEL_PREFIX, SWIVEL_ON, SWIVEL_OFF, spec.swivel_on_text,
		spec.swivel_off_text, spec.swivel_custom_text)
	_foveation = DevMenuValueFoveation.new(FOVEATION_PREFIX, spec.foveation_off_text,
		spec.foveation_dynamic_text, spec.foveation_note_text)
	_values = {DevMenuSpec.KIND_CORNER: _corner, DevMenuSpec.KIND_CONTROLS: _scheme,
		DevMenuSpec.KIND_HANDS: _hands, DevMenuSpec.KIND_PITCH: _pitch,
		DevMenuSpec.KIND_COMFORT: _comfort, DevMenuSpec.KIND_BREAK: _break,
		DevMenuSpec.KIND_REFRESH: _refresh, DevMenuSpec.KIND_SWIVEL: _swivel,
		DevMenuSpec.KIND_FOVEATION: _foveation, DevMenuSpec.KIND_AUTO_LEVEL: DevMenuValueToggle.new(
			AUTO_LEVEL_PREFIX, AUTO_LEVEL_ON, AUTO_LEVEL_OFF, spec.auto_level_on_text,
			spec.auto_level_off_text, spec.auto_level_preset_text),
		DevMenuSpec.KIND_LEVEL: DevMenuValueLevel.new(LEVEL_PREFIX, levels, spec)}


## Shows what is in use when the menu opens: the first entry highlighted,
## `corner`, the level `source` (as `LevelStart.source` holds it), the
## control `scheme`, the hand and pitch settings, the comfort preset
## `comfort_number` (1..4, or the custom mode while `p_custom_base` > 0;
## another number shows the first preset) and whether the break reminder is
## on, all as in use. `p_custom_base` is the valid custom file's base, 0 for none.
func open(corner: String, source: String, scheme: String = "", left_handed: bool = false,
		invert_pitch: bool = false, comfort_number: int = ComfortPresetFiles.START_NUMBER,
		p_break_on: bool = true, p_custom_base: int = 0) -> void:
	selected = _step_shown(-1, 1)
	_held = {}
	_corner.select(corner)
	_scheme.select(scheme)
	_hands.index = 1 if left_handed else 0
	_pitch.index = 1 if invert_pitch else 0
	_comfort.open(comfort_number, p_custom_base)
	break_on = p_break_on
	levels.open(source)


## One frame of input: `held` maps action names to whether they are held.
## Returns what was confirmed this frame, or "".
func press(held: Dictionary) -> String:
	var result: String = ""
	for action: String in ACTIONS:
		var down: bool = bool(held.get(action, false))
		var pressed: bool = down and not bool(_held.get(action, false))
		_held[action] = down
		if pressed and result == "":
			result = _act(action)
	return result


func kind() -> String:
	return str(spec.entries[selected]["kind"])


## The value helper of entry kind `entry_kind`, or null for an action entry.
func value(entry_kind: String) -> DevMenuValue:
	return _values.get(entry_kind, null)


## The words entry kind `entry_kind` shows for its value; "" for an action entry.
func value_text(entry_kind: String) -> String:
	var helper: DevMenuValue = value(entry_kind)
	return helper.value_text() if helper != null else ""


## Whether entry `index` is on the menu now: every entry but a hidden update.
func is_shown(index: int) -> bool:
	return str(spec.entries[index]["kind"]) != DevMenuSpec.KIND_UPDATE or update_version != ""


## Names the waiting build, or hides the update entry with "". A hidden
## entry cannot stay highlighted, so the highlight moves on to the next one.
func set_update(version: String, busy: bool) -> void:
	update_version = version
	update_busy = busy
	if not is_shown(selected):
		selected = _step_shown(selected, 1)


## The words the update entry shows for the waiting build.
func update_text(label: String) -> String:
	var text: String = spec.cancel_update_text if update_busy else label
	return text.replace("{version}", update_version)


# Each value by name, for the wiring and the tests: the choice in use, and the words shown.
func corner() -> String: return _corner.current()
func scheme() -> String: return _scheme.current()
func hands() -> String: return _hands.current()
func pitch() -> String: return _pitch.current()
## The comfort preset number the comfort entry shows, 1..4 or the custom mode's.
func comfort_number() -> int: return _comfort.number()
func comfort_text() -> String: return _comfort.value_text()
func hands_text() -> String: return _hands.value_text()
func pitch_text() -> String: return _pitch.value_text()
func refresh_text() -> String: return _refresh.value_text()
func swivel_text() -> String: return _swivel.value_text()
func foveation_text() -> String: return _foveation.value_text()
func break_text() -> String: return _break.value_text()


## Shows the 120 Hz option in use and whether the active preset allows it.
func set_refresh(high: bool, allowed: bool) -> void:
	refresh_high = high
	refresh_allowed = allowed


## Shows the swivel in use and whether the custom file decides it.
func set_swivel(on: bool, locked: bool) -> void:
	swivel_on = on
	swivel_locked = locked


func _act(action: String) -> String:
	match action:
		UP:
			selected = _step_shown(selected, -1)
		DOWN:
			selected = _step_shown(selected, 1)
		LEFT, RIGHT:
			var helper: DevMenuValue = value(kind())
			if helper != null:
				helper.step(-1 if action == LEFT else 1)
		CONFIRM:
			return _confirm()
		_:
			if kind() == DevMenuSpec.KIND_LEVEL and levels.choice() == DevMenuLevels.CHOICE_SEED:
				levels.step_seed(SEED_STEPS[action])
	return ""


func _confirm() -> String:
	var helper: DevMenuValue = value(kind())
	if helper != null:
		return helper.confirmed()
	match kind():
		DevMenuSpec.KIND_RESTART:
			return RESTART
		DevMenuSpec.KIND_FLIGHT_TEST:
			return FLIGHT_TEST
		DevMenuSpec.KIND_UPDATE:
			return UPDATE
	return CLOSE


## The next shown entry from `from` in `direction`, wrapping; `from` itself
## when nothing else is shown. A start of -1 finds the first shown entry.
func _step_shown(from: int, direction: int) -> int:
	var count: int = spec.entries.size()
	var index: int = from
	for step: int in count:
		index = posmod(index + direction, count)
		if is_shown(index):
			return index
	return maxi(from, 0)
