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
## `pitch:<normal|inverted>` (#790), `level:<source>` where the source is in the form
## `LevelStart.source` uses ("" for the test tunnel, a level file path,
## `seed:<n>`) or `random` for a fresh pick, `restart`, `update` or `close`.
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
## The hand and pitch choices, in the order left / right steps through them.
const HANDS: Array[String] = ["right", "left"]
const PITCHES: Array[String] = ["normal", "inverted"]
const LEVEL_PREFIX: String = "level:"
const RANDOM: String = "random"
const RESTART: String = "restart"
const CLOSE: String = "close"
const UPDATE: String = "update"
## The largest seed `LevelSwitch` accepts: `SEED_MAX_DIGITS` nines.
const SEED_MAX: int = 999999999999999999
## Level choices besides the level files.
const CHOICE_TUNNEL: String = "tunnel"
const CHOICE_SEED: String = "seed"
const CHOICE_RANDOM: String = "random"

var spec: DevMenuSpec
## Index of the highlighted entry in `spec.entries`.
var selected: int = 0
var corner_index: int = 0
var scheme_index: int = 0
## Indices into `HANDS` and `PITCHES`.
var hand_index: int = 0
var pitch_index: int = 0
## The level choices, in order: the tunnel, every level file, seed, random.
## A level file is its path; the others are the `CHOICE_` names.
var level_choices: Array[String] = []
var level_index: int = 0
var level_seed: int = 0
## The waiting build the update entry names; "" hides the entry (#763).
var update_version: String = ""
## True while that build downloads: the entry then cancels it.
var update_busy: bool = false

var _held: Dictionary = {}


## A menu from `spec` offering the level files at `level_paths`.
func _init(p_spec: DevMenuSpec, level_paths: Array[String]) -> void:
	spec = p_spec
	level_choices = [CHOICE_TUNNEL]
	level_choices.append_array(level_paths)
	level_choices.append_array([CHOICE_SEED, CHOICE_RANDOM])


## Every level file in `LevelSwitch.LEVEL_DIR` that `LevelSwitch.path_for`
## accepts, sorted: the ones `--level=<name>` can fly.
static func level_files() -> Array[String]:
	var paths: Array[String] = []
	for file: String in DirAccess.get_files_at(LevelSwitch.LEVEL_DIR):
		if not file.ends_with(LevelSwitch.LEVEL_SUFFIX):
			continue
		var path: String = LevelSwitch.path_for(file.trim_suffix(LevelSwitch.LEVEL_SUFFIX))
		if path != "":
			paths.append(path)
	paths.sort()
	return paths


## Shows what is in use when the menu opens: the first entry highlighted,
## `corner`, the level `source` (as `LevelStart.source` holds it), the
## control `scheme` and the hand and pitch settings in use.
func open(corner: String, source: String, scheme: String = "", left_handed: bool = false,
		invert_pitch: bool = false) -> void:
	selected = _step_shown(-1, 1)
	_held = {}
	corner_index = maxi(spec.corners.find(corner), 0)
	scheme_index = maxi(spec.schemes.find(scheme), 0)
	hand_index = 1 if left_handed else 0
	pitch_index = 1 if invert_pitch else 0
	level_index = 0
	if source.begins_with(LevelSwitch.SEED_PREFIX):
		level_index = level_choices.find(CHOICE_SEED)
		level_seed = maxi(LevelSwitch.seed_from(source.substr(LevelSwitch.SEED_PREFIX.length())), 0)
	elif level_choices.has(source):
		level_index = level_choices.find(source)


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


## The words the hands and pitch entries show for their choice.
func hands_text() -> String:
	return spec.left_handed_text if hands() == "left" else spec.right_handed_text


func pitch_text() -> String:
	return spec.inverted_pitch_text if pitch() == "inverted" else spec.normal_pitch_text


func level_choice() -> String:
	return level_choices[level_index]


## The level source the level entry would confirm: see `press`.
func level_source() -> String:
	match level_choice():
		CHOICE_TUNNEL:
			return ""
		CHOICE_SEED:
			return LevelSwitch.SEED_PREFIX + str(level_seed)
		CHOICE_RANDOM:
			return RANDOM
	return level_choice()


## Steps the seed by `amount`, kept within 0..`SEED_MAX`.
func step_seed(amount: int) -> void:
	if amount < 0:
		level_seed = maxi(level_seed + amount, 0)
	else:
		level_seed = SEED_MAX if level_seed > SEED_MAX - amount else level_seed + amount


## The words the level entry shows for its choice.
func level_text() -> String:
	match level_choice():
		CHOICE_TUNNEL:
			return spec.tunnel_text
		CHOICE_SEED:
			return spec.seed_text.replace("{seed}", str(level_seed))
		CHOICE_RANDOM:
			return spec.random_text
	return level_choice().get_file().trim_suffix(LevelSwitch.LEVEL_SUFFIX).to_upper()


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
			if kind() == DevMenuSpec.KIND_LEVEL and level_choice() == CHOICE_SEED:
				step_seed(SEED_STEPS[action])
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
	elif kind() == DevMenuSpec.KIND_LEVEL:
		level_index = posmod(level_index + direction, level_choices.size())


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
		DevMenuSpec.KIND_LEVEL:
			return LEVEL_PREFIX + level_source()
		DevMenuSpec.KIND_RESTART:
			return RESTART
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
