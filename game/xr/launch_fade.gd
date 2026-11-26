class_name LaunchFade
extends RefCounted

## The launch from the home base and the arrival back at it, as the pilot sees
## them (#1396, CRW-2, CMF-1, CMF-3, CMF-8): choosing Launch first raises the
## cradle ship's engine glow over `glow_seconds`, then fades the view to a
## plain colour over `fade_out_seconds`; on the frame it is fully dark the
## launch is due, the level loads behind the colour and the view fades in
## over `fade_in_seconds`. Arriving at the base fades in the same way.
##
##     IDLE -> GLOW -> FADE_OUT -> (launch due) FADE_IN -> IDLE
##     IDLE -> FADE_IN -> IDLE   (arriving, or a resume)
##
## It only answers an opacity, a glow and when the launch is due; the launch
## itself is the hub's unchanged launch (ARC-3, MP-2). Nothing here moves the
## camera: the fade is the only change to the view (CMF-8). The times and the
## colour come from `DEFAULT_FILE` (ARC-4):
##
##     {"glow_seconds": 0.6, "fade_out_seconds": 0.5, "fade_in_seconds": 0.5,
##      "color": [0.0, 0.0, 0.0]}

enum State { IDLE, GLOW, FADE_OUT, FADE_IN }

const DEFAULT_FILE: String = "res://xr/launch_fade.json"
## Each time with the range it must lie in, inclusive. A fade is never shorter
## than 0.2 s, so it cannot become a cut.
const RANGES: Dictionary[String, Vector2] = {
	"glow_seconds": Vector2(0.0, 3.0),
	"fade_out_seconds": Vector2(0.2, 3.0),
	"fade_in_seconds": Vector2(0.2, 3.0),
}
## The brightest a colour channel may be: the fade is a dim plain colour,
## never a flash.
const MAX_CHANNEL: float = 0.3
## Used when the file is missing or rejected.
const FALLBACK: Dictionary = {"glow_seconds": 0.6, "fade_out_seconds": 0.5, "fade_in_seconds": 0.5,
	"color": Color(0.0, 0.0, 0.0)}

var state: State = State.IDLE
var glow_seconds: float = FALLBACK["glow_seconds"]
var fade_out_seconds: float = FALLBACK["fade_out_seconds"]
var fade_in_seconds: float = FALLBACK["fade_in_seconds"]
var color: Color = FALLBACK["color"]
## Seconds since the current state began.
var elapsed: float = 0.0


func _init(values: Dictionary = FALLBACK) -> void:
	glow_seconds = float(values.get("glow_seconds", FALLBACK["glow_seconds"]))
	fade_out_seconds = float(values.get("fade_out_seconds", FALLBACK["fade_out_seconds"]))
	fade_in_seconds = float(values.get("fade_in_seconds", FALLBACK["fade_in_seconds"]))
	color = values.get("color", FALLBACK["color"])


## Parses the text of a launch fade file. Returns the times as floats and the
## colour as a Color, or a dictionary holding only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (RANGES.has(key) or key == "color"):
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
	var parsed_color: Variant = _color(data.get("color"))
	if parsed_color is String:
		return {"error": parsed_color}
	values["color"] = parsed_color
	return values


## The file at `path` as a fade. A missing or rejected file gives `FALLBACK`
## and pushes a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> LaunchFade:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		push_warning("The launch fade uses built-in times; %s: %s" % [path, values["error"]])
		values = FALLBACK
	return LaunchFade.new(values)


## Starts the launch: the glow, then the fade out. False, changing nothing,
## while a launch is already under way.
func start_launch() -> bool:
	if is_launching():
		return false
	_enter(State.GLOW)
	return true


## Starts a fade in from fully dark: arriving at the base, or a resume.
func start_fade_in() -> void:
	_enter(State.FADE_IN)


## Runs the fade by `delta` seconds. Returns true on the one call on which the
## fade out reaches full colour: the launch is due, and the fade in begins.
func advance(delta: float) -> bool:
	elapsed += maxf(delta, 0.0)
	match state:
		State.GLOW:
			if elapsed >= glow_seconds:
				_enter(State.FADE_OUT, elapsed - glow_seconds)
				return advance(0.0)
		State.FADE_OUT:
			if elapsed >= fade_out_seconds:
				_enter(State.FADE_IN)
				return true
		State.FADE_IN:
			if elapsed >= fade_in_seconds:
				_enter(State.IDLE)
	return false


## True from the launch press until the launch is due.
func is_launching() -> bool:
	return state == State.GLOW or state == State.FADE_OUT


## The colour's opacity, 0..1: rising during the fade out, full when the
## launch is due, falling during the fade in. It never goes up during a fade
## in nor down during a fade out (CMF-8).
func alpha() -> float:
	match state:
		State.FADE_OUT:
			return clampf(elapsed / fade_out_seconds, 0.0, 1.0)
		State.FADE_IN:
			return clampf(1.0 - elapsed / fade_in_seconds, 0.0, 1.0)
	return 0.0


## How far the engine glow has risen, 0 (idle) to 1 (full): over the glow,
## then held full through the fade out.
func glow() -> float:
	match state:
		State.GLOW:
			return 1.0 if glow_seconds <= 0.0 else clampf(elapsed / glow_seconds, 0.0, 1.0)
		State.FADE_OUT:
			return 1.0
	return 0.0


func _enter(next: State, carried: float = 0.0) -> void:
	state = next
	elapsed = carried


static func _color(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 3:
		return "\"color\" must be [r, g, b]"
	var channels: Array[float] = []
	for value: Variant in raw:
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return "\"color\" must hold numbers"
		if float(value) < 0.0 or float(value) > MAX_CHANNEL:
			return "\"color\" channels must be within 0..%s, a dim colour, never a flash" % MAX_CHANNEL
		channels.append(float(value))
	return Color(channels[0], channels[1], channels[2])
