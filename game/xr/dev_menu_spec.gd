class_name DevMenuSpec
extends RefCounted

## The in-headset development menu's data file, `res://xr/dev_menu.json`
## (#753, ARC-4): which entries it shows and in what order, the panel corners
## the corner entry offers, the control schemes the controls entry offers
## (#778), and the words for the level choices and the hand and pitch
## settings (#790).
##
##     {"entries": [{"kind": "corner", "label": "Panel corner"}, ...],
##      "corners": ["top_left", ...], "schemes": ["thumbsticks", "gripped"],
##      "tunnel_text": "Test tunnel",
##      "seed_text": "Seed {seed}", "random_text": "Random seed"}
##
## `kind` is one of `KINDS`, each at most once. A missing or rejected file
## gives `fallback()`: the built-in entries. The `update` entry (#763) shows
## only while a newer build waits; `{version}` in its label, and in
## `cancel_update_text` while that build downloads, names it. `schemes` is
## optional and defaults to every `ControlSchemeSwitch.SCHEMES`; each must be
## one of them, at most once. The `hands` and `pitch` entries (#790) show
## `right_handed_text` / `left_handed_text` and `normal_pitch_text` /
## `inverted_pitch_text`, each optional. The `comfort` entry (#805) shows
## each comfort preset's own `display_name`, from the preset files. The
## `break` entry (#821) shows `break_on_text` / `break_off_text`, each optional.
## With a valid custom comfort file the `comfort` entry also offers the custom
## mode (#837), shown as `custom_text` with `{base}` naming its base preset.
## The `flight_test` entry (#839) runs the first-launch flight test again.
## The `refresh` entry (#852) shows `refresh_90_text` / `refresh_120_text`,
## and `refresh_note_text` after it while the active preset does not allow 120 Hz.
## The `swivel` entry (#853) shows `swivel_on_text` / `swivel_off_text`, with
## `swivel_custom_text` after it while the custom file decides; each optional.
## The `auto_level` entry (#1247) shows `auto_level_on_text` /
## `auto_level_off_text`, with `auto_level_preset_text` after it while the
## preset always levels; each optional.
## The `foveation` entry (#871) shows `foveation_off_text` or the level, with
## `foveation_dynamic_text` after it when dynamic and `foveation_note_text` last.
## `distance_m` (a number over 0) and `offset_m` (`[right, up]`) say where the
## menu opens from the head (#1206): its centre that far along the head's
## forward direction, then moved across the view; both optional.
## `info_title_text` heads the read-only Info section (#1207); optional.
## The `map_place` and `map_turn` entries (#1321) show `map_hand_text` /
## `map_cockpit_text` and `map_fixed_text` / `map_follows_text`, each optional.
## The `return` entry (#1246) shows only while a run's level flies; once pressed
## it reads `confirm_return_text` until a second press abandons the run.
## `sections` (#1301, optional) groups entries under a row each:
## `[{"label": "Comfort", "entries": ["comfort", "break", ...]}, ...]`. Each
## named kind must be an entry, in at most one section; entries in no section
## stay on the top list after the section rows. `back_text` labels the row at the
## top of each section that returns to the top list. `max_rows_visible` rows
## show at once and the list scrolls with the highlight; a label and its value
## should fit `max_row_chars` (a check for the shipped file, not a cut).

const DEFAULT_FILE: String = "res://xr/dev_menu.json"
const KIND_CORNER: String = "corner"
const KIND_LEVEL: String = "level"
const KIND_RESTART: String = "restart"
const KIND_CLOSE: String = "close"
const KIND_UPDATE: String = "update"
const KIND_CONTROLS: String = "controls"
const KIND_HANDS: String = "hands"
const KIND_PITCH: String = "pitch"
const KIND_COMFORT: String = "comfort"
const KIND_BREAK: String = "break"
const KIND_FLIGHT_TEST: String = "flight_test"
const KIND_REFRESH: String = "refresh"
const KIND_SWIVEL: String = "swivel"
const KIND_FOVEATION: String = "foveation"
const KIND_AUTO_LEVEL: String = "auto_level"
const KIND_RETURN: String = "return"
const KIND_MAP_PLACE: String = "map_place"
const KIND_MAP_TURN: String = "map_turn"
const KINDS: Array[String] = [KIND_CORNER, KIND_LEVEL, KIND_RESTART, KIND_CLOSE, KIND_UPDATE,
	KIND_CONTROLS, KIND_HANDS, KIND_PITCH, KIND_COMFORT, KIND_BREAK, KIND_FLIGHT_TEST,
	KIND_REFRESH, KIND_SWIVEL, KIND_FOVEATION, KIND_AUTO_LEVEL, KIND_RETURN, KIND_MAP_PLACE,
	KIND_MAP_TURN]
const TEXT_KEYS: Array[String] = ["tunnel_text", "seed_text", "random_text", "cancel_update_text",
	"right_handed_text", "left_handed_text", "normal_pitch_text", "inverted_pitch_text",
	"break_on_text", "break_off_text", "custom_text", "refresh_90_text", "refresh_120_text",
	"refresh_note_text", "swivel_on_text", "swivel_off_text", "swivel_custom_text",
	"foveation_off_text", "foveation_dynamic_text", "foveation_note_text", "info_title_text",
	"auto_level_on_text", "auto_level_off_text", "auto_level_preset_text", "confirm_return_text",
	"back_text", "map_hand_text", "map_cockpit_text", "map_fixed_text", "map_follows_text"]
const COUNT_KEYS: Array[String] = ["max_rows_visible", "max_row_chars"]
const BUILT_IN_LABELS: Dictionary = {
	KIND_CORNER: "Panel corner",
	KIND_LEVEL: "Level",
	KIND_RESTART: "Restart level",
	KIND_CLOSE: "Close",
	KIND_UPDATE: "Update to {version}",
	KIND_CONTROLS: "Controls",
	KIND_HANDS: "Hands",
	KIND_PITCH: "Pitch",
	KIND_COMFORT: "Comfort",
	KIND_BREAK: "Break reminder",
	KIND_FLIGHT_TEST: "Flight test",
	KIND_REFRESH: "Refresh",
	KIND_SWIVEL: "Swivel chair",
	KIND_FOVEATION: "Foveation",
	KIND_AUTO_LEVEL: "Auto-level",
	KIND_RETURN: "Return to base",
	KIND_MAP_PLACE: "Map place",
	KIND_MAP_TURN: "Map turn",
}
const PLACE_KEYS: Array[String] = ["distance_m", "offset_m"]
## Corner names are lower-case letters and underscores, like `PanelCorner`'s.
const NAME_CHARACTERS: String = "abcdefghijklmnopqrstuvwxyz_"

## Each entry as `{"kind": ..., "label": ...}`, top to bottom.
var entries: Array[Dictionary] = []
var corners: Array[String] = []
var schemes: Array[String] = ControlSchemeSwitch.SCHEMES.duplicate()
var tunnel_text: String = "Test tunnel"
var seed_text: String = "Seed {seed}"
var random_text: String = "Random seed"
var cancel_update_text: String = "Cancel update to {version}"
var right_handed_text: String = "right-handed"
var left_handed_text: String = "left-handed"
var normal_pitch_text: String = "normal"
var inverted_pitch_text: String = "inverted"
var break_on_text: String = "On"
var break_off_text: String = "Off"
var custom_text: String = "Custom (base {base})"
var refresh_90_text: String = "90 Hz"
var refresh_120_text: String = "120 Hz"
var refresh_note_text: String = "(preset 4 only)"
var swivel_on_text: String = "On"
var swivel_off_text: String = "Off"
var swivel_custom_text: String = "(custom file)"
var auto_level_on_text: String = "On"
var auto_level_off_text: String = "Off"
var auto_level_preset_text: String = "(preset)"
var foveation_off_text: String = "Off"
var foveation_dynamic_text: String = "dynamic"
var foveation_note_text: String = "(this session)"
var map_hand_text: String = "hand"
var map_cockpit_text: String = "cockpit"
var map_fixed_text: String = "fixed"
var map_follows_text: String = "follows ship"
var distance_m: float = 1.0
var offset_m: Vector2 = Vector2.ZERO
## The heading of the Info section under the entries (#1207, `DevMenuInfo`).
var info_title_text: String = "Info"
## The Return to base row's text once pressed, before the confirming press (#1246).
var confirm_return_text: String = "Confirm: abandon run"
## The row at the top of each section that returns to the top list (#1301).
var back_text: String = "Back"
## Each section as `{"label": ..., "kinds": [...]}`, top to bottom (#1301).
var sections: Array[Dictionary] = []
## How many rows show at once, and how long a row's label and value may be (#1301).
var max_rows_visible: int = 6
var max_row_chars: int = 28
## Why the file was rejected; empty when it was read.
var error: String = ""


## The built-in menu: every entry in `KINDS` order, the four corners
## and the default place.
static func fallback() -> DevMenuSpec:
	var spec: DevMenuSpec = DevMenuSpec.new()
	for kind: String in KINDS:
		spec.entries.append({"kind": kind, "label": BUILT_IN_LABELS[kind]})
	spec.corners = ["bottom_left", "bottom_right", "top_left", "top_right", "centre"]
	return spec


## Reads `path`; a missing or rejected file gives `fallback()` with `error`
## set and a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> DevMenuSpec:
	var spec: DevMenuSpec = parse(FileAccess.get_file_as_string(path)) \
		if FileAccess.file_exists(path) else null
	var problem: String = "file not found" if spec == null else spec.error
	if problem == "":
		return spec
	push_warning("DevMenu uses the built-in entries; %s: %s" % [path, problem])
	var built_in: DevMenuSpec = fallback()
	built_in.error = problem
	return built_in


## Parses the text of a menu file; on a problem `error` names the field.
static func parse(text: String) -> DevMenuSpec:
	var spec: DevMenuSpec = DevMenuSpec.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		spec.error = "not a JSON object"
		return spec
	var data: Dictionary = json.data
	for key: Variant in data:
		if not (["entries", "corners", "schemes", "sections"] + PLACE_KEYS + TEXT_KEYS
				+ COUNT_KEYS).has(str(key)):
			spec.error = "unknown key \"%s\"" % str(key)
			return spec
	spec.error = spec._read_entries(data.get("entries"))
	if spec.error == "":
		spec.error = spec._read_corners(data.get("corners"))
	if spec.error == "" and data.has("schemes"):
		spec.error = spec._read_schemes(data["schemes"])
	if spec.error == "":
		spec.error = spec._read_place(data)
	if spec.error == "" and data.has("sections"):
		spec.error = spec._read_sections(data["sections"])
	for key: String in COUNT_KEYS:
		if spec.error == "" and data.has(key):
			if not (data[key] is float or data[key] is int) or int(data[key]) < 1 \
					or float(data[key]) != float(int(data[key])):
				spec.error = "\"%s\" must be a whole number of at least 1" % key
			else:
				spec.set(key, int(data[key]))
	for key: String in TEXT_KEYS:
		if spec.error == "" and data.has(key):
			if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
				spec.error = "\"%s\" must be a non-empty string" % key
			else:
				spec.set(key, data[key])
	return spec


func _read_entries(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "\"entries\" must be a non-empty list"
	for item: Variant in value:
		if typeof(item) != TYPE_DICTIONARY:
			return "every entry must be an object"
		var entry: Dictionary = item
		if entry.keys().size() != 2 or not entry.has("kind") or not entry.has("label"):
			return "an entry must have exactly \"kind\" and \"label\""
		var kind: String = str(entry["kind"])
		if not KINDS.has(kind):
			return "unknown entry kind \"%s\"" % kind
		for seen: Dictionary in entries:
			if seen["kind"] == kind:
				return "entry kind \"%s\" given twice" % kind
		if typeof(entry["label"]) != TYPE_STRING or (entry["label"] as String).strip_edges() == "":
			return "entry \"%s\" needs a non-empty label" % kind
		entries.append({"kind": kind, "label": entry["label"]})
	return ""


## The kind of every entry in a section; the rest belong to the top list.
func sectioned_kinds() -> Array[String]:
	var kinds: Array[String] = []
	for section: Dictionary in sections:
		kinds.append_array(section["kinds"])
	return kinds


func _read_sections(value: Variant) -> String:
	var listed: Array[String] = []
	for entry: Dictionary in entries:
		listed.append(str(entry["kind"]))
	return DevMenuSections.read(value, listed, sections)


func _read_corners(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "\"corners\" must be a non-empty list"
	for item: Variant in value:
		var corner: String = str(item)
		if typeof(item) != TYPE_STRING or corner == "" or corners.has(corner):
			return "corner %s is empty, not text or given twice" % str(item)
		for character: String in corner:
			if not NAME_CHARACTERS.contains(character):
				return "corner \"%s\" is not a name" % corner
		corners.append(corner)
	return ""


func _read_schemes(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "\"schemes\" must be a non-empty list"
	schemes = []
	for item: Variant in value:
		var scheme: String = str(item)
		if typeof(item) != TYPE_STRING or not ControlSchemeSwitch.SCHEMES.has(scheme) \
				or schemes.has(scheme):
			return "scheme %s is not one of %s or given twice" % [
				str(item), ", ".join(ControlSchemeSwitch.SCHEMES)]
		schemes.append(scheme)
	return ""


func _read_place(data: Dictionary) -> String:
	if data.has("distance_m"):
		var distance: Variant = data["distance_m"]
		if not (distance is float or distance is int) or float(distance) <= 0.0:
			return "\"distance_m\" must be a number over 0"
		distance_m = float(distance)
	if data.has("offset_m"):
		var offset: Variant = data["offset_m"]
		if typeof(offset) != TYPE_ARRAY or (offset as Array).size() != 2 \
				or not ((offset as Array)[0] is float or (offset as Array)[0] is int) \
				or not ((offset as Array)[1] is float or (offset as Array)[1] is int):
			return "\"offset_m\" must be [right, up] in metres"
		offset_m = Vector2(float(offset[0]), float(offset[1]))
	return ""
