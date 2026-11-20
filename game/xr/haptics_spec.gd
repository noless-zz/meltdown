class_name HapticsSpec
extends RefCounted

## Controller haptic pulses as data (PLT-6, ARC-4): which pulse each event
## kind asks for, read from `res://xr/haptics.json` so the owner can tune them
## after a headset session without code changes. The afterburner starting and
## stopping (#170), the hull falling to the low-hull mark and the shield
## breaking (#616), a shot hitting the ship and a part picked up (#618) have
## pulses; weapons, wall impacts and the alarm come later.
##
## It only answers which pulse to send and on which hand; it never reads or
## writes `ShipState` or `Sim` (ARC-3).

const DEFAULT_FILE: String = "res://xr/haptics.json"

const BOOST_START: String = "boost_start"
const BOOST_STOP: String = "boost_stop"
## Sent on both hands once each time the hull falls to the low-hull mark (#616).
const LOW_HULL: String = "low_hull"
## Sent on both hands once each time the shield falls from above zero to zero (#616).
const SHIELD_BREAK: String = "shield_break"
## Sent on the hand on the side a shot came from, both for a shot from the front (#618).
const SHIP_HIT: String = "ship_hit"
## Sent on both hands when a floating part goes into the hold (#618, #600); it
## must feel unlike `SHIP_HIT`.
const SALVAGE_PICKUP: String = "salvage_pickup"
## Every event kind the data file holds, each one entry.
const KINDS: Array[String] = [BOOST_START, BOOST_STOP, LOW_HULL, SHIELD_BREAK, SHIP_HIT, SALVAGE_PICKUP]

## The keys of one entry, as `pulse_for` returns them.
const PULSE_KEYS: Array[String] = ["amplitude", "duration_s", "frequency_hz"]
## Allowed range of each entry key, inclusive: [minimum, maximum]. A frequency
## of 0 asks for the runtime's default.
const RANGES: Dictionary[String, Array] = {
	"amplitude": [0.0, 1.0],
	"duration_s": [0.01, 0.5],
	"frequency_hz": [0.0, 320.0],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""
## Event kind -> {amplitude, duration_s, frequency_hz}.
var _pulses: Dictionary = {}


## Parses the text of a haptics data file: one JSON object holding an entry
## for every kind in `KINDS` and nothing else, each entry holding every key in
## `PULSE_KEYS` as a number in its range and nothing else. On failure the
## returned spec has `error` set, naming the field, and no pulses.
static func parse_json(text: String) -> HapticsSpec:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KINDS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var spec: HapticsSpec = HapticsSpec.new()
	for kind: String in KINDS:
		if not data.has(kind):
			return _rejected("missing key \"%s\"" % kind)
		if typeof(data[kind]) != TYPE_DICTIONARY:
			return _rejected("key \"%s\" must be a JSON object" % kind)
		var entry: Dictionary = data[kind]
		for key: Variant in entry:
			if typeof(key) != TYPE_STRING or not PULSE_KEYS.has(key):
				return _rejected("unknown key \"%s.%s\"" % [kind, str(key)])
		var pulse: Dictionary = {}
		for key: String in PULSE_KEYS:
			var field: String = "%s.%s" % [kind, key]
			if not entry.has(key):
				return _rejected("missing key \"%s\"" % field)
			var value: Variant = entry[key]
			# A bool must not pass as 0 or 1.
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return _rejected("key \"%s\" must be a number" % field)
			var low: float = RANGES[key][0]
			var high: float = RANGES[key][1]
			if float(value) < low or float(value) > high:
				return _rejected("key \"%s\" is %s, must be within %s..%s" % [field, value, low, high])
			pulse[key] = float(value)
		spec._pulses[kind] = pulse
	return spec


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> HapticsSpec:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var spec: HapticsSpec = parse_json(FileAccess.get_file_as_string(path))
	if spec.error != "":
		spec.error = "%s: %s" % [path, spec.error]
	return spec


static func _rejected(message: String) -> HapticsSpec:
	var spec: HapticsSpec = HapticsSpec.new()
	spec.error = message
	return spec


## The pulse for `event_kind`: {amplitude, duration_s, frequency_hz}, or an
## empty dictionary for a kind with no pulse. A copy, safe to edit.
func pulse_for(event_kind: String) -> Dictionary:
	return (_pulses.get(event_kind, {}) as Dictionary).duplicate()


## "left" or "right": the hand that holds `action` in `mapping`, after
## left-handed mode swaps the hands. The control with the largest weight
## decides; empty when the action is bound to no hand.
static func hand_for_action(mapping: ThumbstickMapping, action: String) -> String:
	var bindings: Dictionary = mapping.layout.get(action, {})
	var best: String = ""
	var best_weight: float = 0.0
	for control: Variant in bindings:
		var weight: float = absf(float(bindings[control]))
		if weight > best_weight:
			best_weight = weight
			best = str(control)
	var hand: String = ""
	if best.begins_with("left_"):
		hand = "left"
	elif best.begins_with("right_"):
		hand = "right"
	if hand != "" and mapping.left_handed:
		hand = "right" if hand == "left" else "left"
	return hand
