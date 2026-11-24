class_name ProjectileLook
extends RefCounted

## Parses `res://view/projectile_look.json`, the look of bolts, their muzzles,
## their flashes and their impacts (CMB-1, LGT-1, GFX-2, GFX-6, ARC-4), so it
## can be retuned without code. Kept apart from `ProjectileView` so the node
## stays small.
##
## Bolts leave from two muzzles, low left and low right ahead of the eye
## (#602): `muzzle_side_m` to each side, `muzzle_drop_m` down and
## `muzzle_forward_m` ahead, in the ship's own axes. The drawn bolt closes onto
## the simulated line, which starts at the ship's centre, within `converge_m`
## of flight. Flashes last `*_flash_s` seconds; 0 turns that flash off.
##
## Each weapon may change its bolt under `weapons`, keyed by weapon id (a
## robot's bolts use its weapon's id, then `robot`); see `ProjectileWeaponLooks`.
## Every key may be left out: a missing key keeps the look the game had before
## the key existed (`DEFAULTS`), so new effects start switched off (#1309).

const DEFAULT_FILE: String = "res://view/projectile_look.json"
## The key holding the per-weapon looks.
const WEAPONS_KEY: String = "weapons"

## Every key of the look file but `weapons`, with the same name as the field it sets.
const KEYS: Array[String] = [
	"bolt_length_m", "bolt_radius_m", "emission_color", "max_lights", "light_range", "light_energy",
	"muzzle_side_m", "muzzle_drop_m", "muzzle_forward_m", "converge_m",
	"muzzle_flash_radius_m", "muzzle_flash_s",
	"impact_color", "impact_flash_radius_m", "impact_flash_s",
	"bolt_shape", "trail_length_m", "trail_color",
	"spark_count", "spark_speed_mps", "spark_s", "spark_color",
	"scorch_radius_m", "scorch_fade_s", "scorch_color",
	"hit_color", "hit_flash_radius_m", "hit_flash_s", "hit_spark_count", "hit_spark_color",
]
## The keys the file had before #1309.
const FIRST_KEYS: Array[String] = [
	"bolt_length_m", "bolt_radius_m", "emission_color", "max_lights", "light_range", "light_energy",
	"muzzle_side_m", "muzzle_drop_m", "muzzle_forward_m", "converge_m",
	"muzzle_flash_radius_m", "muzzle_flash_s",
	"impact_color", "impact_flash_radius_m", "impact_flash_s",
]
## Keys holding [red, green, blue].
const COLOR_KEYS: Array[String] = ["emission_color", "impact_color", "trail_color", "spark_color",
	"scorch_color", "hit_color", "hit_spark_color"]
## Keys that must hold a whole number.
const WHOLE_KEYS: Array[String] = ["max_lights", "spark_count", "hit_spark_count"]
## Keys holding one of a list of names: the allowed names.
const NAME_KEYS: Dictionary[String, Array] = {"bolt_shape": BoltMeshes.SHAPES}

## Allowed range of each number, inclusive: [minimum, maximum]. For a colour
## the range holds for each of its red, green and blue parts.
const RANGES: Dictionary[String, Array] = {
	"bolt_length_m": [0.05, 5.0],
	"bolt_radius_m": [0.005, 0.5],
	"emission_color": [0.0, 1.0],
	# The mobile renderer the Quest uses lights a mesh with at most 8 omni
	# lights, so a larger budget would only cost time without lighting more.
	"max_lights": [0, 8],
	"light_range": [0.5, 30.0],
	"light_energy": [0.0, 16.0],
	"muzzle_side_m": [0.0, 1.0],
	"muzzle_drop_m": [0.0, 1.0],
	# At least this far ahead, so a bolt never starts at the pilot's eye.
	"muzzle_forward_m": [0.35, 2.0],
	"converge_m": [0.5, 20.0],
	"muzzle_flash_radius_m": [0.01, 0.5],
	"muzzle_flash_s": [0.0, 0.5],
	"impact_color": [0.0, 1.0],
	"impact_flash_radius_m": [0.01, 2.0],
	"impact_flash_s": [0.0, 1.0],
	"trail_length_m": [0.0, 8.0],
	"trail_color": [0.0, 1.0],
	# Each burst is one draw call whatever its count; the cap keeps it cheap.
	"spark_count": [0, 32],
	"spark_speed_mps": [0.5, 40.0],
	"spark_s": [0.05, 1.0],
	"spark_color": [0.0, 1.0],
	"scorch_radius_m": [0.05, 2.0],
	"scorch_fade_s": [0.0, 30.0],
	"scorch_color": [0.0, 1.0],
	"hit_color": [0.0, 1.0],
	"hit_flash_radius_m": [0.01, 2.0],
	"hit_flash_s": [0.0, 1.0],
	"hit_spark_count": [0, 32],
	"hit_spark_color": [0.0, 1.0],
}

## The look used for a missing file or key: the look before #1309, with no
## trail, sparks or scorch, and robot hits flashed like wall hits.
const DEFAULTS: Dictionary[String, Variant] = {
	"bolt_length_m": 0.6,
	"bolt_radius_m": 0.03,
	"emission_color": Color(1.0, 0.55, 0.15),
	"max_lights": 4,
	"light_range": 6.0,
	"light_energy": 1.5,
	"muzzle_side_m": 0.3,
	"muzzle_drop_m": 0.25,
	"muzzle_forward_m": 0.6,
	"converge_m": 4.0,
	"muzzle_flash_radius_m": 0.08,
	"muzzle_flash_s": 0.06,
	"impact_color": Color(1.0, 0.85, 0.55),
	"impact_flash_radius_m": 0.3,
	"impact_flash_s": 0.15,
	"bolt_shape": "cylinder",
	"trail_length_m": 0.0,
	"trail_color": Color(0.5, 0.25, 0.08),
	"spark_count": 0,
	"spark_speed_mps": 6.0,
	"spark_s": 0.25,
	"spark_color": Color(1.0, 0.8, 0.45),
	"scorch_radius_m": 0.25,
	"scorch_fade_s": 0.0,
	"scorch_color": Color(0.05, 0.04, 0.03),
	"hit_color": Color(1.0, 0.85, 0.55),
	"hit_flash_radius_m": 0.3,
	"hit_flash_s": 0.15,
	"hit_spark_count": 0,
	"hit_spark_color": Color(0.6, 0.85, 1.0),
}


## Parses the text of a look file: one JSON object holding keys of `KEYS`,
## the numbers in their ranges, each colour as three numbers, and optionally
## `weapons`. Returns the values by key, a missing key at its default, with
## `weapons` as weapon id to its own checked keys; or a dictionary holding
## only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or key == WEAPONS_KEY):
			return _rejected("unknown key \"%s\"" % str(key))
	var values: Dictionary = {}
	for key: String in KEYS:
		if not data.has(key):
			values[key] = DEFAULTS[key]
			continue
		var checked: Variant = check_value(key, data[key])
		if checked is Dictionary:
			return checked
		values[key] = checked
	var weapons: Dictionary = ProjectileWeaponLooks.parse(data.get(WEAPONS_KEY, {}))
	if weapons.has("error"):
		return weapons
	values[WEAPONS_KEY] = weapons
	return values


## `value` for `key` turned into its type (a `Color` for a colour), or a
## dictionary holding only `"error"` naming the key.
static func check_value(key: String, value: Variant) -> Variant:
	if NAME_KEYS.has(key):
		if typeof(value) != TYPE_STRING or not NAME_KEYS[key].has(value):
			return _rejected("key \"%s\" must be one of %s" % [key, NAME_KEYS[key]])
		return value
	var parts: Array = [value]
	if COLOR_KEYS.has(key):
		if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
			return _rejected("key \"%s\" must be [red, green, blue]" % key)
		parts = value
	for part: Variant in parts:
		# A bool must not pass as 0 or 1.
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return _rejected("key \"%s\" must hold numbers" % key)
		if WHOLE_KEYS.has(key) and float(part) != floorf(float(part)):
			return _rejected("key \"%s\" must be a whole number" % key)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(part) < low or float(part) > high:
			return _rejected("key \"%s\" has %s, must be within %s..%s" % [key, part, low, high])
	if COLOR_KEYS.has(key):
		return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	if WHOLE_KEYS.has(key):
		return int(value)
	return float(value)


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
