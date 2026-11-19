class_name ReactorState
extends RefCounted

## A level's reactor in the simulation (RUN-2): a sphere the ships' shots wear
## down. When its hull reaches zero the meltdown starts, and from the next tick
## `meltdown_ticks_left` counts down to zero at 60 ticks a second (ARC-1).
##
## Read from one JSON object, in the level file and in the replay's reactor
## line alike, so there is one parser:
##
##     {"position": [0, -39, -114], "radius": 2.5, "hull": 400, "meltdown_seconds": 90}
##
## Position and radius are metres, read in whole millimetres like robot spawns,
## so the reactor is the same on every device (ARC-2). Hull and meltdown time
## are data, not code (ARC-4).
##
## The reactor also carries the radius of the level's exit (RUN-3): the exit only
## matters once the reactor is dead, and so the replay's reactor line holds it
## too. A level file sets it with its top-level `exit_radius` key (`LevelDef`); the
## optional `exit_radius` key here exists for the replay line, and is missing in
## replays written before #311, which then get `LevelDefaults.FALLBACK_EXIT_RADIUS_MM`.
##
## The countdown may instead scale with the way out (RUN-5): with all four
## `SCALING_KEYS` set, it starts at clamp(base + per_metre * metres, min, max)
## seconds, where metres is the longest live ship's `EscapePath` on the tick the
## reactor dies. `meltdown_seconds` is still required but then unused. Without the
## keys nothing changes, so older levels and replays keep their hashes.

const KEYS: Array[String] = ["position", "radius", "hull", "meltdown_seconds"]
## Keys the JSON may leave out.
const OPTIONAL_KEYS: Array[String] = ["exit_radius", "meltdown_base_seconds",
	"meltdown_seconds_per_metre", "meltdown_min_seconds", "meltdown_max_seconds"]
## Optional keys that scale the countdown with the escape path; all or none.
const SCALING_KEYS: Array[String] = ["meltdown_base_seconds", "meltdown_seconds_per_metre",
	"meltdown_min_seconds", "meltdown_max_seconds"]
const TICKS_PER_SECOND: int = 60
## Large enough for any room; a typo of a few orders of magnitude is caught.
const MAX_RADIUS_M: float = 100.0

var position_mm: Vector3i = Vector3i.ZERO
var radius_mm: int = 1000
## Hull the reactor starts with.
var max_hull: float = 1.0
var meltdown_seconds: float = 1.0
## True when the level set `SCALING_KEYS`; the four values below are then used.
var scales_with_path: bool = false
var meltdown_base_seconds: float = 0.0
var meltdown_seconds_per_metre: float = 0.0
var meltdown_min_seconds: float = 1.0
var meltdown_max_seconds: float = 1.0
## Current hull; part of the hash.
var hull: float = 1.0
## Set on the tick the hull reaches zero; part of the hash.
var destroyed: bool = false
## Ticks until the meltdown ends; 0 until destroyed. Part of the hash.
var meltdown_ticks_left: int = 0
## Radius of the exit sphere at the start (RUN-3). Fixed for the run, so not
## part of the hash.
var exit_radius_mm: int = LevelDefaults.FALLBACK_EXIT_RADIUS_MM
## Set by `parse` when the data was rejected; empty otherwise.
var error: String = ""


## Reads a reactor from `value`, a parsed JSON object. On failure `error` is set.
static func parse(value: Variant) -> ReactorState:
	var reactor: ReactorState = ReactorState.new()
	reactor.error = reactor._read(value)
	if reactor.error != "":
		reactor.error = "reactor: " + reactor.error
	return reactor


## Reads a reactor from JSON text, as in the replay's reactor line.
static func parse_json(text: String) -> ReactorState:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		var failed: ReactorState = ReactorState.new()
		failed.error = "reactor: invalid JSON: %s" % json.get_error_message()
		return failed
	return parse(json.data)


## The same reactor as it was before the first tick: full hull, not destroyed.
## A replay hands this to every run, so running it twice starts it the same.
func fresh_copy() -> ReactorState:
	var copy: ReactorState = ReactorState.new()
	copy.position_mm = position_mm
	copy.radius_mm = radius_mm
	copy.max_hull = max_hull
	copy.meltdown_seconds = meltdown_seconds
	copy.scales_with_path = scales_with_path
	copy.meltdown_base_seconds = meltdown_base_seconds
	copy.meltdown_seconds_per_metre = meltdown_seconds_per_metre
	copy.meltdown_min_seconds = meltdown_min_seconds
	copy.meltdown_max_seconds = meltdown_max_seconds
	copy.exit_radius_mm = exit_radius_mm
	copy.hull = max_hull
	return copy


## The JSON object `parse` reads back to this reactor, at full precision.
func to_json() -> String:
	var scale: float = float(RobotSpawn.SCALE)
	var position: Array[float] = [position_mm.x / scale, position_mm.y / scale,
		position_mm.z / scale]
	var data: Dictionary = {"position": position, "radius": radius_mm / scale,
		"hull": max_hull, "meltdown_seconds": meltdown_seconds,
		"exit_radius": exit_radius_mm / scale}
	# Only when set, so a reactor line without scaling reads as it always did.
	if scales_with_path:
		data["meltdown_base_seconds"] = meltdown_base_seconds
		data["meltdown_seconds_per_metre"] = meltdown_seconds_per_metre
		data["meltdown_min_seconds"] = meltdown_min_seconds
		data["meltdown_max_seconds"] = meltdown_max_seconds
	return JSON.stringify(data, "", false, true)


func position() -> Vector3:
	return Vector3(position_mm) / float(RobotSpawn.SCALE)


func radius() -> float:
	return radius_mm / float(RobotSpawn.SCALE)


func exit_radius() -> float:
	return exit_radius_mm / float(RobotSpawn.SCALE)


## Reads `value`, metres, as a radius in whole millimetres into `read`.
## Returns "" or the problem, naming `key`.
static func read_radius_mm(value: Variant, key: String, read: Array[int]) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT \
			or not is_finite(float(value)) or float(value) <= 0.0:
		return "%s must be a number above zero" % key
	if float(value) > MAX_RADIUS_M:
		return "%s must be at most %s m" % [key, MAX_RADIUS_M]
	var mm: int = roundi(float(value) * RobotSpawn.SCALE)
	if mm < 1:
		return "%s must be at least 1 mm" % key
	read.append(mm)
	return ""


## Ticks the countdown starts from when the reactor dies.
func meltdown_ticks() -> int:
	return roundi(meltdown_seconds * TICKS_PER_SECOND)


## Ticks the countdown starts from when the reactor dies with the longest
## escape path `path_mm` millimetres long. Without scaling, `meltdown_ticks`.
func meltdown_ticks_for_path(path_mm: int) -> int:
	if not scales_with_path:
		return meltdown_ticks()
	var seconds: float = meltdown_base_seconds \
		+ meltdown_seconds_per_metre * path_mm / float(RobotSpawn.SCALE)
	seconds = clampf(seconds, meltdown_min_seconds, meltdown_max_seconds)
	return roundi(seconds * TICKS_PER_SECOND)


## Where the segment `from`..`to` first enters the reactor sphere, as a
## fraction 0..1, or -1.0 if it never does or the reactor is already destroyed.
func segment_entry(from: Vector3, to: Vector3) -> float:
	if destroyed:
		return -1.0
	return Projectile.segment_entry(from, to, position(), radius())


## Lowers the hull by `amount`. Returns true only on the hit that destroys it,
## which also arms the countdown; `count_down` starts it on the next tick.
func apply_damage(amount: float) -> bool:
	if destroyed or amount <= 0.0:
		return false
	hull = maxf(hull - amount, 0.0)
	if hull > 0.0:
		return false
	destroyed = true
	meltdown_ticks_left = meltdown_ticks()
	return true


## One tick of the meltdown countdown. `Sim.step` calls it before any shot
## moves, so the tick the reactor dies on keeps the full count.
func count_down() -> void:
	if destroyed and meltdown_ticks_left > 0:
		meltdown_ticks_left -= 1


func state_hash() -> int:
	return hash(["hull", hull, "destroyed", destroyed, "ticks_left", meltdown_ticks_left])


func _read(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be a JSON object"
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(key) and not OPTIONAL_KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in KEYS:
		if not data.has(key):
			return "missing key \"%s\"" % key
	var read: Array[Vector3i] = []
	var problem: String = RobotSpawn.read_mm(data["position"], "position", read)
	if problem != "":
		return problem
	position_mm = read[0]
	var numbers: Dictionary = {}
	for key: String in ["radius", "hull", "meltdown_seconds"]:
		var number: Variant = data[key]
		if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT \
				or not is_finite(float(number)) or float(number) <= 0.0:
			return "%s must be a number above zero" % key
		numbers[key] = float(number)
	if numbers["radius"] > MAX_RADIUS_M:
		return "radius must be at most %s m" % MAX_RADIUS_M
	radius_mm = roundi(numbers["radius"] * RobotSpawn.SCALE)
	if radius_mm < 1:
		return "radius must be at least 1 mm"
	max_hull = numbers["hull"]
	hull = max_hull
	meltdown_seconds = numbers["meltdown_seconds"]
	if meltdown_ticks() < 1:
		return "meltdown_seconds must be at least one tick"
	if data.has("exit_radius"):
		var read_exit: Array[int] = []
		problem = read_radius_mm(data["exit_radius"], "exit_radius", read_exit)
		if problem != "":
			return problem
		exit_radius_mm = read_exit[0]
	return _read_scaling(data)


func _read_scaling(data: Dictionary) -> String:
	var present: int = 0
	for key: String in SCALING_KEYS:
		if data.has(key):
			present += 1
	if present == 0:
		return ""
	if present < SCALING_KEYS.size():
		return "%s must be given together" % ", ".join(SCALING_KEYS)
	var numbers: Dictionary = {}
	for key: String in SCALING_KEYS:
		var number: Variant = data[key]
		if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT \
				or not is_finite(float(number)) or float(number) < 0.0:
			return "%s must be a number of at least zero" % key
		numbers[key] = float(number)
	meltdown_base_seconds = numbers["meltdown_base_seconds"]
	meltdown_seconds_per_metre = numbers["meltdown_seconds_per_metre"]
	meltdown_min_seconds = numbers["meltdown_min_seconds"]
	meltdown_max_seconds = numbers["meltdown_max_seconds"]
	if roundi(meltdown_min_seconds * TICKS_PER_SECOND) < 1:
		return "meltdown_min_seconds must be at least one tick"
	if meltdown_max_seconds < meltdown_min_seconds:
		return "meltdown_max_seconds must be at least meltdown_min_seconds"
	scales_with_path = true
	return ""
