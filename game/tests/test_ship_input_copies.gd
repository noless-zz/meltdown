extends RefCounted

## Every `ShipInput` field survives the copies in `LatestInputSource` and
## `ComfortInputFilter` (#99), so a field added later, such as a fire button,
## cannot be dropped on its way to the simulation (MP-2, ARC-3).

const PRESET_DIR: String = "res://xr/presets"
const PRESETS: Array[String] = ["anchored", "guided", "pilot", "unrestricted"]


static func _load(preset_name: String) -> ComfortPreset:
	return ResourceLoader.load("%s/comfort_%s.tres" % [PRESET_DIR, preset_name], "",
		ResourceLoader.CACHE_MODE_IGNORE) as ComfortPreset


## Names of `ShipInput`'s script properties.
static func _field_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in ShipInput.new().get_script().get_script_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(StringName(property["name"]))
	return names


## An input with every field away from its default, or null with the field
## whose type the test does not know how to change.
static func _all_set() -> Array:
	var input: ShipInput = ShipInput.new()
	for field: StringName in _field_names():
		var value: Variant = input.get(field)
		match typeof(value):
			TYPE_BOOL:
				input.set(field, not bool(value))
			TYPE_INT:
				input.set(field, int(value) + 7)
			TYPE_FLOAT:
				input.set(field, float(value) + 0.5)
			TYPE_VECTOR3I:
				input.set(field, Vector3i(value) + Vector3i(110, -220, 330))
			TYPE_VECTOR3:
				input.set(field, Vector3(value) + Vector3(0.1, -0.2, 0.3))
			_:
				return [null, field]
	return [input, &""]


## The first field of `got` that differs from `want`, skipping `skip`.
static func _differs(want: ShipInput, got: ShipInput, skip: Array[StringName] = []) -> String:
	for field: StringName in _field_names():
		if skip.has(field):
			continue
		if got.get(field) != want.get(field):
			return "%s is %s, want %s" % [field, str(got.get(field)), str(want.get(field))]
	return ""


func test_ship_input_has_the_fields_the_test_expects() -> String:
	var names: Array[StringName] = _field_names()
	for field: StringName in [&"thrust_q", &"turn_q", &"afterburner", &"reset_to_start"]:
		if not names.has(field):
			return "ShipInput has no %s; the field list was not read" % field
	return ""


func test_reset_to_start_survives_the_input_source() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, true))
	if not source.next_input(0).reset_to_start:
		return "next_input dropped reset_to_start"
	if not source.latest_input().reset_to_start:
		return "latest_input dropped reset_to_start"
	return ""


func test_reset_to_start_survives_the_filter_in_every_preset() -> String:
	for preset_name: String in PRESETS:
		var filter: ComfortInputFilter = ComfortInputFilter.new(_load(preset_name))
		var input: ShipInput = ShipInput.new(Vector3i(0, 0, -1000), Vector3i(300, 300, 300),
			false, true)
		if not filter.filter(input, Basis(Vector3.FORWARD, 0.5)).reset_to_start:
			return "%s dropped reset_to_start" % preset_name
	return ""


func test_every_field_survives_the_input_source() -> String:
	var made: Array = _all_set()
	if made[0] == null:
		return "no test value for ShipInput.%s; extend _all_set" % made[1]
	var input: ShipInput = made[0]
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(input)
	for got: ShipInput in [source.next_input(0), source.latest_input()]:
		var message: String = _differs(input, got)
		if message != "":
			return "input source: " + message
	return ""


func test_every_field_survives_the_filter() -> String:
	var made: Array = _all_set()
	if made[0] == null:
		return "no test value for ShipInput.%s; extend _all_set" % made[1]
	var input: ShipInput = made[0]
	# Preset 4 changes nothing, so every field must come out as it went in.
	var untouched: ShipInput = ComfortInputFilter.new(_load("unrestricted")).filter(input)
	var message: String = _differs(input, untouched)
	if message != "":
		return "unrestricted: " + message
	# The other presets may change the turn, and nothing else.
	var turn_only: Array[StringName] = [&"turn_q"]
	for preset_name: String in PRESETS:
		var out: ShipInput = ComfortInputFilter.new(_load(preset_name)).filter(input)
		message = _differs(input, out, turn_only)
		if message != "":
			return "%s: %s" % [preset_name, message]
	return ""


func test_the_filter_copy_does_not_share_the_input() -> String:
	var input: ShipInput = ShipInput.new(Vector3i(1, 2, 3), Vector3i(4, 5, 6), true, true)
	var out: ShipInput = ComfortInputFilter.copy_input(input)
	out.reset_to_start = false
	out.thrust_q = Vector3i.ZERO
	if not input.reset_to_start or input.thrust_q != Vector3i(1, 2, 3):
		return "changing the copy changed the original"
	return ""
