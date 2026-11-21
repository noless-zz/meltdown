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
## each comfort preset's own `display_name`, from the preset files.

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
const KINDS: Array[String] = [KIND_CORNER, KIND_LEVEL, KIND_RESTART, KIND_CLOSE, KIND_UPDATE,
	KIND_CONTROLS, KIND_HANDS, KIND_PITCH, KIND_COMFORT]
const TEXT_KEYS: Array[String] = ["tunnel_text", "seed_text", "random_text", "cancel_update_text",
	"right_handed_text", "left_handed_text", "normal_pitch_text", "inverted_pitch_text"]
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
}
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
		if not (["entries", "corners", "schemes"] + TEXT_KEYS).has(str(key)):
			spec.error = "unknown key \"%s\"" % str(key)
			return spec
	spec.error = spec._read_entries(data.get("entries"))
	if spec.error == "":
		spec.error = spec._read_corners(data.get("corners"))
	if spec.error == "" and data.has("schemes"):
		spec.error = spec._read_schemes(data["schemes"])
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
