extends RefCounted

## The `eyes_same_frame` check (#1513, CMF-8, PRF-1, GFX-7, DEV-6, decision
## record 0005), lane-a's file under `acceptance/checks/`. In `suites/m1.json`
## it has two steps, one in the test tunnel and one at the base:
##
##     {"id": "eyes_same_frame", "checks": ["eyes_same_frame"]}
##     {"id": "eyes_same_frame_base", "run": 12345,
##      "replay": "res://acceptance/replays/craft_and_fit_idle.replay", "checks": ["eyes_same_frame"]}
##
## Once the step is otherwise done, its frame work samples every drawn frame for
## `seconds` (`AcceptanceEyeFrames`) and judges both eyes' projections and poses
## (`AcceptanceEyePair`), with the limits in `eye_frames.json`. Without a stereo
## runtime it reports skipped, not passed. Only the runtime is read: nothing in
## the scene or the simulation changes (ARC-3).

const CHECK: String = "eyes_same_frame"
const DATA_FILE: String = "res://acceptance/checks/eye_frames.json"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func frame_work() -> Dictionary[String, Callable]:
	return {CHECK: _start}


## The sampler for the limits in `path`, reading `read`, or a String naming what is wrong with the file.
static func sampler(path: String, read: Callable) -> Variant:
	var section: Dictionary = AcceptanceEyePair.read_section(path, CHECK)
	if section.has("error"):
		return str(section["error"])
	var limits: Dictionary = AcceptanceEyePair.parse_limits(section)
	if limits.has("error"):
		return "%s: %s.%s" % [path, CHECK, limits["error"]]
	var seconds: Variant = section.get("seconds")
	if (typeof(seconds) != TYPE_FLOAT and typeof(seconds) != TYPE_INT) or float(seconds) < 1.0 or float(seconds) > 60.0:
		return "%s: %s.seconds must be a number within 1..60" % [path, CHECK]
	var frames: AcceptanceEyeFrames = AcceptanceEyeFrames.new()
	frames.limits = limits
	frames.seconds = float(seconds)
	frames.read = read
	return frames


static func _start(_step: AcceptanceStep, runner: AcceptanceRunner, frames: AcceptanceFrameHook) -> void:
	var made: Variant = sampler(DATA_FILE, func() -> Variant: return AcceptanceEyePair.read_interface(runner.xr_interface))
	frames.results[CHECK] = made
	if made is AcceptanceEyeFrames:
		(made as AcceptanceEyeFrames).start(frames)


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var frames: AcceptanceFrameHook = runner.frame_hook() if runner != null else null
	var made: Variant = frames.results.get(CHECK) if frames != null else null
	if made is String:
		return [AcceptanceReport.RESULT_FAIL, made]
	if not made is AcceptanceEyeFrames:
		return [AcceptanceReport.RESULT_FAIL, "no frame was sampled: the check's frame work did not run"]
	return (made as AcceptanceEyeFrames).judge(step.required, measurements)
