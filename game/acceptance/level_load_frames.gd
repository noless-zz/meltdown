class_name LevelLoadFrames
extends RefCounted

## The m6 `level_load` step's frame work (#1480, PRF-7, ARC-1): loads each level `LevelLoadPlan`
## lists into the scene, one at a time, waits for the frame after it to be drawn and takes it out
## again, so every load's `total_s` includes its first drawn frame (`LevelLoadTiming`). The judge
## in `checks/level_load_check.gd` reads `timings` once `done`.
##
## Each load is also built once without the clock and its state hash compared, so the measurement
## provably leaves the simulation as it was (ARC-1, ARC-2). That second build is not timed.

var budget_seconds: float = 0.0
## The finished loads, each with its `label`, phases, `total_s` and `drawn`.
var timings: Array[Dictionary] = []
## Why the loads stopped, naming the load, or "".
var error: String = ""
var done: bool = false

var _loads: Array[Dictionary] = []
var _parent: Node = null
var _frames: AcceptanceFrameHook = null
var _index: int = 0
var _current: Dictionary = {}


## Starts the plan's loads under `parent` (the game scene), one per frame of `frames`.
static func start(parent: Node, frames: AcceptanceFrameHook) -> LevelLoadFrames:
	var plan: LevelLoadPlan = LevelLoadPlan.load_file()
	var loads: Array[Dictionary] = plan.loads(SeedLevel.read_text(RunWiring.RUN_FILE),
		ShaftOffer.build(SeedLevel.read_text(RunWiring.SHAFTS_FILE)))
	return start_loads(loads, plan.budget_seconds, plan.error, parent, frames)


## Starts `loads` (each {"label", "source", "shaft"}); `plan_error` stops them before the first.
static func start_loads(loads: Array[Dictionary], budget: float, plan_error: String, parent: Node,
		frames: AcceptanceFrameHook) -> LevelLoadFrames:
	var work: LevelLoadFrames = LevelLoadFrames.new()
	work.budget_seconds = budget
	work._loads = loads
	work._parent = parent
	work._frames = frames
	frames.on_end(func() -> void: work.cleanup())  # Also holds the work until the step ends.
	if plan_error != "":
		work.error = "%s: %s" % [LevelLoadPlan.FILE.get_file(), plan_error]
		work.done = true
		return work
	work._next()
	return work


## Takes a load still waiting for its frame out of the scene: the step ended or timed out. Lets
## go of the hook, whose results hold this work, so neither outlives the step.
func cleanup() -> void:
	_frames = null
	if not _current.is_empty():
		LevelLoadTiming.drop(_current.get("world") as Node)
		_current = {}


func _next() -> void:
	if _index >= _loads.size():
		done = true
		return
	var entry: Dictionary = _loads[_index]
	var timing: Dictionary = LevelLoadTiming.begin(entry["source"], entry["shaft"], _parent)
	if timing.has("error"):
		_stop("%s: %s" % [entry["label"], timing["error"]])
		return
	_current = timing
	_frames.next_drawn_frame(_on_frame)


func _on_frame(drawn: bool, drawn_usec: int) -> void:
	var entry: Dictionary = _loads[_index]
	var timing: Dictionary = LevelLoadTiming.finish(_current, drawn, drawn_usec)
	_current = {}
	var unmeasured: int = LevelLoadTiming.unmeasured_hash(entry["source"], entry["shaft"])
	if unmeasured != int(timing["hash"]):
		_stop("%s: state hash %d when measured, %d without" % [entry["label"], timing["hash"], unmeasured])
		return
	timing["label"] = entry["label"]
	timings.append(timing)
	_index += 1
	_next()


func _stop(why: String) -> void:
	error = why
	done = true
