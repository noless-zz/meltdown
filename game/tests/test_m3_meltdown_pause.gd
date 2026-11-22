extends RefCounted

## The m3 suite's `meltdown_pause` step (#886, PLT-7, CMF-8, RUN-5, ARC-2): the
## `bot_generated_escape` flight with the headset taken off for five seconds a
## few seconds after the reactor dies. The meltdown countdown must hold with
## everything else, and the flight must end on `bot_generated_escape`'s hash.

const SeedPick := preload("res://tests/m3_seed_pick.gd")
const M3Run := preload("res://tests/m3_suite_run.gd")
const STEP_ID: String = "meltdown_pause"
const ESCAPE_ID: String = "bot_generated_escape"
## The tick the reactor dies on in the seed 43 replay; the pause comes three
## seconds later.
const DEATH_TICK: int = 4162
const PAUSE_TICK: int = 4342


func test_the_step_flies_the_escape_and_pauses_in_the_meltdown() -> String:
	var step: AcceptanceStep = SeedPick.find_step(STEP_ID)
	var escape: AcceptanceStep = SeedPick.find_step(ESCAPE_ID)
	if step == null or escape == null:
		return "m3 lacks %s or %s" % [STEP_ID, ESCAPE_ID]
	var wanted: Array[String] = [AcceptanceStep.CHECK_HELD_WHILE_PAUSED, AcceptanceStep.CHECK_FINAL_HASH,
		AcceptanceStep.CHECK_OUTCOME, AcceptanceStep.CHECK_ESCAPE_CUE]
	if step.checks != wanted:
		return "%s checks %s" % [STEP_ID, step.checks]
	if step.replay_path != escape.replay_path or step.level_seed != escape.level_seed:
		return "%s flies %s on seed %d" % [STEP_ID, step.replay_path, step.level_seed]
	# A pause must not change the flight, so the hash is the escape's own.
	if step.expected_hash != escape.expected_hash or step.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "%s expects hash %d, outcome %d" % [STEP_ID, step.expected_hash, step.expected_outcome]
	if step.pause_at_tick != PAUSE_TICK or step.pause_seconds != 5.0:
		return "pauses at %d for %s s" % [step.pause_at_tick, step.pause_seconds]
	if step.pause_at_tick - DEATH_TICK < 60 or step.pause_at_tick - DEATH_TICK > 5 * 60:
		return "the pause is %d ticks after the reactor dies" % (step.pause_at_tick - DEATH_TICK)
	return ""


## The shipped step, flown in the shared m3 run (`m3_suite_run.gd`, #1139) by
## the runner in a main scene built as on the
## headset: every check passes, five seconds of frames are held with the
## countdown showing, and the flight resumes on the next tick.
func test_the_step_passes_headless() -> String:
	var problem: String = M3Run.step_problem(STEP_ID)
	if problem == "":
		var measured: Dictionary = M3Run.step(STEP_ID)["measurements"]
		var shown: String = str(measured.get("pause_countdown", ""))
		if int(measured.get("paused_frames", 0)) != 300 or int(measured.get("pause_tick", -1)) != PAUSE_TICK \
				or int(measured.get("resume_tick", -1)) != PAUSE_TICK + 1 or not shown.contains("Meltdown 0:"):
			problem = "measured %s" % measured
	return problem


## A held frame whose countdown moved on fails, naming the frame and both texts.
func test_a_held_frame_whose_countdown_changes_fails() -> String:
	var pause: AcceptancePauseCheck = _hand_fed_pause()
	pause.hold_from(100, 7, Transform3D.IDENTITY, "Meltdown 0:57 | 0:57")
	pause.held_frame(100, 7, Transform3D.IDENTITY, "Meltdown 0:57 | 0:57")
	pause.held_frame(100, 7, Transform3D.IDENTITY, "Meltdown 0:56 | 0:57")
	pause.held_frame(100, 7, Transform3D.IDENTITY, "Meltdown 0:55 | 0:55")
	var result: Array = pause.judge({})
	var want: String = "held frame 2 (paused at tick 100): the meltdown countdown changed from " \
		+ "'Meltdown 0:57 | 0:57' to 'Meltdown 0:56 | 0:57'"
	if result[0] != AcceptanceReport.RESULT_FAIL or str(result[1]) != want:
		return "gave %s" % [result]
	return ""


## The same frames with the countdown held are not faulted; with no meltdown
## the countdown is "" throughout, as in m1's plain flight.
func test_held_frames_with_a_steady_countdown_are_not_faulted() -> String:
	for text: String in ["Meltdown 0:57 | 0:57", ""]:
		var pause: AcceptancePauseCheck = _hand_fed_pause()
		pause.hold_from(100, 7, Transform3D.IDENTITY, text)
		for i: int in 3:
			pause.held_frame(100, 7, Transform3D.IDENTITY, text)
		var result: Array = pause.judge({})
		# Never resumed here, so the hand-fed hold ends with that message only.
		if str(result[1]) != "the replay ended before the pause was lifted":
			return "'%s' gave %s" % [text, result]
	return ""


## Outside a meltdown the scene shows no countdown, so plain-flight pauses
## (m1 `focus_pause`) compare "" with "".
func test_no_countdown_reads_empty_outside_a_meltdown() -> String:
	var main: Node = _main()
	var text: String = AcceptancePauseCheck.countdown_text(main)
	main.free()
	return "" if text == "" else "a fresh scene shows countdown '%s'" % text


static func _hand_fed_pause() -> AcceptancePauseCheck:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.pause_at_tick = 100
	step.pause_seconds = 1.0
	return AcceptancePauseCheck.new(step)


static func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main
