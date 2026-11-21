class_name AcceptancePauseCheck
extends RefCounted

## A step's solo pause (#804, PLT-7, CMF-8, ARC-2): partway through the replay
## the runner takes the headset off, holds, puts it back on and flies on.
## The pause goes through the scene's own `on_session_visible` and
## `on_session_focussed`, the calls the OpenXR focus events make, so the step
## tests the path a player's headset takes, not a stand-in.
##
## `held_while_paused` then judges what the player would see: no simulation
## tick ran while paused, the simulation's state hash and the camera's world
## pose did not change on any held frame (CMF-8), and the first frame after
## the pause flew exactly the next recorded tick, so no input was skipped.
## The step's final_hash shows the pause did not change the flight (ARC-2).
##
## In a suite: `"pause_at_tick": <n>` (a tick inside the replay) and
## `"pause_seconds": <s>` go together with the held_while_paused check. The
## hold is counted in the frames the runner feeds the scene (one tick's time
## each), so the step takes the same frames on every device.

const KEY_TICK: String = "pause_at_tick"
const KEY_SECONDS: String = "pause_seconds"
const MAX_SECONDS: float = 60.0
## Camera position (metres) and rotation axes may differ by this much: a held
## pose repeats the same numbers, so it only absorbs float noise, far below
## any drift a player could see.
const POSE_EPSILON: float = 1.0e-4

var _step: AcceptanceStep = null
var _hold_frames: int = 0
var _started: bool = false
var _resumed: bool = false
var _judged_resume: bool = false
var _held: int = 0
var _paused_tick: int = -1
var _paused_hash: int = 0
var _paused_pose: Transform3D = Transform3D.IDENTITY
var _resume_tick: int = -1
var _problem: String = ""


func _init(p_step: AcceptanceStep) -> void:
	_step = p_step
	_hold_frames = maxi(1, ceili(p_step.pause_seconds / ShipState.TICK_DT - 1.0e-6))


## The pause of `step`, or null when it lists none.
static func for_step(step: AcceptanceStep) -> AcceptancePauseCheck:
	return AcceptancePauseCheck.new(step) if step.pause_at_tick != AcceptanceStep.NO_PAUSE else null


## Frames the pause holds for.
func hold_frames() -> int:
	return _hold_frames


## Before the frame that would fly `tick`: pauses when the tick is due, and
## once the hold is over, puts the headset back on.
func before_frame(main: Node, tick: int) -> void:
	if not _started and tick >= _step.pause_at_tick:
		_started = true
		var session: LocalSession = main.get("session")
		_paused_tick = session.sim.tick
		_paused_hash = session.sim.state_hash()
		_paused_pose = world_pose(main)
		main.call("on_session_visible")
	elif _started and not _resumed and _held >= _hold_frames:
		_resumed = true
		main.call("on_session_focussed")


## After the frame: a held frame must show nothing moved; the first frame after
## the pause must fly exactly the next tick.
func after_frame(main: Node) -> void:
	if not _started or _problem != "":
		return
	var session: LocalSession = main.get("session")
	if not _resumed:
		_held += 1
		_problem = _held_problem(session, world_pose(main))
	elif not _judged_resume:
		_judged_resume = true
		_resume_tick = session.sim.tick
		if session.sim.tick != _paused_tick + 1 or session.ticks_last_advance != 1:
			_problem = "the frame after the pause flew %d tick(s) to tick %d, not the next tick %d" % [
				session.ticks_last_advance, session.sim.tick, _paused_tick + 1]
		elif session.replay.frames.size() != session.sim.tick:
			_problem = "the session recorded %d inputs by tick %d: an input was skipped" % [
				session.replay.frames.size(), session.sim.tick]


func _held_problem(session: LocalSession, pose: Transform3D) -> String:
	var where: String = "held frame %d (paused at tick %d)" % [_held, _paused_tick]
	if session.sim.tick != _paused_tick:
		return "%s: the simulation advanced to tick %d" % [where, session.sim.tick]
	if session.sim.state_hash() != _paused_hash:
		return "%s: the state hash changed" % where
	if pose.origin.distance_to(_paused_pose.origin) > POSE_EPSILON \
			or not _bases_match(pose.basis, _paused_pose.basis):
		return "%s: the camera moved from %s to %s" % [where, _paused_pose, pose]
	return ""


static func _bases_match(a: Basis, b: Basis) -> bool:
	for axis: int in 3:
		if a[axis].distance_to(b[axis]) > POSE_EPSILON:
			return false
	return true


## [result, message] for held_while_paused, adding the numbers to `measurements`.
func judge(measurements: Dictionary) -> Array:
	measurements["pause_tick"] = _paused_tick
	measurements["paused_frames"] = _held
	measurements["resume_tick"] = _resume_tick
	if not _started:
		return [AcceptanceReport.RESULT_FAIL, "the replay never reached tick %d to pause" % _step.pause_at_tick]
	if _problem != "":
		return [AcceptanceReport.RESULT_FAIL, _problem]
	if not _judged_resume:
		return [AcceptanceReport.RESULT_FAIL, "the replay ended before the pause was lifted"]
	return [AcceptanceReport.RESULT_PASS, "held %d frames at tick %d, resumed on tick %d" % [
		_held, _paused_tick, _resume_tick]]


## The camera's world pose, composed up its parents by hand so it also works
## outside a scene tree, where the tests fly the main scene.
static func world_pose(main: Node) -> Transform3D:
	var node: Node3D = main.get_node_or_null("XRRig/Camera") as Node3D
	if node == null:
		return Transform3D.IDENTITY
	var pose: Transform3D = node.transform
	var parent: Node3D = node.get_parent() as Node3D
	while parent != null:
		pose = parent.transform * pose
		parent = parent.get_parent() as Node3D
	return pose


## Reads `pause_at_tick` and `pause_seconds` from a step's JSON into `step`;
## "" or the problem, with the field named. The two and the check come
## together, and the tick must lie inside the replay: a pause after the last
## tick would never happen and the step would pass without it.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wanted: bool = step.has_check(AcceptanceStep.CHECK_HELD_WHILE_PAUSED)
	var has_tick: bool = data.has(KEY_TICK)
	var has_seconds: bool = data.has(KEY_SECONDS)
	if not has_tick and not has_seconds:
		return "%s.%s: needed by the held_while_paused check" % [field, KEY_TICK] if wanted else ""
	for key: String in [KEY_TICK, KEY_SECONDS]:
		if not data.has(key):
			return "%s.%s: needed with %s" % [field, key, KEY_SECONDS if key == KEY_TICK else KEY_TICK]
	if not wanted:
		return "%s.%s: only used by the held_while_paused check, which the step does not list" % [field, KEY_TICK]
	if step.replay_path == "":
		return "%s.%s: only used with a replay, which the step does not list" % [field, KEY_TICK]
	if not AcceptanceStepParser.is_whole(data[KEY_TICK]) or float(data[KEY_TICK]) < 0.0:
		return "%s.%s: must be a whole number from 0" % [field, KEY_TICK]
	var seconds: Variant = data[KEY_SECONDS]
	if (typeof(seconds) != TYPE_FLOAT and typeof(seconds) != TYPE_INT) or not is_finite(float(seconds)) \
			or float(seconds) <= 0.0 or float(seconds) > MAX_SECONDS:
		return "%s.%s: must be a number above 0 and at most %s" % [field, KEY_SECONDS, MAX_SECONDS]
	var tick: int = int(data[KEY_TICK])
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return "%s.%s: cannot read the replay to check the tick: %s" % [field, KEY_TICK, replay.error]
	if tick >= replay.frames.size():
		return "%s.%s: tick %d is past the replay, which flies ticks 0..%d" % [field, KEY_TICK, tick,
			replay.frames.size() - 1]
	step.pause_at_tick = tick
	step.pause_seconds = float(seconds)
	return ""
