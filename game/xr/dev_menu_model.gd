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
## The hand and pitch choices, in the order left / right steps through them.
const HANDS: Array[String] = ["right", "left"]
const PITCHES: Array[String] = ["normal", "inverted"]
const LEVEL_PREFIX: String = "level:"
const RANDOM: String = DevMenuLevels.RANDOM
const RESTART: String = "restart"
const FLIGHT_TEST: String = "flight_test"
const CLOSE: String = "close"
const UPDATE: String = "update"

var spec: DevMenuSpec
## Index of the highlighted entry in `spec.entries`.
var selected: int = 0
var corner_index: int = 0
var scheme_index: int = 0
## Indices into `HANDS` and `PITCHES`.
var hand_index: int = 0
var pitch_index: int = 0
## The comfort presets the comfort entry steps through, 1 to 4 in order (#805):
## each preset file's `display_name`, or its number when the file is rejected.
var preset_names: Array[String] = []
## Index into `preset_names`: the preset numbered `preset_index + 1`; one past
## the end is the custom mode, offered only while `custom_base` > 0.
var preset_index: int = 0
## The valid custom comfort file's base preset (1..4), or 0 when there is none (#837).
var custom_base: int = 0
## Whether the Break reminder entry shows On (#821, CMF-10).
var break_on: bool = true
## Whether the Refresh entry shows 120 Hz (#852), and whether the active
## preset allows it; the wiring sets both (`set_refresh`).
var refresh_high: bool = false
var refresh_allowed: bool = true
## Whether the Swivel chair entry shows On, and whether the custom comfort file
## decides it so left / right leave it alone (#853); the wiring sets both.
var swivel_on: bool = false
var swivel_locked: bool = false
## The Level entry's choices and seed.
var levels: DevMenuLevels
## The waiting build the update entry names; "" hides the entry (#763).
var update_version: String = ""
## True while that build downloads: the entry then cancels it.
var update_busy: bool = false

var _held: Dictionary = {}


## A menu from `spec` offering the level files at `level_paths`.
func _init(p_spec: DevMenuSpec, level_paths: Array[String]) -> void:
	spec = p_spec
	levels = DevMenuLevels.new(level_paths)
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		preset_names.append(preset.display_name if preset != null else str(number))


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
	corner_index = maxi(spec.corners.find(corner), 0)
	scheme_index = maxi(spec.schemes.find(scheme), 0)
	hand_index = 1 if left_handed else 0
	pitch_index = 1 if invert_pitch else 0
	custom_base = maxi(p_custom_base, 0)
	preset_index = comfort_number - 1 if comfort_number >= 1 and comfort_number <= preset_names.size() else 0
	if comfort_number == ComfortPresetFiles.CUSTOM_NUMBER and custom_base > 0:
		preset_index = preset_names.size()
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


func corner() -> String:
	return spec.corners[corner_index]


func scheme() -> String:
	return spec.schemes[scheme_index]


func hands() -> String:
	return HANDS[hand_index]


func pitch() -> String:
	return PITCHES[pitch_index]


## The comfort preset number the comfort entry shows, 1..4 or the custom
## mode's, and its name: the preset's, or the file's custom text.
func comfort_number() -> int:
	if preset_index >= preset_names.size():
		return ComfortPresetFiles.CUSTOM_NUMBER
	return preset_index + 1


func comfort_text() -> String:
	if preset_index >= preset_names.size():
		return spec.custom_text.replace("{base}", str(custom_base))
	return preset_names[preset_index]


## The words the hands and pitch entries show for their choice.
func hands_text() -> String:
	return spec.left_handed_text if hands() == "left" else spec.right_handed_text


func pitch_text() -> String:
	return spec.inverted_pitch_text if pitch() == "inverted" else spec.normal_pitch_text


## Shows the 120 Hz option in use and whether the active preset allows it.
func set_refresh(high: bool, allowed: bool) -> void:
	refresh_high = high
	refresh_allowed = allowed


## The words the Refresh entry shows: the file's 90 or 120 Hz text, and its
## note while the active preset keeps its own rate whatever is chosen.
func refresh_text() -> String:
	var text: String = spec.refresh_120_text if refresh_high else spec.refresh_90_text
	return text if refresh_allowed else "%s %s" % [text, spec.refresh_note_text]


## Shows the swivel in use and whether the custom file decides it.
func set_swivel(on: bool, locked: bool) -> void:
	swivel_on = on
	swivel_locked = locked


## The words the Swivel chair entry shows: the file's On or Off text, marked
## while the custom file decides.
func swivel_text() -> String:
	var text: String = spec.swivel_on_text if swivel_on else spec.swivel_off_text
	return "%s %s" % [text, spec.swivel_custom_text] if swivel_locked else text


## The words the Break reminder entry shows: the file's On or Off text.
func break_text() -> String:
	return spec.break_on_text if break_on else spec.break_off_text


func _act(action: String) -> String:
	match action:
		UP:
			selected = _step_shown(selected, -1)
		DOWN:
			selected = _step_shown(selected, 1)
		LEFT, RIGHT:
			_change(-1 if action == LEFT else 1)
		CONFIRM:
			return _confirm()
		_:
			if kind() == DevMenuSpec.KIND_LEVEL and levels.choice() == DevMenuLevels.CHOICE_SEED:
				levels.step_seed(SEED_STEPS[action])
	return ""


func _change(direction: int) -> void:
	if kind() == DevMenuSpec.KIND_CORNER:
		corner_index = posmod(corner_index + direction, spec.corners.size())
	elif kind() == DevMenuSpec.KIND_CONTROLS:
		scheme_index = posmod(scheme_index + direction, spec.schemes.size())
	elif kind() == DevMenuSpec.KIND_HANDS:
		hand_index = posmod(hand_index + direction, HANDS.size())
	elif kind() == DevMenuSpec.KIND_PITCH:
		pitch_index = posmod(pitch_index + direction, PITCHES.size())
	elif kind() == DevMenuSpec.KIND_COMFORT:
		var choices: int = preset_names.size() + (1 if custom_base > 0 else 0)
		preset_index = posmod(preset_index + direction, choices)
	elif kind() == DevMenuSpec.KIND_BREAK:
		break_on = not break_on  # Two choices, so either direction flips it.
	elif kind() == DevMenuSpec.KIND_REFRESH:
		refresh_high = not refresh_high
	elif kind() == DevMenuSpec.KIND_SWIVEL and not swivel_locked:
		swivel_on = not swivel_on
	elif kind() == DevMenuSpec.KIND_LEVEL:
		levels.step(direction)


func _confirm() -> String:
	match kind():
		DevMenuSpec.KIND_CORNER:
			return CORNER_PREFIX + corner()
		DevMenuSpec.KIND_CONTROLS:
			return CONTROLS_PREFIX + scheme()
		DevMenuSpec.KIND_HANDS:
			return HANDS_PREFIX + hands()
		DevMenuSpec.KIND_PITCH:
			return PITCH_PREFIX + pitch()
		DevMenuSpec.KIND_COMFORT:
			return COMFORT_PREFIX + str(comfort_number())
		DevMenuSpec.KIND_BREAK:
			return BREAK_PREFIX + (BREAK_ON if break_on else BREAK_OFF)
		DevMenuSpec.KIND_REFRESH:
			return REFRESH_PREFIX + (REFRESH_HIGH if refresh_high else REFRESH_STANDARD)
		DevMenuSpec.KIND_SWIVEL:
			return SWIVEL_PREFIX + (SWIVEL_ON if swivel_on else SWIVEL_OFF)
		DevMenuSpec.KIND_LEVEL:
			return LEVEL_PREFIX + levels.source()
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
