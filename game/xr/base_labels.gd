class_name BaseLabels
extends RefCounted

## The control labels shown where pointing selects: the home base's stations
## and the shaft choice (#1469, PLT-5, CRW-2, ARC-4). The flight labels name
## fire, boost and pitch, which do nothing there; these name only what acts.
##
## Data, not code (ARC-4): `res://xr/base_labels.json` holds
## `{"labels": {<physical control>: <text>}, "mirror_left_handed": <bool>}`.
## A control is a hand prefix and a key of `ControlLabelSet.LABEL_POSITIONS`,
## as `ControlLabels` names them (`right_stick`, `right_button_lower`,
## `left_menu`). The file sits beside the layouts, not among them, because
## every file in `ThumbstickLayout.LAYOUTS_DIR` is read as a flight layout.
##
## The base and the shaft choice read the right stick, A and the right
## controller's aim in both hand modes (`DevMenuWiring.actions`), so the shipped
## file leaves `mirror_left_handed` off. Set on, left-handed mode swaps each
## label to the other hand's twin as decision record 0004 swaps the flight
## controls; the menu stays on the left menu button either way, as the reset
## hold does. A bad file names its field and leaves no labels at all.
##
## Presentation only: reads no input, ship or comfort state (ARC-3).

const DEFAULT_FILE: String = "res://xr/base_labels.json"
const KEY_LABELS: String = "labels"
const KEY_MIRROR: String = "mirror_left_handed"
const HANDS: Array[String] = ["left", "right"]

## Physical control (right-handed) -> its text.
var labels: Dictionary = {}
## True when left-handed mode moves the labels to the other hand.
var mirror_left_handed: bool = false
## Set when the file was rejected; empty otherwise.
var error: String = ""


## Parses the text of a base-labels file. On failure the result has `error`
## set and no labels.
static func parse_json(text: String) -> BaseLabels:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if str(key) != KEY_LABELS and str(key) != KEY_MIRROR:
			return _rejected("unknown key \"%s\"" % str(key))
	if not data.has(KEY_LABELS):
		return _rejected("missing key \"%s\"" % KEY_LABELS)
	if typeof(data[KEY_LABELS]) != TYPE_DICTIONARY:
		return _rejected("key \"%s\" must be an object" % KEY_LABELS)
	var mirror: Variant = data.get(KEY_MIRROR, false)
	if typeof(mirror) != TYPE_BOOL:
		return _rejected("key \"%s\" must be true or false" % KEY_MIRROR)
	var result: BaseLabels = BaseLabels.new()
	var given: Dictionary = data[KEY_LABELS]
	for control: Variant in given:
		var field: String = "%s.%s" % [KEY_LABELS, str(control)]
		if not is_control(str(control)):
			return _rejected("unknown control \"%s\"" % field)
		var words: Variant = given[control]
		if typeof(words) != TYPE_STRING or str(words).strip_edges() == "":
			return _rejected("\"%s\" must be a non-empty string" % field)
		result.labels[str(control)] = str(words)
	result.mirror_left_handed = bool(mirror)
	return result


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> BaseLabels:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var loaded: BaseLabels = parse_json(FileAccess.get_file_as_string(path))
	if loaded.error != "":
		loaded.error = "%s: %s" % [path, loaded.error]
	return loaded


## True for a hand prefix followed by a control a label set can show.
static func is_control(control: String) -> bool:
	for hand: String in HANDS:
		if control.begins_with(hand + "_"):
			return ControlLabelSet.LABEL_POSITIONS.has(control.trim_prefix(hand + "_"))
	return false


## Physical control -> text for the given hand mode, keyed as
## `ControlLabels.for_layout` keys the flight labels, so `ControlLabels.for_hand`
## splits it the same way.
func for_hand_mode(left_handed: bool) -> Dictionary:
	var result: Dictionary = {}
	for control: String in labels:
		var physical: String = control
		if left_handed and mirror_left_handed and control != ResetHold.BUTTON:
			physical = ControlLabels.other_hand(control)
		result[physical] = labels[control]
	return result


static func _rejected(message: String) -> BaseLabels:
	var rejected: BaseLabels = BaseLabels.new()
	rejected.error = message
	return rejected
