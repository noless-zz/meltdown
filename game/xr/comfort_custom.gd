class_name ComfortCustom
extends RefCounted

## The custom comfort mode (CMF-1): one of the four presets with any row of the
## comfort table changed, read from a JSON file in user storage.
##
## JSON rather than `.tres`, because a resource file from user storage can carry
## a script. The file names only `ComfortPreset` fields, and a preset holds no
## speed, damage or timer, so a custom file cannot change the simulation
## (CMF-6, ARC-3). `ComfortWiring` offers it after preset 4 (#806); a settings
## menu (M8) will write the file.
##
## The file is `{"base": 1..4, "display_name": "...", "<field>": <value>, ...}`.
## Enum fields take the value's name (`"SNAP"`), so reordering an enum cannot
## silently change what a saved file means.

const DEFAULT_PATH: String = "user://meltdown_comfort_custom.json"
const FIELD_BASE: String = "base"
const FIELD_NAME: String = "display_name"
const DEFAULT_NAME: String = "Custom"
const LOG_PREFIX: String = "Meltdown: custom comfort"
## Preset fields the custom file may not set. Look-aim stays off in custom mode,
## as at presets 3 and 4, until the owner decides (decision record 0010).
const NOT_SETTABLE: Array[String] = ["look_aim"]

## The preset to use, or null when there is no custom file.
var preset: ComfortPreset = null
## Why the file was not applied, naming the field; empty when it was, or when
## the file is simply missing.
var error: String = ""
## The file's base preset (1..4) when it was accepted, 0 otherwise; a saved
## custom choice falls back to it when the file is gone (#806).
var base: int = 0


## The field `error` names, short enough for the status panel's preset row
## (#807): `base` for `field "base" is 7, ...`, the field a range check names,
## or, for a file that is not a usable object at all, the reason without its
## detail (`not JSON`). Empty when the file was not rejected.
func rejected_field() -> String:
	if error.is_empty():
		return ""
	var quoted: RegExMatch = RegEx.create_from_string("field \"([^\"]+)\"").search(error)
	if quoted != null:
		return quoted.get_string(1)
	# `ComfortPreset.validation_error` starts with the field's name.
	var named: RegExMatch = RegEx.create_from_string("^([a-z_]+) is ").search(error)
	if named != null:
		return named.get_string(1)
	return error.get_slice(" (", 0)


## Reads `path`. A missing file gives no preset. A file that cannot be read, or
## whose base is bad, gives the start preset; a bad field gives the base preset
## unchanged. Either way `error` names the reason.
static func load_from(path: String = DEFAULT_PATH) -> ComfortCustom:
	if not FileAccess.file_exists(path):
		return ComfortCustom.new()
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		return _fallback(null, "file could not be read (%s)" % error_string(FileAccess.get_open_error()))
	return parse(text)


## Builds the custom preset from the JSON `text`; see `load_from`.
static func parse(text: String) -> ComfortCustom:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _fallback(null, "not JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fallback(null, "not a JSON object")
	var data: Dictionary = json.data
	var base_error: String = _base_error(data)
	if not base_error.is_empty():
		return _fallback(null, base_error)
	var base: ComfortPreset = ComfortPresetFiles.load_number(int(data[FIELD_BASE]))
	if base == null:
		return _fallback(null, "base preset %d could not be loaded" % int(data[FIELD_BASE]))
	# A duplicate, so the shipped preset that later loads share is never changed.
	var custom: ComfortPreset = base.duplicate() as ComfortPreset
	custom.display_name = DEFAULT_NAME
	custom.look_aim = false
	var fields: Dictionary = settable_fields()
	for key: Variant in data.keys():
		var field: String = str(key)
		if field == FIELD_BASE:
			continue
		if not fields.has(field):
			return _fallback(base, "unknown field \"%s\"" % field)
		var converted: Array = _convert(field, fields[field], data[key])
		if converted[1] != "":
			return _fallback(base, converted[1])
		custom.set(field, converted[0])
	var invalid: String = custom.validation_error()
	if not invalid.is_empty():
		return _fallback(base, invalid)
	var result: ComfortCustom = ComfortCustom.new()
	result.preset = custom
	result.base = int(data[FIELD_BASE])
	return result


## Every exported `ComfortPreset` field by name, with its property description.
## Taken from the script itself, so a field added to the comfort table later is
## settable here without a change.
static func settable_fields() -> Dictionary:
	var fields: Dictionary = {}
	for property: Dictionary in ComfortPreset.new().get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR \
				and not NOT_SETTABLE.has(property["name"]):
			fields[property["name"]] = property
	return fields


static func _fallback(base: ComfortPreset, reason: String) -> ComfortCustom:
	push_warning("%s ignored: %s" % [LOG_PREFIX, reason])
	var result: ComfortCustom = ComfortCustom.new()
	result.preset = base if base != null else ComfortPresetFiles.load_number(ComfortPresetFiles.START_NUMBER)
	result.error = reason
	return result


static func _base_error(data: Dictionary) -> String:
	if not data.has(FIELD_BASE):
		return "field \"%s\" missing" % FIELD_BASE
	var value: Variant = data[FIELD_BASE]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "field \"%s\" is %s, expected a number" % [FIELD_BASE, type_string(typeof(value))]
	var number: float = float(value)
	if number != floorf(number) or number < 1 or number > ComfortPresetFiles.PATHS.size():
		return "field \"%s\" is %s, expected 1..%d" % [FIELD_BASE, str(value), ComfortPresetFiles.PATHS.size()]
	return ""


## `[value, ""]` with the JSON value turned into the field's type, or
## `[null, reason]` naming the field.
static func _convert(field: String, property: Dictionary, value: Variant) -> Array:
	var type: int = property["type"]
	var hint: int = property["hint"]
	var hint_string: String = property["hint_string"]
	var got: String = type_string(typeof(value))
	match type:
		TYPE_BOOL:
			if typeof(value) != TYPE_BOOL:
				return [null, "field \"%s\" is %s, expected true or false" % [field, got]]
			return [value, ""]
		TYPE_STRING:
			if typeof(value) != TYPE_STRING:
				return [null, "field \"%s\" is %s, expected text" % [field, got]]
			# Only a shipped file, so the custom file cannot point the cockpit at
			# data in user storage.
			if hint == PROPERTY_HINT_FILE and not (str(value).begins_with("res://") and FileAccess.file_exists(value)):
				return [null, "field \"%s\" is \"%s\", expected a shipped res:// file" % [field, value]]
			return [value, ""]
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				return _convert_enum(field, str(property["class_name"]).get_slice(".", 1), value)
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return [null, "field \"%s\" is %s, expected a whole number" % [field, got]]
			if float(value) != floorf(float(value)):
				return [null, "field \"%s\" is %s, expected a whole number" % [field, str(value)]]
			return [int(value), ""]
		TYPE_FLOAT:
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return [null, "field \"%s\" is %s, expected a number" % [field, got]]
			var number: float = float(value)
			if hint == PROPERTY_HINT_RANGE:
				var bounds: PackedStringArray = hint_string.split(",")
				if number < float(bounds[0]) or number > float(bounds[1]):
					return [null, "field \"%s\" is %s, expected %s..%s" % [field, str(value), bounds[0], bounds[1]]]
			return [number, ""]
	return [null, "field \"%s\" has a type the custom file cannot set" % field]


## The file gives the value's name as written in `ComfortPreset`'s enum
## (`"SNAP"`); the property's hint text holds only prettified names.
static func _convert_enum(field: String, enum_name: String, value: Variant) -> Array:
	var script: Script = load("res://xr/comfort_preset.gd") as Script
	var values: Dictionary = script.get_script_constant_map().get(enum_name, {})
	if typeof(value) == TYPE_STRING and values.has(value):
		return [values[value], ""]
	var names: PackedStringArray = []
	for key: Variant in values.keys():
		names.append(str(key))
	return [null, "field \"%s\" is %s, expected one of %s" % [field, JSON.stringify(value), ", ".join(names)]]
