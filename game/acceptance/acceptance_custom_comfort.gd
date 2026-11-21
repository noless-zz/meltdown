class_name AcceptanceCustomComfort
extends RefCounted

## A step's `custom_file` (#836, CMF-1, CMF-6): fly the step in the custom
## comfort mode built from a shipped custom comfort file, the way a player who
## saved one flies it. The scene's `ComfortWiring` reads that file in place of
## the one in user storage, and the step chooses `CUSTOM_NUMBER` through the
## scene's own `set_comfort_preset`, as a numbered `preset` does. A file that
## `ComfortCustom` rejects fails the step, naming the rejected field: the
## wiring would quietly keep the preset before it, and the step would then pass
## on limits it never asked for.
##
## In a suite: `"custom_file": "res://acceptance/comfort/m1_custom.json"`,
## instead of `preset`.

const KEY: String = "custom_file"
const PATH_PREFIX: String = "res://"


## Reads `custom_file` from a step's JSON into `step`; "" or the problem, with
## the field named. Whether the file is accepted is decided when the step runs,
## so a rejected file fails that step and not the whole suite.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if not data.has(KEY):
		return ""
	var where: String = "%s.%s" % [field, KEY]
	var value: Variant = data[KEY]
	if typeof(value) != TYPE_STRING or not str(value).begins_with(PATH_PREFIX) or str(value) == PATH_PREFIX:
		return "%s: must be a %s path to a custom comfort file" % [where, PATH_PREFIX]
	if data.has("preset"):
		return "%s: a step flies a numbered preset or a custom file, not both" % where
	step.custom_file = value
	return ""


## Puts `main` in the custom mode of `step.custom_file`; "" when it did, or
## when the step names no file, else why not, naming the rejected field.
static func apply(main: Node, step: AcceptanceStep) -> String:
	if step.custom_file == "":
		return ""
	var wiring: ComfortWiring = main.get("comfort") as ComfortWiring
	if wiring == null:
		return "%s: the scene has no comfort wiring to fly it" % KEY
	var custom: ComfortCustom = ComfortCustom.load_from(step.custom_file)
	if custom.preset == null:
		return "%s: %s not found" % [KEY, step.custom_file]
	if custom.error != "":
		return "%s: %s rejected, field \"%s\": %s" % [KEY, step.custom_file, custom.rejected_field(), custom.error]
	wiring.custom_path = step.custom_file
	# The wiring reads its file once and keeps it, so a file it read earlier
	# (the one in user storage, or none) would otherwise stay in force. The
	# accepted file is handed over as read, so it is not read twice.
	wiring.set("_custom", custom)
	main.call("set_comfort_preset", ComfortPresetFiles.CUSTOM_NUMBER)
	if wiring.number != ComfortPresetFiles.CUSTOM_NUMBER:
		return "%s: the scene stayed on preset %d" % [KEY, wiring.number]
	return ""
