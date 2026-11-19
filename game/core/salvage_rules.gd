class_name SalvageRules
extends RefCounted

## How floating parts reach a ship (SLV-1, ARC-4, #600): how close a ship must
## pass to take one, how far off a part starts drifting towards it, and where a
## swapped-out weapon is dropped. Read from `data/salvage.json`; core opens no
## files, so the caller hands the text to `parse_json` and the rules to
## `Sim.set_salvage_rules`.
##
## A new `SalvageRules` holds the values the game had before this file existed
## (no pull, drop at the ship's centre), so a `Sim` given no rules, and every
## replay recorded without a salvage line, flies exactly as before.
##
## Distances are measured beyond the ship's own collision radius, so a bigger
## ship reaches as far past its hull as a small one. With the shipped 1 m ship
## and the shipped file, a part is taken within 3.5 m of the ship's centre.

## How far beyond its `radius` a ship's centre may pass from a part and still
## take it, metres, 0..20 (SLV-1).
var pickup_reach: float = 1.5
## How far beyond its `radius` a ship starts pulling a part towards itself,
## metres, `pickup_reach`..60. Equal to `pickup_reach` means no pull (SLV-1
## "pulls it into the cockpit").
var pull_reach: float = 1.5
## Speed at which a pulled part drifts towards the ship, metres per second,
## 0..60; 0 means no pull.
var pull_speed: float = 0.0
## How far behind the ship, along its own +Z, a weapon replaced by slotting is
## dropped, metres, 0..20. Behind, so the pilot sees a different object from
## the one just taken and the ship does not sit on it.
var swap_drop_distance: float = 0.0

## Every key of the data file, in the order the file lists them.
const KEYS: Array[String] = ["pickup_reach", "pull_reach", "pull_speed", "swap_drop_distance"]

## Allowed range of each key, inclusive. A String bound names another key.
const RANGES: Dictionary = {
	"pickup_reach": [0.0, 20.0],
	"pull_reach": ["pickup_reach", 60.0],
	"pull_speed": [0.0, 60.0],
	"swap_drop_distance": [0.0, 20.0],
}

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a salvage data file: one JSON object holding every key of
## `KEYS` as a number and nothing else. A missing or unknown key is an error, as
## in `ShipTuning`, so a typo cannot leave a value untuned unnoticed. On failure
## the returned rules have `error` set and the values of `SalvageRules.new()`.
static func parse_json(text: String) -> SalvageRules:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(),
			json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var rules: SalvageRules = SalvageRules.new()
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		rules.set(key, float(value))
	# Checked once every value is read, because a bound may be another key.
	for key: String in KEYS:
		var low: float = rules._bound(RANGES[key][0])
		var high: float = rules._bound(RANGES[key][1])
		var value: float = rules.get(key)
		if value < low or value > high:
			return _rejected("key \"%s\" is %s, must be %s to %s" % [key, value, low, high])
	return rules


## One-line JSON holding every key at full precision, so the rules read back
## are exactly these.
func to_json() -> String:
	var data: Dictionary = {}
	for key: String in KEYS:
		data[key] = get(key)
	return JSON.stringify(data, "", false, true)


func values_hash() -> int:
	return hash([pickup_reach, pull_reach, pull_speed, swap_drop_distance])


## Whether a part has a pull at all.
func pulls() -> bool:
	return pull_speed > 0.0 and pull_reach > pickup_reach


func _bound(bound: Variant) -> float:
	if typeof(bound) == TYPE_STRING:
		return get(bound)
	return bound


static func _rejected(message: String) -> SalvageRules:
	var rules: SalvageRules = SalvageRules.new()
	rules.error = message
	return rules
