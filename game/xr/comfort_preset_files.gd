class_name ComfortPresetFiles
extends RefCounted

## Where the four comfort presets live and how a run picks one (CMF-1, CMF-4).
## Kept out of `main.gd` so the scene script stays short.

## The comfort preset a run starts with until the first-launch flight test
## (CMF-4) picks one. `--comfort-preset=1..4` overrides it.
const START_NUMBER: int = 2
## Preset files in the numbering of the comfort table (CMF-1): index 0 is preset 1.
const PATHS: Array[String] = [
	"res://xr/presets/comfort_anchored.tres", "res://xr/presets/comfort_guided.tres",
	"res://xr/presets/comfort_pilot.tres", "res://xr/presets/comfort_unrestricted.tres",
]
## The custom comfort mode's place in the preset cycle (CMF-1, #806): after the
## four shipped presets, offered only while a custom file is accepted.
const CUSTOM_NUMBER: int = 5
const ARG: String = "--comfort-preset="
## Fields whose value in a `.tres` preset file must be written as a number. Godot turns
## any text assigned to a `float` field into 0, which would pass as "off", so
## the file text is checked before the loaded value.
const NUMBER_FIELDS: Array[String] = ["break_reminder_minutes"]


## Preset `number` (1..4).
static func load_number(number: int) -> ComfortPreset:
	return load_path(PATHS[number - 1])


## The preset file at `path`, or null when it is missing, is not a
## `ComfortPreset`, or fails `ComfortPreset.validation_error()`.
static func load_path(path: String) -> ComfortPreset:
	if not ResourceLoader.exists(path):
		push_warning("Meltdown: comfort preset %s rejected: file not found" % path)
		return null
	var preset: ComfortPreset = load(path) as ComfortPreset
	if preset == null:
		push_warning("Meltdown: comfort preset %s rejected: not a ComfortPreset" % path)
		return null
	var error: String = ""
	# An exported build holds the presets as binary `.res` with typed values and
	# no `.tres` text, so the written-number check applies only where the text
	# exists; the shipped files pass it in the tests before any export.
	if path.get_extension() == "tres" and FileAccess.file_exists(path):
		error = written_number_error(FileAccess.get_file_as_string(path), NUMBER_FIELDS)
	if error.is_empty():
		error = preset.validation_error()
	if not error.is_empty():
		push_warning("Meltdown: comfort preset %s rejected: %s" % [path, error])
		return null
	return preset


## The custom comfort mode (CMF-1) from the JSON file at `path`, or null when
## there is none. A bad field is reported naming it, and the base preset is used
## unchanged; see `ComfortCustom`.
static func load_custom(path: String = ComfortCustom.DEFAULT_PATH) -> ComfortPreset:
	return ComfortCustom.load_from(path).preset


## 1 > 2 > 3 > 4 > 1.
static func next_number(number: int) -> int:
	return number % PATHS.size() + 1


## The last `--comfort-preset=N` with N in 1..4, else `START_NUMBER`.
static func number_from_args(args: PackedStringArray) -> int:
	var number: int = START_NUMBER
	for arg: String in args:
		if not arg.begins_with(ARG):
			continue
		var value: String = arg.substr(ARG.length())
		var valid: bool = value.is_valid_int() and int(value) >= 1 and int(value) <= PATHS.size()
		number = int(value) if valid else START_NUMBER
	return number


## Empty when every field in `fields` appears in the `.tres` text exactly once,
## written as a plain number; otherwise names the first that does not.
static func written_number_error(text: String, fields: Array[String]) -> String:
	for field: String in fields:
		var line: RegEx = RegEx.create_from_string("(?m)^%s = (.*)$" % field)
		var found: Array[RegExMatch] = line.search_all(text)
		if found.size() != 1:
			return "%s is written %d times, expected once" % [field, found.size()]
		var value: String = found[0].get_string(1).strip_edges()
		if not value.is_valid_float():
			return "%s is %s, must be a number" % [field, value]
	return ""
