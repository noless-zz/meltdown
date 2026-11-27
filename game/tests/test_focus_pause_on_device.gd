extends RefCounted

## The m1 `focus_pause` step as the headset flies it (#1439, DEV-6, CMF-8,
## PLT-7). On the Quest the step hung: the headset never really loses focus, so
## no OpenXR event ends the pause; the step's own simulated pause has to. The
## tracked head moves the camera on every frame there, which the old check read
## as the view moving, and a faulted held frame stopped the hold counting, so
## the simulated focus never came back and the suite waited 15 minutes.

const REPLAY_PATH: String = "res://acceptance/replays/basic_flight.replay"
const PAUSE_TICK: int = 300
## Far more frames than the flight and its one-second hold take.
const FRAME_LIMIT: int = 3000
## How far the head wanders, metres and radians: a seated player's sway.
const HEAD_SWAY: float = 0.02


## The head moves on every frame and no focus event arrives from the runtime:
## the pause still ends after its frames, and the flight passes.
func test_a_moving_head_with_no_focus_event_still_resumes_and_passes() -> String:
	var flown: Dictionary = _fly(false)
	if not flown["resumed"]:
		return "the pause never ended (%d frames flown)" % flown["frames"]
	if flown["frames"] >= FRAME_LIMIT:
		return "the flight did not finish in %d frames" % FRAME_LIMIT
	var result: Array = flown["result"]
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "a held flight with a moving head failed: %s" % result[1]
	if int(flown["measured"]["paused_frames"]) != 60:
		return "held %s frames, wanted 60" % flown["measured"]["paused_frames"]
	if flown["hash"] != Replay.load_file(REPLAY_PATH).expected_hash:
		return "the flight ended on hash %d, not the replay's" % flown["hash"]
	return ""


## A pause that does not hold faults on its first held frame, yet the hold
## still ends after its frames and the step finishes with the fault named.
func test_a_faulted_hold_still_ends_after_its_frames() -> String:
	var flown: Dictionary = _fly(true)
	if not flown["resumed"]:
		return "a faulted hold never ended (%d frames flown)" % flown["frames"]
	if flown["frames"] >= FRAME_LIMIT:
		return "the flight did not finish in %d frames" % FRAME_LIMIT
	var result: Array = flown["result"]
	if result[0] != AcceptanceReport.RESULT_FAIL or str(result[1]).find("held frame 1") < 0:
		return "gave %s" % [result]
	return ""


## Hand-fed: the hold counts every frame, faulted or not, and the first fault stays.
func test_held_frames_count_after_a_fault() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.pause_at_tick = 100
	step.pause_seconds = 0.05
	var pause: AcceptancePauseCheck = AcceptancePauseCheck.new(step)
	pause.hold_from(100, 7, Transform3D.IDENTITY, "")
	pause.held_frame(101, 7, Transform3D.IDENTITY, "")
	pause.held_frame(102, 8, Transform3D.IDENTITY, "")
	pause.held_frame(100, 7, Transform3D.IDENTITY, "")
	var measured: Dictionary = {}
	var result: Array = pause.judge(measured)
	if int(measured["paused_frames"]) != 3:
		return "counted %s held frames, wanted 3" % measured["paused_frames"]
	if str(result[1]) != "held frame 1 (paused at tick 100): the simulation advanced to tick 101":
		return "gave %s" % [result]
	return ""


## The rig's pose leaves out the tracked head inside it.
func test_the_rig_pose_leaves_out_the_head() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var camera: Node3D = main.get_node("XRRig/Camera") as Node3D
	var before: Transform3D = AcceptancePauseCheck.rig_pose(main)
	camera.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 0.05, -0.02))
	var after: Transform3D = AcceptancePauseCheck.rig_pose(main)
	var head_moved: bool = not AcceptancePauseCheck.world_pose(main).is_equal_approx(before)
	main.free()
	if not after.is_equal_approx(before):
		return "the rig pose followed the head: %s to %s" % [before, after]
	return "" if head_moved else "the camera's pose did not change, so the test shows nothing"


## Flies the basic flight frame by frame in the main scene as the runner does,
## pausing at PAUSE_TICK for one second, with the head swaying every frame.
## `broken` clears the session's pause every frame, as a pause that never took would.
func _fly(broken: bool) -> Dictionary:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.pause_at_tick = PAUSE_TICK
	step.pause_seconds = 1.0
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var camera: Node3D = main.get_node("XRRig/Camera") as Node3D
	var source: ReplayInputSource = ReplayInputSource.new(Replay.load_file(REPLAY_PATH))
	main.set("session", source.new_session())
	var pause: AcceptancePauseCheck = AcceptancePauseCheck.new(step)
	var frames: int = 0
	while (main.get("session") as LocalSession).sim.tick < source.tick_count() and frames < FRAME_LIMIT:
		var sway: float = sin(float(frames) * 0.37) * HEAD_SWAY
		camera.transform = Transform3D(Basis(Vector3.UP, sway), Vector3(sway, 1.2 + sway, -sway))
		pause.before_frame(main, (main.get("session") as LocalSession).sim.tick)
		if broken:
			(main.get("session") as LocalSession).paused = false
		main.call("advance_frame", ShipState.TICK_DT)
		pause.after_frame(main)
		frames += 1
	var measured: Dictionary = {}
	var flown: Dictionary = {"result": pause.judge(measured), "measured": measured, "frames": frames,
		"resumed": pause.resumed(), "hash": (main.get("session") as LocalSession).sim.state_hash()}
	main.free()
	return flown
