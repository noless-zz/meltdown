class_name DestroyedSequence
extends RefCounted

## What the pilot sees once the local ship's hull reaches zero (#616, RUN-7,
## CMB-2): the view fades dark over `fade_seconds`, `SHIP DESTROYED` shows,
## and after `hold_seconds` a fresh press of the restart button asks for the
## level to start again. After the restart the view fades back in.
##
##     ALIVE -> DESTROYED -> CAN_RESTART -> RESTARTED -> ALIVE
##
## It only reads a hull value it is handed and only answers what to show and
## when to restart; the restart itself goes through the main scene's level
## loading (MP-2). Nothing moves the camera; the fade is the only change to
## the view (CMF-8). The times come from `DEFAULT_FILE` (ARC-4):
##
##     {"fade_seconds": 1.0, "hold_seconds": 3.0}

enum State { ALIVE, DESTROYED, CAN_RESTART, RESTARTED }

const DEFAULT_FILE: String = "res://xr/destroyed_screen.json"
## Each key with the range it must lie in, inclusive.
const RANGES: Dictionary[String, Vector2] = {
	"fade_seconds": Vector2(0.0, 10.0),
	"hold_seconds": Vector2(0.0, 30.0),
}
## Used when the file is missing or rejected.
const FALLBACK: Dictionary = {"fade_seconds": 1.0, "hold_seconds": 3.0}

var state: State = State.ALIVE
var fade_seconds: float = FALLBACK["fade_seconds"]
var hold_seconds: float = FALLBACK["hold_seconds"]
## Seconds since the ship was destroyed, or since the restart.
var elapsed: float = 0.0
## Seconds since the ship was destroyed, kept through CAN_RESTART: the fade out
## is timed by this, not `elapsed`, which restarts when the prompt shows.
## Timing it by `elapsed` dropped the view to clear at the prompt and faded it
## out a second time, the level flashing back behind the end screen (#1228).
var dark_seconds: float = 0.0

## Whether the restart button was up at some frame since restarting became
## possible, so a button already held (A is also the afterburner) does not
## restart at once.
var _released: bool = false


func _init(values: Dictionary = FALLBACK) -> void:
	fade_seconds = float(values.get("fade_seconds", FALLBACK["fade_seconds"]))
	hold_seconds = float(values.get("hold_seconds", FALLBACK["hold_seconds"]))


## Parses the text of a destroyed-screen file. Returns the values as floats,
## or a dictionary holding only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not RANGES.has(key):
			return {"error": "unknown key \"%s\"" % str(key)}
	var values: Dictionary = {}
	for key: String in RANGES:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		var range_: Vector2 = RANGES[key]
		if float(value) < range_.x or float(value) > range_.y:
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, range_.x, range_.y]}
		values[key] = float(value)
	return values


## The sequence with the times in the file at `path`. A missing or rejected
## file gives `FALLBACK` and pushes a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> DestroyedSequence:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		push_warning("The destroyed screen uses built-in times; %s: %s" % [path, values["error"]])
		values = FALLBACK
	return DestroyedSequence.new(values)


## Runs the sequence by `delta` seconds with the local ship's `hull` this frame
## and whether the restart button is held. Returns true on the one frame the
## level should restart; the caller restarts it and the fade-in begins.
func update(hull: float, delta: float, restart_held: bool) -> bool:
	var step: float = maxf(delta, 0.0)
	match state:
		State.ALIVE:
			if hull <= 0.0:
				_enter(State.DESTROYED)
		State.DESTROYED:
			elapsed += step
			dark_seconds += step
			if elapsed >= hold_seconds:
				_enter(State.CAN_RESTART)
		State.CAN_RESTART:
			elapsed += step
			dark_seconds += step
			if not restart_held:
				_released = true
			elif _released:
				_enter(State.RESTARTED)
				return true
		State.RESTARTED:
			elapsed += step
			if elapsed >= fade_seconds:
				_enter(State.ALIVE)
	return false


## The fade's opacity this frame, 0..1: rising to 1 over `fade_seconds` once
## destroyed, held there until the restart, then falling back to 0. It never
## goes down between the destruction and the press (CMF-8).
func fade_alpha() -> float:
	match state:
		State.DESTROYED, State.CAN_RESTART:
			return 1.0 if fade_seconds <= 0.0 else clampf(dark_seconds / fade_seconds, 0.0, 1.0)
		State.RESTARTED:
			return 0.0 if fade_seconds <= 0.0 else clampf(1.0 - elapsed / fade_seconds, 0.0, 1.0)
	return 0.0


## Whether `SHIP DESTROYED` shows.
func line_shown() -> bool:
	return state == State.DESTROYED or state == State.CAN_RESTART


## Whether the restart prompt shows under the line.
func prompt_shown() -> bool:
	return state == State.CAN_RESTART


func _enter(next: State) -> void:
	state = next
	elapsed = 0.0
	if next == State.DESTROYED:
		dark_seconds = 0.0
	_released = false
