class_name AcceptanceControlsScript
extends RefCounted

## A step's `controls` and `left_handed` fields (#818, PLT-5, ARC-2, DEV-6): a
## flight scripted as raw controller values, flown through the scene's
## `ThumbstickMapping` with left-handed mode on or off, so a suite can show
## that a mirrored flight left-handed ends where the plain one does
## right-handed.
##
## In a suite: `"controls": "res://acceptance/replays/<name>.controls.json"`,
## with `"left_handed": true` or false (the default). The step's `replay` still
## names the level the flight starts in; its recorded inputs are not flown.
##
## A controls file is a JSON object `{"segments": [...]}`. Each segment holds
## `ticks` (a whole number from 1 up) and any of `left_stick` and `right_stick`
## (`[x, y]`, each -1..1), `left_trigger`, `right_trigger`, `left_grip` and
## `right_grip` (0..1), and `buttons` (names from `ThumbstickMapping.BUTTONS`,
## held for the whole segment). A control a segment does not name is at rest.

const KEY_CONTROLS: String = "controls"
const KEY_LEFT_HANDED: String = "left_handed"
const KEY_SEGMENTS: String = "segments"
const KEY_TICKS: String = "ticks"
const STICKS: Array[String] = ["left_stick", "right_stick"]
const PULLS: Array[String] = ["left_trigger", "right_trigger", "left_grip", "right_grip"]
const KEY_BUTTONS: String = "buttons"

## One `ControllerSampler` values dictionary per tick, or empty when `error` is set.
var frames: Array[Dictionary] = []
var error: String = ""


## The controls file at `path`; `error` says why it could not be read.
static func load_file(path: String) -> AcceptanceControlsScript:
	if not FileAccess.file_exists(path):
		return _failed("no controls file at %s" % path)
	return from_json(FileAccess.get_file_as_string(path))


static func from_json(text: String) -> AcceptanceControlsScript:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get(KEY_SEGMENTS)) != TYPE_ARRAY:
		return _failed("must be a JSON object with a list of %s" % KEY_SEGMENTS)
	var data: Dictionary = json.data
	var problem: String = AcceptanceStepParser.unknown_key(data, [KEY_SEGMENTS], "")
	if problem != "":
		return _failed(problem)
	var script: AcceptanceControlsScript = AcceptanceControlsScript.new()
	var segments: Array = data[KEY_SEGMENTS]
	if segments.is_empty():
		return _failed("%s: must hold at least one segment" % KEY_SEGMENTS)
	for index: int in segments.size():
		problem = script._add_segment(segments[index], "%s[%d]" % [KEY_SEGMENTS, index])
		if problem != "":
			return _failed(problem)
	return script


static func _failed(message: String) -> AcceptanceControlsScript:
	var script: AcceptanceControlsScript = AcceptanceControlsScript.new()
	script.error = message
	return script


func _add_segment(raw: Variant, field: String) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "%s: must be a JSON object" % field
	var segment: Dictionary = raw
	var allowed: Array[String] = [KEY_TICKS, KEY_BUTTONS]
	allowed.append_array(STICKS)
	allowed.append_array(PULLS)
	var problem: String = AcceptanceStepParser.unknown_key(segment, allowed, field + ".")
	if problem != "":
		return problem
	if not AcceptanceStepParser.is_whole(segment.get(KEY_TICKS)) or int(segment[KEY_TICKS]) < 1:
		return "%s.%s: must be a whole number from 1 up" % [field, KEY_TICKS]
	var values: Dictionary = ControllerSampler.idle_values()
	for stick: String in STICKS:
		if segment.has(stick):
			var pair: Variant = segment[stick]
			if typeof(pair) != TYPE_ARRAY or (pair as Array).size() != 2 or not _in_range(pair[0], -1.0) \
					or not _in_range(pair[1], -1.0):
				return "%s.%s: must be [x, y], each a number in -1..1" % [field, stick]
			values[stick] = Vector2(float(pair[0]), float(pair[1]))
	for pull: String in PULLS:
		if segment.has(pull):
			if not _in_range(segment[pull], 0.0):
				return "%s.%s: must be a number in 0..1" % [field, pull]
			values[pull] = float(segment[pull])
	var buttons: Dictionary = {}
	if segment.has(KEY_BUTTONS):
		if typeof(segment[KEY_BUTTONS]) != TYPE_ARRAY:
			return "%s.%s: must be a list of button names" % [field, KEY_BUTTONS]
		for button: Variant in segment[KEY_BUTTONS]:
			if typeof(button) != TYPE_STRING or not ThumbstickMapping.BUTTONS.has(button):
				return "%s.%s: unknown button \"%s\"" % [field, KEY_BUTTONS, str(button)]
			buttons[str(button)] = true
	values[KEY_BUTTONS] = buttons
	for tick: int in int(segment[KEY_TICKS]):
		frames.append(values.duplicate(true))
	return ""


static func _in_range(value: Variant, low: float) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and float(value) >= low \
		and float(value) <= 1.0


## Reads `controls` and `left_handed` from a step's JSON into `step`; "" or
## the problem, with the field named. Runs after `loop_replay` is read.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if data.has(KEY_LEFT_HANDED):
		if typeof(data[KEY_LEFT_HANDED]) != TYPE_BOOL:
			return "%s.%s: must be true or false" % [field, KEY_LEFT_HANDED]
		if not data.has(KEY_CONTROLS):
			return "%s.%s: only used with controls; a replay's inputs never pass the mapping" % [
				field, KEY_LEFT_HANDED]
		step.left_handed = data[KEY_LEFT_HANDED]
	if not data.has(KEY_CONTROLS):
		return ""
	var where: String = "%s.%s" % [field, KEY_CONTROLS]
	if typeof(data[KEY_CONTROLS]) != TYPE_STRING or str(data[KEY_CONTROLS]) == "":
		return "%s: must be a non-empty path" % where
	if step.replay_path == "":
		return "%s: needs a replay to name the level the flight starts in" % where
	if step.loop_replay:
		return "%s: a scripted flight does not loop; drop %s" % [where, AcceptanceLoopReplay.KEY]
	var script: AcceptanceControlsScript = load_file(str(data[KEY_CONTROLS]))
	if script.error != "":
		return "%s: %s" % [where, script.error]
	step.controls_path = data[KEY_CONTROLS]
	return ""


## The input source the runner flies `step` with: `replay`'s own inputs, or the
## step's controls through `main`'s mapping in the step's hand setting.
static func source_for(step: AcceptanceStep, replay: Replay, main: Node) -> ReplayInputSource:
	if step.controls_path == "":
		return ReplayInputSource.new(replay, step.loop_replay)
	var mapping: ThumbstickMapping = main.get("mapping") as ThumbstickMapping
	var script: AcceptanceControlsScript = load_file(step.controls_path)
	return ControlsInputSource.new(replay, script.frames, mapping, step.left_handed)
