extends RefCounted

## The end screens' lists and base prompt in the real main scene (#1376,
## CRF-2, RUN-7, SLV-3, MP-2): a lost run lists what earlier escapes kept and
## what the level lost and says "return to base"; an escape before the last
## level lists what it banks and keeps its own prompt; a won run's escape says
## "return to base"; a single level lists nothing and still says "restart".
## The flat build runs headless, so the prompts name Enter.

const FRAME: float = 1.0 / 90.0
const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const PROFILE_PATH: String = "user://t1376_profile.json"
const FITTING_PATH: String = "user://t1376_fitting.json"


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	(main.get("level_start") as LevelStart).source = ""
	main.call("restart_level")
	return main


## The main scene flying level 1 of a three-level run, or the level after
## `escapes` escaped levels, each banking `banked_each`.
func _run_main(escapes: int = 0, banked_each: Dictionary = {}) -> Node:
	_clean()
	var main: Node = _main()
	var level_start: LevelStart = main.get("level_start")
	var run: RunWiring = RunWiring.new(12345, ProfileStore.new(PROFILE_PATH), func() -> int: return 77,
		THREE_LEVELS, false)
	run.ship.fittings = FittingStore.new(FITTING_PATH)
	for i: int in escapes:
		run.after_level(ExitRule.Outcome.ESCAPED, 1.0, banked_each.duplicate())
	level_start.run = run
	level_start.source = run.level_source()
	(main.get("destroyed") as DestroyedWiring).escape.run = run
	main.call("restart_level")
	return main


func _fly(main: Node, seconds: float) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = {}
	for i: int in ceili(seconds / FRAME):
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)


func _done(main: Node) -> void:
	main.free()
	_clean()


func test_a_lost_run_lists_kept_and_lost_and_says_return_to_base() -> String:
	var main: Node = _run_main(1, {"cell_salts": 2})
	var result: String = _check_lost(main)
	_done(main)
	return result


func _check_lost(main: Node) -> String:
	var session: LocalSession = main.get("session")
	var wiring: DestroyedWiring = main.get("destroyed")
	session.sim.collected["scrap_alloy"] = 3
	session.sim.ships[0].hull = 0.0
	_fly(main, 5.0)
	var lists: EndScreenLists = wiring.escape.lists
	var expected: String = lists.destroyed_text({"cell_salts": 2}, {"scrap_alloy": 3}, 0)
	if not wiring.screen.line_visible() or wiring.screen.lists_text() != expected:
		return "the destroyed screen lists '%s', expected '%s'" % [wiring.screen.lists_text(), expected]
	if not expected.contains(lists.items({"cell_salts": 2})) or not expected.contains(lists.items({"scrap_alloy": 3})):
		return "the lists '%s' leave out a kind" % expected
	if not wiring.screen.prompt_visible() or wiring.screen.prompt_text() != "Press Enter: return to base":
		return "the destroyed prompt reads '%s'" % wiring.screen.prompt_text()
	if session.sim.collected != {"scrap_alloy": 3}:
		return "the screen changed the sim's counts: %s" % session.sim.collected
	return ""


func test_an_escape_before_the_last_level_lists_the_bank_and_flies_on() -> String:
	var main: Node = _run_main()
	var result: String = _check_escape(main)
	_done(main)
	return result


func _check_escape(main: Node) -> String:
	var session: LocalSession = main.get("session")
	var end: EscapeEndWiring = (main.get("destroyed") as DestroyedWiring).escape
	session.sim.collected["cell_salts"] = 2
	session.sim.ships[0].escaped = true
	_fly(main, 5.0)
	var expected: String = end.lists.escape_text({"cell_salts": 2}, 0)
	if not end.screen.line_visible() or end.screen.lists_text() != expected or end.lists_shown != expected:
		return "the escape screen lists '%s', expected '%s'" % [end.screen.lists_text(), expected]
	if end.screen.prompt_text() != "Press Enter to fly again":
		return "an escape that does not end the run prompts '%s'" % end.screen.prompt_text()
	return ""


func test_a_won_run_escape_says_return_to_base() -> String:
	var main: Node = _run_main(2, {"cell_salts": 1})
	var session: LocalSession = main.get("session")
	var end: EscapeEndWiring = (main.get("destroyed") as DestroyedWiring).escape
	session.sim.ships[0].escaped = true
	_fly(main, 5.0)
	var result: String = ""
	if not end.run.on_last_level() or session.sim.outcome() != ExitRule.Outcome.ESCAPED:
		result = "the test did not escape the run's last level"
	elif end.screen.line_text() != EscapeScreenLook.FALLBACK["won_text"] \
			or end.screen.prompt_text() != "Press Enter: return to base":
		result = "the won run shows '%s' and prompts '%s'" % [end.screen.line_text(), end.screen.prompt_text()]
	_done(main)
	return result


func test_a_single_level_lists_nothing_and_restarts() -> String:
	var main: Node = _main()
	var session: LocalSession = main.get("session")
	var wiring: DestroyedWiring = main.get("destroyed")
	session.sim.collected["cell_salts"] = 1
	session.sim.ships[0].hull = 0.0
	_fly(main, 5.0)
	var result: String = ""
	if not wiring.screen.prompt_visible() or wiring.screen.prompt_text() != DestroyedScreen.PROMPT_FLAT:
		result = "a single level prompts '%s'" % wiring.screen.prompt_text()
	elif wiring.screen.lists_text() != "" or wiring.lists_shown != "":
		result = "a single level lists '%s'" % wiring.screen.lists_text()
	main.free()
	return result
