class_name SwivelYaw
extends RefCounted

## Swivel-chair mode (CMF-7): turning the body in a real chair turns the ship.
## Off by default and not wired yet (#722); it only answers a yaw stick value.
##
## The headset's yaw is compared with a reference heading. Inside the dead
## zone the answer is 0, so looking around the cockpit never turns the ship;
## past it the answer grows with the angle up to `max_input`. The value is
## added to the stick's yaw before `ComfortInputFilter`, so it is just more
## stick: preset 1 still turns only by snaps (CMF-3), preset 2's rate caps
## still hold, and the core sees an ordinary input on every preset (CMF-6).
## Nothing here touches the simulation (ARC-3).
##
## The reference drifts towards the body at `follow_deg_per_s`, so a player
## who settles facing a new direction stops turning without a recentre. A
## recentre puts the reference back on the head at once.
##
## Kept apart from look-aim (#678), which also reads the head direction but
## for aiming, not turning. The tuning values are guesses for a headset
## session and live in `res://xr/swivel.json` so the owner can change them.

const DEFAULT_FILE: String = "res://xr/swivel.json"

## Off unless the file says otherwise.
var enabled: bool = false
## Head yaw either side of the reference that gives nothing, degrees, 0..90.
var dead_zone_deg: float = 30.0
## Stick yaw per degree past the dead zone, 0..1.
var gain_per_deg: float = 0.03
## Largest stick yaw this may give, 0..1.
var max_input: float = 1.0
## How fast the reference follows the body, degrees per second, 0..180.
## 0 never follows.
var follow_deg_per_s: float = 5.0

## Every number key of the data file, named like the field it sets. The file
## also holds the bool `enabled`.
const NUMBER_KEYS: Array[String] = [
	"dead_zone_deg", "gain_per_deg", "max_input", "follow_deg_per_s",
]

## Allowed range of each number key, inclusive: [minimum, maximum]. Keep these
## in step with the ranges written on the fields above.
const RANGES: Dictionary[String, Array] = {
	"dead_zone_deg": [0.0, 90.0],
	"gain_per_deg": [0.0, 1.0],
	"max_input": [0.0, 1.0],
	"follow_deg_per_s": [0.0, 180.0],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""
## Head yaw that counts as facing forward, radians about +Y.
var reference_rad: float = 0.0


## Parses the text of a swivel data file: one JSON object holding `enabled` as
## a bool and every key of `NUMBER_KEYS` as a number in its range, and nothing
## else. On failure the returned swivel has `error` set, naming the field, and
## default values, so it stays off.
static func parse_json(text: String) -> SwivelYaw:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or (key != "enabled" and not NUMBER_KEYS.has(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	if not data.has("enabled"):
		return _rejected("missing key \"enabled\"")
	if typeof(data["enabled"]) != TYPE_BOOL:
		return _rejected("key \"enabled\" must be true or false")
	var swivel: SwivelYaw = SwivelYaw.new()
	swivel.enabled = bool(data["enabled"])
	for key: String in NUMBER_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(value) < low or float(value) > high:
			return _rejected("key \"%s\" is %s, must be within %s..%s" % [key, value, low, high])
		swivel.set(key, float(value))
	return swivel


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> SwivelYaw:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var swivel: SwivelYaw = parse_json(FileAccess.get_file_as_string(path))
	if swivel.error != "":
		swivel.error = "%s: %s" % [path, swivel.error]
	return swivel


## Makes `head_yaw_rad` the forward heading, for the recentre event.
func recentre(head_yaw_rad: float = 0.0) -> void:
	reference_rad = head_yaw_rad


## Returns this frame's yaw stick value, -1..1, + turning the nose right like
## the stick's x. `head_yaw_rad` is the headset's yaw relative to the cockpit,
## radians about +Y (+ is turned left, as `HeadRecentre.heading` gives it).
## `delta` is the frame time in seconds, used only to move the reference.
func update(head_yaw_rad: float, delta: float) -> float:
	if not enabled:
		return 0.0
	var turned: float = wrapf(head_yaw_rad - reference_rad, -PI, PI)
	var value: float = stick_for(turned)
	var step: float = deg_to_rad(follow_deg_per_s) * maxf(delta, 0.0)
	reference_rad = wrapf(reference_rad + clampf(turned, -step, step), -PI, PI)
	return value


## The stick yaw for a head turned `turned_rad` from the reference.
func stick_for(turned_rad: float) -> float:
	var past: float = absf(rad_to_deg(turned_rad)) - dead_zone_deg
	if not enabled or past <= 0.0:
		return 0.0
	# Head turned left (+) means the nose should go left: negative stick yaw.
	return -signf(turned_rad) * minf(past * gain_per_deg, max_input)


## A copy of `input` with `stick_yaw` (-1..1, + nose right) added to its yaw,
## the result kept within the stick's full rate. Feed this to
## `ComfortInputFilter.filter` so the preset still applies.
static func added_to(input: ShipInput, stick_yaw: float) -> ShipInput:
	var full: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
	var out: ShipInput = ComfortInputFilter.copy_input(input)
	var extra: int = roundi(-stick_yaw * ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
	out.turn_q = Vector3i(out.turn_q.x, clampi(out.turn_q.y + extra, -full, full), out.turn_q.z)
	return out


static func _rejected(message: String) -> SwivelYaw:
	var swivel: SwivelYaw = SwivelYaw.new()
	swivel.error = message
	return swivel
