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
## `flight_test` (#839), `update`, `return_to_base` (#1246), `checklist` (#1325) or `close`.
## The update entry is skipped while `update_version` is empty. Confirming a
## section row opens that section and its Back row returns to the top list
## (#1301, `DevMenuRows`); neither returns anything. The menu
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
const RETURN: String = "return_to_base"
const CHECKLIST: String = "checklist"

## The entries confirming acts on with no value to step (`value` gives null).
const ACTION_KINDS: Array[String] = [DevMenuSpec.KIND_RESTART, DevMenuSpec.KIND_FLIGHT_TEST,
	DevMenuSpec.KIND_UPDATE, DevMenuSpec.KIND_CLOSE, DevMenuSpec.KIND_RETURN, DevMenuSpec.KIND_CHECKLIST]
## What confirming each action entry but Return to base returns; anything else closes.
const ACTION_RESULTS: Dictionary = {DevMenuSpec.KIND_RESTART: RESTART, DevMenuSpec.KIND_FLIGHT_TEST: FLIGHT_TEST,
	DevMenuSpec.KIND_UPDATE: UPDATE, DevMenuSpec.KIND_CHECKLIST: CHECKLIST}

## What `kind` gives on a section row and on a section's Back row (#1301).
const KIND_SECTION: String = "section"
const KIND_BACK: String = "back"

var spec: DevMenuSpec
## The list shown, its scroll and its highlight (#1301).
var rows: DevMenuRows
## The highlighted row: an entry's index in `spec.entries`, or a section or
## Back row (`DevMenuRows`).
var selected: int:
	get: return rows.selected
	set(value): rows.selected = value
## The Level entry's choices and seed.
var levels: DevMenuLevels
## The waiting build the update entry names; "" hides the entry (#763).
var update_version: String = ""
## True while that build downloads: the entry then cancels it.
var update_busy: bool = false
## Whether the Return to base row shows (a run flies) and is armed: its first
## press arms it, the second returns `RETURN`, moving or reopening disarms (#1246).
var run_shown: bool = false
var return_armed: bool = false
## Whether the Test checklist row shows: a checklist is attached (#1325).
var checklist_shown: bool = false
## Each value entry kind's value helper (#908, split out by #1282).
var values: DevMenuValues
## The valid custom comfort file's base preset (1..4), or 0 when there is none (#837).
var custom_base: int:
	get: return values.comfort.custom_base
	set(value): values.comfort.custom_base = value
## Whether the Break reminder entry shows On (#821, CMF-10).
var break_on: bool:
	get: return values.break_reminder.on
	set(value): values.break_reminder.on = value
## Whether the Refresh entry shows 120 Hz (#852), and whether the active
## preset allows it; the wiring sets both (`set_refresh`).
var refresh_high: bool:
	get: return values.refresh.on
	set(value): values.refresh.on = value
var refresh_allowed: bool:
	get: return not values.refresh.noted
	set(value): values.refresh.noted = not value
## Whether the Swivel chair entry shows On, and whether the custom comfort file
## decides it so left / right leave it alone (#853); the wiring sets both.
var swivel_on: bool:
	get: return values.swivel.on
	set(value): values.swivel.on = value
var swivel_locked: bool:
	get: return values.swivel.locked
	set(value): values.swivel.locked = value
## The Foveation entry's setting as a `FoveationSwitch.MENU_STEPS` value (#871).
var foveation: Vector2i:
	get: return values.foveation.setting
	set(value): values.foveation.setting = value

var _held: Dictionary = {}


## A menu from `spec` offering the level files at `level_paths`.
func _init(p_spec: DevMenuSpec, level_paths: Array[String]) -> void:
	spec = p_spec
	rows = DevMenuRows.new(spec, is_shown)
	levels = DevMenuLevels.new(level_paths)
	values = DevMenuValues.new(spec, levels)


## Shows what is in use when the menu opens: the top list, its first row highlighted,
## `corner`, the level `source` (as `LevelStart.source` holds it), the
## control `scheme`, the hand and pitch settings, the comfort preset
## `comfort_number` (1..4, or the custom mode while `p_custom_base` > 0;
## another number shows the first preset) and whether the break reminder is
## on, all as in use. `p_custom_base` is the valid custom file's base, 0 for none.
func open(corner: String, source: String, scheme: String = "", left_handed: bool = false,
		invert_pitch: bool = false, comfort_number: int = ComfortPresetFiles.START_NUMBER,
		p_break_on: bool = true, p_custom_base: int = 0) -> void:
	rows.to_top()
	_held = {}
	return_armed = false
	values.corner.select(corner)
	values.scheme.select(scheme)
	values.hands.index = 1 if left_handed else 0
	values.pitch.index = 1 if invert_pitch else 0
	values.comfort.open(comfort_number, p_custom_base)
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


## Back to the top list, any Return to base confirm cancelled (#1246, #1301).
func close() -> void:
	rows.to_top()
	return_armed = false


## The highlighted row's entry kind, or `KIND_SECTION` / `KIND_BACK`.
func kind() -> String:
	if selected == DevMenuRows.BACK:
		return KIND_BACK
	if DevMenuRows.section_of(selected) != -1:
		return KIND_SECTION
	return str(spec.entries[selected]["kind"])


## The value helper of entry kind `entry_kind`, or null for an action entry.
func value(entry_kind: String) -> DevMenuValue:
	return values.value(entry_kind)


## The words entry kind `entry_kind` shows for its value; "" for an action entry.
func value_text(entry_kind: String) -> String:
	return values.value_text(entry_kind)


## Whether entry `index` is on the menu now: every entry but a hidden update
## or Return to base row.
func is_shown(index: int) -> bool:
	match str(spec.entries[index]["kind"]):
		DevMenuSpec.KIND_UPDATE: return update_version != ""
		DevMenuSpec.KIND_RETURN: return run_shown
		DevMenuSpec.KIND_CHECKLIST: return checklist_shown
	return true


## Shows or hides the Return to base row, disarmed; the highlight leaves it when hidden.
func set_run(shown: bool) -> void:
	run_shown = shown
	return_armed = false
	rows.leave_hidden()


## The words the Return to base row shows: its label, or the confirm text once armed.
func return_text(label: String) -> String:
	return spec.confirm_return_text if return_armed else label


## Names the waiting build, or hides the update entry with "". A hidden
## entry cannot stay highlighted, so the highlight moves on to the next one.
func set_update(version: String, busy: bool) -> void:
	update_version = version
	update_busy = busy
	rows.leave_hidden()


## The words the update entry shows for the waiting build.
func update_text(label: String) -> String:
	var text: String = spec.cancel_update_text if update_busy else label
	return text.replace("{version}", update_version)


# Each value by name, for the wiring and the tests: the choice in use, and the words shown.
func corner() -> String: return values.corner.current()
func scheme() -> String: return values.scheme.current()
func hands() -> String: return values.hands.current()
func pitch() -> String: return values.pitch.current()
## The comfort preset number the comfort entry shows, 1..4 or the custom mode's.
func comfort_number() -> int: return values.comfort.number()
func comfort_text() -> String: return values.comfort.value_text()
func hands_text() -> String: return values.hands.value_text()
func pitch_text() -> String: return values.pitch.value_text()
func refresh_text() -> String: return values.refresh.value_text()
func swivel_text() -> String: return values.swivel.value_text()
func foveation_text() -> String: return values.foveation.value_text()
func break_text() -> String: return values.break_reminder.value_text()


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
		UP, DOWN:
			rows.step(-1 if action == UP else 1)
			return_armed = false  # Moving to another row cancels the confirm step.
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
	if kind() == KIND_SECTION:
		rows.open_section(DevMenuRows.section_of(selected))
		return ""
	if kind() == KIND_BACK:
		rows.back()
		return ""
	var helper: DevMenuValue = value(kind())
	if helper != null:
		return helper.confirmed()
	if kind() == DevMenuSpec.KIND_RETURN:
		return_armed = not return_armed
		return "" if return_armed else RETURN
	return str(ACTION_RESULTS.get(kind(), CLOSE))
