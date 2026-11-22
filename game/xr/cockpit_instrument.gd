class_name CockpitInstrument
extends RefCounted

## One instrument a cockpit file declares (#1216, ARC-4): which gauge it reads
## (`ShipGauges.NAMES`) and where on the frame it sits. The owner asked for
## hull, shield and energy to move from the panel into the cockpit itself;
## the instruments are drawn with M6's cockpit design, so for now a file only
## declares them and `CockpitSpec` checks the list. View only: an instrument
## reads `ShipGauges` and writes nothing (ARC-3, CMF-6).
##
## Each entry of a cockpit file's optional `instruments` list:
##   {"id": "hull_dial", "gauge": "hull", "yaw_deg": -20, "pitch_deg": -30}
## `yaw_deg` is degrees right of straight ahead (negative is left), and
## `pitch_deg` degrees above it (negative is below), seen from the eye point.

## The file's key holding the list.
const LIST_KEY: String = "instruments"
## Every key of one entry; all are required.
const KEYS: Array[String] = ["id", "gauge", "yaw_deg", "pitch_deg"]
## Both angles must lie within this many degrees of straight ahead.
const MAX_ANGLE_DEG: float = 90.0

## Unique within its cockpit file.
var id: String = ""
## One of `ShipGauges.NAMES`.
var gauge: String = ""
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0


## Parses the `instruments` value of a cockpit file. Returns an
## `Array[CockpitInstrument]`, or a message naming the field at fault
## ("instruments[1].gauge ...").
static func parse_list(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return "\"%s\" must be a list" % LIST_KEY
	var list: Array[CockpitInstrument] = []
	var ids: Array[String] = []
	for index: int in (value as Array).size():
		var parsed: Variant = parse_entry(value[index], "%s[%d]" % [LIST_KEY, index])
		if parsed is String:
			return parsed
		var instrument: CockpitInstrument = parsed
		if ids.has(instrument.id):
			return "%s[%d].id \"%s\" is used twice" % [LIST_KEY, index, instrument.id]
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
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
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
		# A bool must not pass as 0 or 1.
		if typeof(angle) != TYPE_FLOAT and typeof(angle) != TYPE_INT:
			return "%s.%s must be a number" % [field, key]
		if absf(float(angle)) > MAX_ANGLE_DEG:
			return "%s.%s is %s, must be within -%s..%s" % [field, key, angle, MAX_ANGLE_DEG, MAX_ANGLE_DEG]
		instrument.set(key, float(angle))
	return instrument
