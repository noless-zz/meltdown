class_name CockpitInstrument
extends RefCounted

## One instrument a cockpit file declares (#1216, ARC-4): which gauge it reads
## (`ShipGauges.NAMES`), where on the frame it sits and how it looks. Since
## #1461 the frame draws each one as a lit bar on the console
## (`ConsoleGauges`), part of the cockpit model and fixed to it, never to the
## head (CMF-8). View only: an instrument reads `ShipGauges` and writes nothing
## (ARC-3, CMF-6).
##
## Each entry of a cockpit file's optional `instruments` list:
##   {"id": "hull_bar", "gauge": "hull", "yaw_deg": -13.5, "pitch_deg": -34,
##    "distance_m": 0.35, "size_m": [0.075, 0.034], "label": "HULL",
##    "color": [0.55, 0.95, 1.0], "low_color": [1.0, 0.45, 0.25],
##    "low_below": 0.25, "low_pulse_s": 1.6, "low_pulse_min": 0.7}
## `yaw_deg` is degrees right of straight ahead (negative is left), and
## `pitch_deg` degrees above it (negative is below), seen from the eye point.
## The first four keys are required; the rest have the defaults below. Below
## `low_below` of its gauge the bar takes `low_color` and pulses slowly between
## `low_pulse_min` and full brightness once every `low_pulse_s` seconds: at
## least a second and never dark, so it is a pulse and not a flash (CMF-8).

## The file's key holding the list.
const LIST_KEY: String = "instruments"
## Every key an entry must have.
const KEYS: Array[String] = ["id", "gauge", "yaw_deg", "pitch_deg"]
## Keys an entry may have.
const OPTIONAL_KEYS: Array[String] = ["distance_m", "size_m", "label", "color", "low_color",
	"low_below", "low_pulse_s", "low_pulse_min"]
## Both angles must lie within this many degrees of straight ahead.
const MAX_ANGLE_DEG: float = 90.0
## The allowed range of each optional number key.
const RANGES: Dictionary[String, Vector2] = {
	"distance_m": Vector2(0.3, 0.8),
	"low_below": Vector2(0.0, 1.0),
	"low_pulse_s": Vector2(1.0, 10.0),
	"low_pulse_min": Vector2(0.5, 1.0),
}
## Width and height of the instrument's face, metres, each within this range.
const SIZE_RANGE_M: Vector2 = Vector2(0.01, 0.2)
## Longest label, characters: a word, not a sentence.
const MAX_LABEL_LENGTH: int = 12

## Unique within its cockpit file.
var id: String = ""
## One of `ShipGauges.NAMES`.
var gauge: String = ""
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
## From the eye to the instrument's face, metres; nearer than the shell.
var distance_m: float = 0.35
## Width along the yaw and height along the pitch of the face, metres.
var size_m: Vector2 = Vector2(0.075, 0.034)
## Text above the bar; empty draws none.
var label: String = ""
var color: Color = Color(0.55, 0.95, 1.0)
var low_color: Color = Color(1.0, 0.45, 0.25)
## The low state shows while the gauge is below this fraction.
var low_below: float = 0.25
var low_pulse_s: float = 1.6
var low_pulse_min: float = 0.7


## Parses the `instruments` value of a cockpit file whose shell is
## `frame_distance_m` from the eye. Returns an `Array[CockpitInstrument]`, or a
## message naming the field at fault ("instruments[1].gauge ...").
static func parse_list(value: Variant, frame_distance_m: float = INF) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return "\"%s\" must be a list" % LIST_KEY
	var list: Array[CockpitInstrument] = []
	var ids: Array[String] = []
	for index: int in (value as Array).size():
		var field: String = "%s[%d]" % [LIST_KEY, index]
		var parsed: Variant = parse_entry(value[index], field)
		if parsed is String:
			return parsed
		var instrument: CockpitInstrument = parsed
		if ids.has(instrument.id):
			return "%s.id \"%s\" is used twice" % [field, instrument.id]
		if instrument.distance_m >= frame_distance_m:
			return "%s.distance_m is %s, not nearer than frame_distance_m %s" % [
				field, instrument.distance_m, frame_distance_m]
		ids.append(instrument.id)
		list.append(instrument)
	return list


## Parses one entry; `field` names it in messages. Returns the instrument or
## a message naming the field at fault.
static func parse_entry(entry: Variant, field: String) -> Variant:
	if typeof(entry) != TYPE_DICTIONARY:
		return "%s must be an object" % field
	var data: Dictionary = entry
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or OPTIONAL_KEYS.has(key)):
			return "%s has unknown key \"%s\"" % [field, str(key)]
	for key: String in KEYS:
		if not data.has(key):
			return "%s.%s is missing" % [field, key]
	var instrument: CockpitInstrument = CockpitInstrument.new()
	if typeof(data["id"]) != TYPE_STRING or String(data["id"]).strip_edges().is_empty():
		return "%s.id must be a non-empty text" % field
	instrument.id = String(data["id"])
	if typeof(data["gauge"]) != TYPE_STRING or not ShipGauges.NAMES.has(data["gauge"]):
		return "%s.gauge \"%s\" is not one of %s" % [field, str(data["gauge"]), ", ".join(ShipGauges.NAMES)]
	instrument.gauge = String(data["gauge"])
	for key: String in ["yaw_deg", "pitch_deg"]:
		var angle: Variant = data[key]
		if not CockpitSpec._is_number(angle):  # A bool must not pass as 0 or 1.
			return "%s.%s must be a number" % [field, key]
		if absf(float(angle)) > MAX_ANGLE_DEG:
			return "%s.%s is %s, must be within -%s..%s" % [field, key, angle, MAX_ANGLE_DEG, MAX_ANGLE_DEG]
		instrument.set(key, float(angle))
	var problem: String = _parse_look(data, instrument)
	if problem != "":
		return "%s.%s" % [field, problem]
	return instrument


## Whether `value` of the gauge shows the low state.
func is_low(value: float) -> bool:
	return fill(value) < low_below


## How full the bar is drawn for `value`: 0..1, empty for a value that is not
## a finite number (as the status panel's bars draw it).
func fill(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


## Brightness of the bar `time_s` seconds into a showing, 0..1: full when not
## `low`, else a smooth pulse from full down to `low_pulse_min` and back.
func brightness(time_s: float, low: bool) -> float:
	if not low:
		return 1.0
	return lerpf(low_pulse_min, 1.0, 0.5 + 0.5 * cos(TAU * time_s / low_pulse_s))


## The bar's colour for `value` at `time_s`.
func bar_color(value: float, time_s: float) -> Color:
	var low: bool = is_low(value)
	var base: Color = low_color if low else color
	var shade: float = brightness(time_s, low)
	return Color(base.r * shade, base.g * shade, base.b * shade)


## Sets the optional keys of `data` on `instrument`; the key at fault and why,
## or "".
static func _parse_look(data: Dictionary, instrument: CockpitInstrument) -> String:
	for key: String in RANGES:
		if not data.has(key):
			continue
		var bounds: Vector2 = RANGES[key]
		if not CockpitSpec._is_number(data[key]):
			return "%s must be a number" % key
		if float(data[key]) < bounds.x or float(data[key]) > bounds.y:
			return "%s is %s, must be within %s..%s" % [key, data[key], bounds.x, bounds.y]
		instrument.set(key, float(data[key]))
	if data.has("size_m"):
		var size: Variant = data["size_m"]
		if typeof(size) != TYPE_ARRAY or (size as Array).size() != 2:
			return "size_m must be an array of two numbers"
		for part: Variant in size:
			if not CockpitSpec._is_number(part) or float(part) < SIZE_RANGE_M.x or float(part) > SIZE_RANGE_M.y:
				return "size_m has %s, each part must be a number within %s..%s" % [
					part, SIZE_RANGE_M.x, SIZE_RANGE_M.y]
		instrument.size_m = Vector2(float(size[0]), float(size[1]))
	if data.has("label"):
		if typeof(data["label"]) != TYPE_STRING or String(data["label"]).length() > MAX_LABEL_LENGTH:
			return "label must be a text of at most %d characters" % MAX_LABEL_LENGTH
		instrument.label = String(data["label"])
	for key: String in ["color", "low_color"]:
		if not data.has(key):
			continue
		var color_error: String = CockpitSpec._color_error(data[key])
		if color_error != "":
			return "%s %s" % [key, color_error]
		var parts: Array = data[key]
		instrument.set(key, Color(float(parts[0]), float(parts[1]), float(parts[2])))
	return ""
