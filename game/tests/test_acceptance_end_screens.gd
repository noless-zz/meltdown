extends RefCounted

## Each acceptance step starts with the scene drawn (#917, DEV-6, CMF-8): the
## destroyed screen, the escape end screen and the fade a step ended on are
## cleared before the next step's first tick, so a device run's recording and
## screenshots show each flight rather than the first end screen on black.

const M2_PATH: String = "res://acceptance/suites/m2.json"
const M3_PATH: String = "res://acceptance/suites/m3.json"
## Enough for the longest step flown here; the runner flies one tick per frame.
const FRAME_LIMIT: int = 40000


## m2: the destroyed ship's step, then the bot's. The second step's first frame
## shows no destroyed screen and no fade.
func test_a_destroyed_step_does_not_hide_the_next_one() -> String:
	var steps: Array[AcceptanceStep] = _steps(M2_PATH, ["ship_destroyed_in_test_tunnel", "bot_clears_test_tunnel"])
	var seen: Dictionary = _fly_into_second_step(steps, null)
	if seen.has("error"):
		return seen["error"]
	if not bool(seen["before"]["destroyed"]):
		return "the first step did not end on the destroyed screen: %s" % [seen["before"]]
	var after: Dictionary = seen["after"]
	if bool(after["destroyed"]) or bool(after["destroyed_node"]) or float(after["fade"]) > 0.0 \
			or float(after["overlay"]) > 0.0:
		return "the second step's first frame still shows %s" % [after]
	return ""


## m3: the G2 escape, then the generated seed's. The second step's first frame
## shows no escape end screen and no fade.
func test_an_escape_step_does_not_hide_the_next_one() -> String:
	var steps: Array[AcceptanceStep] = _steps(M3_PATH, ["bot_g2_escape", "bot_generated_escape"])
	var seen: Dictionary = _fly_into_second_step(steps, null)
	if seen.has("error"):
		return seen["error"]
	if not bool(seen["before"]["escaped"]):
		return "the first step did not end on the escape screen: %s" % [seen["before"]]
	var after: Dictionary = seen["after"]
	if bool(after["escaped"]) or bool(after["escaped_node"]) or float(after["fade"]) > 0.0 \
			or float(after["overlay"]) > 0.0:
		return "the second step's first frame still shows %s" % [after]
	return ""


## A screenshot at the second step's first tick is taken with no end screen
## or fade from the step before over the scene.
func test_a_screenshot_after_an_end_screen_shows_the_scene() -> String:
	var steps: Array[AcceptanceStep] = _steps(M2_PATH, ["ship_destroyed_in_test_tunnel", "bot_clears_test_tunnel"])
	if steps.size() != 2:
		return "m2 lacks the steps"
	steps[1].screenshot_ticks = [0]
	var shots: AcceptanceScreenshots = AcceptanceScreenshots.new()
	var grabbed: Array[Dictionary] = []
	var holder: Array = [null]  # The main scene, once the runner has it.
	shots.grab = func() -> Variant:
		grabbed.append(_state(holder[0]))
		return "recorded by the test"
	var seen: Dictionary = _fly_into_second_step(steps, shots, holder)
	if seen.has("error"):
		return seen["error"]
	# The first step's own end screenshot shows its end screen; the second's shows the scene.
	if grabbed.size() != 2:
		return "%d screenshots were taken: %s" % [grabbed.size(), grabbed]
	if not bool(grabbed[0]["destroyed"]):
		return "the first step's end screenshot did not show its own end screen: %s" % [grabbed[0]]
	var second: Dictionary = grabbed[1]
	if bool(second["destroyed"]) or bool(second["destroyed_node"]) or float(second["overlay"]) > 0.0:
		return "the second step's screenshot was taken over %s" % [second]
	return ""


## A main scene with no end screens (a bare node) is left alone.
func test_a_scene_without_end_screens_is_left_alone() -> String:
	var bare: Node = Node.new()
	AcceptanceStepLevel.clear_end_screens(bare)
	bare.free()
	return ""


## Clearing puts the sequences back to where a restart's fade-in ends, with the same times.
func test_clearing_keeps_the_sequence_times() -> String:
	var wiring: DestroyedWiring = DestroyedWiring.new()
	wiring.sequence.update(0.0, 0.5, false)
	wiring.escape.sequence.update(0.0, 0.5, false)
	var fade: float = wiring.sequence.fade_seconds
	var hold: float = wiring.escape.sequence.hold_seconds
	wiring.clear_end_screens()
	if wiring.sequence.state != DestroyedSequence.State.ALIVE \
			or wiring.escape.sequence.state != DestroyedSequence.State.ALIVE or wiring.fade_alpha() != 0.0:
		return "states %d and %d, fade %f" % [wiring.sequence.state, wiring.escape.sequence.state, wiring.fade_alpha()]
	if wiring.sequence.fade_seconds != fade or wiring.escape.sequence.hold_seconds != hold:
		return "the times changed"
	return ""


static func _steps(path: String, ids: Array[String]) -> Array[AcceptanceStep]:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(path)
	var found: Array[AcceptanceStep] = []
	for id: String in ids:
		for step: AcceptanceStep in suite.steps:
			if step.id == id:
				found.append(step)
	return found


## Flies `steps[0]` to its end and the first frame of `steps[1]`, returning
## the end screens' state as the first step ended ("before") and after that
## frame ("after"), or "error".
static func _fly_into_second_step(steps: Array[AcceptanceStep], shots: AcceptanceScreenshots,
		holder: Array = []) -> Dictionary:
	if steps.size() != 2:
		return {"error": "the suite lacks the steps"}
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.name = "end_screens"
	suite.steps.append_array(steps)
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	if shots != null:
		shots.dir = "user://test_end_screens"
		runner.screenshots = shots
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	if not holder.is_empty():
		holder[0] = main
	runner.setup(main, suites, null)
	var frames: int = 0
	while (runner.reports.is_empty() or runner.reports[0].steps.is_empty()) and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var seen: Dictionary = {"before": _state(main)}
	if runner.reports.is_empty() or runner.reports[0].steps.is_empty():
		seen = {"error": "the first step never ended"}
	else:
		runner.process_frame()
		seen["after"] = _state(main)
	main.free()
	runner.free()
	return seen


## What the end screens and the fade show in `main` now.
static func _state(main: Node) -> Dictionary:
	var wiring: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	var overlay: FadeOverlay = main.get("fade_overlay") as FadeOverlay
	return {
		"destroyed": wiring.sequence.line_shown(),
		"destroyed_node": wiring.screen != null and wiring.screen.line_visible(),
		"escaped": wiring.escape.sequence.line_shown(),
		"escaped_node": wiring.escape.screen != null and wiring.escape.screen.line_visible(),
		"fade": wiring.fade_alpha(),
		"overlay": overlay.get_alpha() if overlay != null and overlay.visible else 0.0,
	}
