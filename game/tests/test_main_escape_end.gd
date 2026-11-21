extends RefCounted

## The escape's end screen in the real main scene (#751, RUN-3, RUN-7, CMF-8,
## MP-2): an escape from a seed shows it, a press after the hold flies the same
## seed again from its start through the fade, and a run lost in the meltdown
## still gets the destroyed ship's screen.

const FRAME: float = 1.0 / 90.0
const SEED_SOURCE: String = "seed:31"


func _main(source: String) -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	(main.get("level_start") as LevelStart).source = source
	main.call("restart_level")
	return main


func _fly(main: Node, seconds: float, buttons: Dictionary = {}) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	for i: int in ceili(seconds / FRAME):
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)


func test_an_escape_from_a_seed_shows_the_screen_and_flies_the_seed_again() -> String:
	var main: Node = _main(SEED_SOURCE)
	var result: String = _check_escape(main)
	main.free()
	return result


func _check_escape(main: Node) -> String:
	var wiring: DestroyedWiring = main.get("destroyed")
	var screen: EscapeScreen = wiring.escape.screen
	var fade: FadeOverlay = main.get("fade_overlay")
	if screen == null or screen.get_parent() != main.get_node("XRRig"):
		return "the escape screen is not under the rig"
	_fly(main, 0.1)
	var old: LocalSession = main.get("session")
	if old.sim.reactor == null:
		return "the seed's session has no reactor"
	var start: Vector3 = old.sim.start_positions[0]
	var reactor_at: Vector3i = old.sim.reactor.position_mm
	if screen.line_visible():
		return "the escape screen shows while flying"
	old.sim.reactor.destroyed = true
	old.sim.reactor.meltdown_ticks_left = 38 * ReactorState.TICKS_PER_SECOND
	old.sim.ships[0].escaped = true
	_fly(main, 1.2)
	if not screen.line_visible() or not screen.time_text().contains("0:38"):
		return "ESCAPED with 0:38 is not shown: '%s'" % screen.time_text()
	if wiring.screen.line_visible():
		return "SHIP DESTROYED shows after an escape"
	var verdict: Array = AcceptanceEscapeScreenCheck.run(main, true, {})
	if verdict[0] != AcceptanceReport.RESULT_PASS or not str(verdict[1]).contains("0:38"):
		return "the suite's escape_screen check did not pass on an escape: %s" % [verdict]
	if fade.get_alpha() < 0.99:
		return "the view is not dark a second after the escape (alpha %.2f)" % fade.get_alpha()
	_fly(main, 2.0, {DestroyedWiring.KEYBOARD_BUTTON: true})
	if main.get("session") != old:
		return "a press before the prompt restarted the level"
	_fly(main, 0.1)
	if not screen.prompt_visible() or not screen.prompt_text().contains("Enter"):
		return "the flat build's prompt is not shown after the hold: '%s'" % screen.prompt_text()
	_fly(main, FRAME, {DestroyedWiring.KEYBOARD_BUTTON: true})
	var fresh: LocalSession = main.get("session")
	if fresh == old:
		return "Enter did not restart the level"
	if (main.get("level_start") as LevelStart).source != SEED_SOURCE:
		return "the restart changed what the launch flies"
	if fresh.sim.start_positions[0] != start or fresh.sim.reactor == null \
			or fresh.sim.reactor.position_mm != reactor_at:
		return "the restart did not fly the same seed"
	if fresh.sim.reactor.destroyed or fresh.sim.ships[0].escaped \
			or fresh.sim.outcome() != ExitRule.Outcome.RUNNING:
		return "the restarted run did not start from the beginning"
	if fresh.current_ship().position.distance_to(start) > 0.5:
		return "the restarted ship is not at the start"
	if screen.line_visible():
		return "ESCAPED is still shown after the restart"
	_fly(main, 1.2)
	if fade.get_alpha() != 0.0:
		return "the view did not fade back in (alpha %.2f)" % fade.get_alpha()
	return ""


func test_a_meltdown_loss_shows_the_destroyed_screen_not_the_escape_one() -> String:
	var main: Node = _main(LevelSwitch.path_for("g2"))
	var result: String = _check_loss(main)
	main.free()
	return result


func _check_loss(main: Node) -> String:
	_fly(main, 0.1)
	var session: LocalSession = main.get("session")
	var ship: ShipState = session.sim.ships[0]
	# Far outside the exit, so the countdown's end is a loss.
	ship.position = session.sim.start_positions[0] + Vector3(0.0, 0.0, -30.0)
	session.sim.reactor.destroyed = true
	session.sim.reactor.meltdown_ticks_left = 2
	_fly(main, 1.2)
	if session.sim.outcome() != ExitRule.Outcome.LOST:
		return "the run did not end LOST in the meltdown: %d" % session.sim.outcome()
	var wiring: DestroyedWiring = main.get("destroyed")
	if not wiring.screen.line_visible():
		return "SHIP DESTROYED is not shown after a meltdown loss"
	if wiring.escape.screen.line_visible():
		return "the escape screen shows after a meltdown loss"
	if AcceptanceEscapeScreenCheck.run(main, true, {})[0] != AcceptanceReport.RESULT_FAIL:
		return "the suite's escape_screen check passed on a meltdown loss"
	return ""
