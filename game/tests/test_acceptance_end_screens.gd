extends RefCounted

## An end screen from one acceptance step does not hide the scene for the
## steps after it (#917, DEV-6, CMF-8, ARC-3, decision record 0005). The m2
## destroyed step is followed by a tunnel step, and the m3 escape step by the
## next m3 step; on the next step's first frame, the frame its tick-0
## screenshot shows, neither end screen is up and the fade is clear.
##
## The scene is instantiated outside the tree, so `_ready` does not hang the
## screens or the fade quad; each test hangs them as `_ready` does. The
## screenshot grab notes what the view holds and returns a reason in place of
## an image, so nothing is written.

## More frames than the two steps need; a runner still going after this hangs.
const FRAME_LIMIT: int = 20000

## One note per screenshot taken, in order: what the view held then.
var _seen: Array[Dictionary] = []
var _main: Node = null


func _on_quit(_code: int) -> void:
	pass


## What the grab sees: each end screen's visibility and the fade's opacity.
func _grab() -> Variant:
	var destroyed: DestroyedWiring = _main.get("destroyed")
	var overlay: FadeOverlay = _main.get("fade_overlay")
	_seen.append({
		"destroyed": destroyed.screen.visible,
		"escaped": destroyed.escape.screen.visible,
		"fade": overlay.get_alpha(),
	})
	return "noted by the test"


## Steps `ids` of the suite at `path`, checks dropped so only the view is at
## stake, with a screenshot at the end of each and at the start of each
## after the first.
func _steps(path: String, ids: Array[String]) -> Array[AcceptanceSuite]:
	var source: AcceptanceSuite = AcceptanceSuite.load_file(path)
	var two: AcceptanceSuite = AcceptanceSuite.new()
	two.name = source.name
	for id: String in ids:
		for step: AcceptanceStep in source.steps:
			if step.id == id:
				step.checks.clear()
				step.screenshot_at_end = true
				step.screenshot_ticks.clear()
				if two.steps.size() > 0:
					step.screenshot_ticks.append(0)
				two.steps.append(step)
	var suites: Array[AcceptanceSuite] = [two]
	return suites


## Flies `suites` in a main scene with its end screens and fade quad hung.
## Returns the problem, or "".
func _fly(suites: Array[AcceptanceSuite]) -> String:
	_seen.clear()
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	_main.call("attach_fade_overlay")
	var destroyed: DestroyedWiring = _main.get("destroyed")
	destroyed.attach(_main.get_node("XRRig") as Node3D, null, null)
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var shots: AcceptanceScreenshots = AcceptanceScreenshots.new()
	shots.grab = _grab
	runner.screenshots = shots
	runner.setup(_main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = "" if runner.finished else "the runner was still going after %d frames" % frames
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	_main.free()
	_main = null
	runner.free()
	return problem


## `_seen` holds the first step's end, then the second step's start: the end
## shows `screen` (its fade may still be rising), the start shows nothing over
## the scene.
func _judge(screen: String) -> String:
	if _seen.size() != 3:
		return "%d screenshots noted, wanted 3: %s" % [_seen.size(), _seen]
	var end_first: Dictionary = _seen[0]
	if not bool(end_first[screen]):
		return "the first step did not end on its %s screen, so this test shows nothing: %s" % [screen, end_first]
	var start_second: Dictionary = _seen[1]
	if bool(start_second["destroyed"]) or bool(start_second["escaped"]) or float(start_second["fade"]) != 0.0:
		return "the next step's first frame still had an end screen or fade: %s" % start_second
	return ""


func test_m2_destroyed_screen_is_down_on_the_next_steps_first_frame() -> String:
	var problem: String = _fly(_steps("res://acceptance/suites/m2.json",
		["ship_destroyed_in_test_tunnel", "bot_clears_test_tunnel"] as Array[String]))
	return problem if problem != "" else _judge("destroyed")


func test_m3_escape_screen_is_down_on_the_next_steps_first_frame() -> String:
	var problem: String = _fly(_steps("res://acceptance/suites/m3.json",
		["bot_g2_escape", "bot_generated_escape"] as Array[String]))
	return problem if problem != "" else _judge("escaped")


## The reset itself: both screens down, both fades clear, and a destroyed
## ship afterwards still brings `SHIP DESTROYED` up, so play is unchanged.
func test_reset_takes_both_screens_down_and_play_still_shows_them() -> String:
	var wiring: DestroyedWiring = DestroyedWiring.new()
	var rig: Node3D = Node3D.new()
	wiring.attach(rig, null, null)
	wiring.sequence.update(0.0, 10.0, false)
	wiring.sequence.update(0.0, 10.0, false)
	wiring.escape.sequence.update(0.0, 10.0, false)
	wiring.escape.sequence.update(0.0, 10.0, false)
	wiring.screen.visible = true
	wiring.escape.screen.visible = true
	var times: Array[float] = [wiring.sequence.fade_seconds, wiring.sequence.hold_seconds]
	wiring.reset()
	var problem: String = ""
	if wiring.screen.visible or wiring.escape.screen.visible:
		problem = "a screen stayed up after the reset"
	elif wiring.fade_alpha() != 0.0:
		problem = "the fade is %s after the reset" % wiring.fade_alpha()
	elif [wiring.sequence.fade_seconds, wiring.sequence.hold_seconds] != times:
		problem = "the reset changed the destroyed times from %s" % [times]
	else:
		wiring.sequence.update(0.0, 0.1, false)
		if not wiring.sequence.line_shown():
			problem = "a destroyed ship after the reset showed no SHIP DESTROYED"
	rig.free()
	return problem
