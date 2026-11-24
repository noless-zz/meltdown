extends RefCounted

## The hub between runs in the real main scene (#1093, CRW-2, CRF-3, CRF-4,
## RUN-1, RUN-7, MP-2, ARC-3): a lost or won run opens the hub on the end
## screen's press, the stick and A craft and fit there with each change saved,
## and the launch row flies the next run's first level with the fitted weapon.
## A refused launch stays in the hub; a single level never opens it.

const FRAME: float = 1.0 / 90.0
const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const NEXT_RUN_SEED: int = 77
const PROFILE_PATH: String = "user://t1093_profile.json"
const FITTING_PATH: String = "user://t1093_fitting.json"


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


func _main(source: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	(main.get("level_start") as LevelStart).source = source
	main.call("restart_level")
	return main


## The main scene flying level 1 of a three-level run with scratch stores; the
## profile has enough banked to build the needle gun.
func _run_main() -> Node:
	_clean()
	var main: Node = _main()
	var level_start: LevelStart = main.get("level_start")
	var run: RunWiring = RunWiring.new(RUN_SEED, ProfileStore.new(PROFILE_PATH),
		func() -> int: return NEXT_RUN_SEED, THREE_LEVELS, false)
	run.ship.fittings = FittingStore.new(FITTING_PATH)
	run.profile.bank({"scrap_alloy": 3, "cell_salts": 2})
	level_start.run = run
	level_start.source = run.level_source()
	(main.get("destroyed") as DestroyedWiring).escape.run = run
	main.call("restart_level")
	return main


func _fly(main: Node, seconds: float, buttons: Dictionary = {}) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	for i: int in ceili(seconds / FRAME):
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)


## Loses the ship and presses A once the destroyed screen's prompt shows.
func _lose_and_press(main: Node) -> void:
	(main.get("session") as LocalSession).sim.ships[0].hull = 0.0
	_fly(main, 5.0)
	_fly(main, FRAME, {DestroyedWiring.RESTART_BUTTON: true})
	_fly(main, FRAME)


func _done(main: Node) -> void:
	main.free()
	_clean()


func test_a_lost_run_opens_the_hub_dark_with_the_ship_held() -> String:
	var main: Node = _run_main()
	var result: String = _check_lost(main)
	_done(main)
	return result


func _check_lost(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var level_start: LevelStart = main.get("level_start")
	_fly(main, 0.1)
	var lost: LocalSession = main.get("session")
	_lose_and_press(main)
	if not hub.is_open() or hub.stations == null or not hub.stations.visible:
		return "losing the run did not open the hub on the room's stations"
	if hub.stations.get_parent() != main.get_node("XRRig") or (hub.panel != null and hub.panel.visible):
		return "the stations are not under the rig, or the flat panel shows in the room (#1299)"
	if main.get("session") != lost:
		return "a level flew behind the hub"
	if level_start.run.state.plan.run_seed != NEXT_RUN_SEED or level_start.run.ended == null:
		return "the lost run did not move on to the next run"
	if (main.get("fade_overlay") as FadeOverlay).get_alpha() < 0.99:
		return "the view is not dark behind the hub"
	if hub.stations.highlighted_id() != "crew" or hub.stations.in_use != "":
		return "the hub does not open choosing a station from the first: %s" % hub.stations.highlighted_id()
	_fly(main, 3.0, {DestroyedWiring.RESTART_BUTTON: true})
	if not hub.is_open() or main.get("session") != lost:
		return "A on the hub's first page left it"
	return ""


func test_craft_fit_and_launch_fly_the_fitted_weapon_and_are_saved() -> String:
	var main: Node = _run_main()
	var result: String = _check_launch(main)
	_done(main)
	return result


func _check_launch(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var level_start: LevelStart = main.get("level_start")
	_fly(main, 0.1)
	_lose_and_press(main)
	if not hub.is_open():
		return "losing the run did not open the hub"
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_CRAFT, "id": "needle_gun"}):
		return "no Workbench row builds the needle gun"
	if not ProfileStore.new(PROFILE_PATH).load_profile().crafted.has("needle_gun"):
		return "the craft was not saved when it happened"
	if not AcceptanceCraftAndFitCheck.press_row(main, hub,
			{"action": HubText.ACTION_FIT, "slot": "primary[0]", "id": "needle_gun"}):
		return "no Fitting Bay row mounts the needle gun"
	if FittingStore.new(FITTING_PATH).load_fitting().primary[0] != "needle_gun":
		return "the fit was not saved when it happened"
	var ended: LocalSession = main.get("session")
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_LAUNCH}):
		return "no launch row"
	var fresh: LocalSession = main.get("session")
	if hub.is_open() or fresh == ended:
		return "the launch did not leave the hub for a new level"
	var want: String = LevelSwitch.SEED_PREFIX + str(RunPlan.build(NEXT_RUN_SEED, THREE_LEVELS).level_seed(0))
	if level_start.source != want or level_start.run.state.level_index != 0:
		return "the launch flies %s, expected the next run's level 1 %s" % [level_start.source, want]
	if LevelStart.local_loadout(fresh).ids_of("primary")[0] != "needle_gun":
		return "the new run's ship flies %s" % [LevelStart.local_loadout(fresh).ids_of("primary")]
	if fresh.current_ship().hull <= 0.0:
		return "the new run's ship starts lost"
	_fly(main, 1.5)
	if (main.get("fade_overlay") as FadeOverlay).get_alpha() != 0.0:
		return "the view did not fade back in after the launch"
	if hub.is_open() or main.get("session") != fresh:
		return "the run did not fly on after the launch"
	return ""


func test_a_refused_launch_keeps_the_hub_open() -> String:
	var main: Node = _run_main()
	var result: String = _check_refused(main)
	_done(main)
	return result


func _check_refused(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	_fly(main, 0.1)
	_lose_and_press(main)
	if not hub.is_open():
		return "losing the run did not open the hub"
	hub.fitting.primary[0] = "arc_lance"  # Not crafted: the fitting check refuses it.
	var reason: String = hub.text.model.launch_check()
	if reason == "":
		return "the test's fitting passes the check"
	var ended: LocalSession = main.get("session")
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_LAUNCH}):
		return "no launch row"
	if not hub.is_open() or main.get("session") != ended:
		return "a refused launch left the hub"
	if hub.reason_text() != reason:
		return "the launch station shows '%s', expected the check's '%s'" % [hub.reason_text(), reason]
	if FileAccess.file_exists(FITTING_PATH):
		return "a refused launch saved the fitting"
	return ""


func test_a_won_run_opens_the_hub() -> String:
	var main: Node = _run_main()
	var level_start: LevelStart = main.get("level_start")
	var run: RunWiring = level_start.run
	while not run.on_last_level():
		run.after_level(ExitRule.Outcome.ESCAPED, 1.0, {})
	level_start.source = run.level_source()
	main.call("restart_level")
	var session: LocalSession = main.get("session")
	var result: String = ""
	if not HubWiring.ends_run(level_start, session):
		session.sim.ships[0].escaped = true
		if session.sim.outcome() != ExitRule.Outcome.ESCAPED:
			result = "the test could not escape the last level"
		elif not HubWiring.ends_run(level_start, session):
			result = "escaping the run's last level does not end the run"
	else:
		result = "flying the last level already ends the run"
	if result == "":
		_fly(main, 5.0)
		_fly(main, FRAME, {DestroyedWiring.RESTART_BUTTON: true})
		_fly(main, FRAME)
		var hub: HubWiring = main.get("hub")
		if not hub.is_open() or run.ended == null or not run.ended.won:
			result = "winning the run did not open the hub"
	_done(main)
	return result


func test_an_escape_before_the_last_level_does_not_open_it() -> String:
	var main: Node = _run_main()
	var level_start: LevelStart = main.get("level_start")
	var session: LocalSession = main.get("session")
	session.sim.ships[0].escaped = true
	var result: String = ""
	if HubWiring.ends_run(level_start, session):
		result = "escaping level 1 ends the run"
	else:
		_fly(main, 5.0)
		_fly(main, FRAME, {DestroyedWiring.RESTART_BUTTON: true})
		if (main.get("hub") as HubWiring).is_open():
			result = "escaping level 1 opened the hub"
		elif level_start.run.state.level_index != 1:
			result = "escaping level 1 did not fly level 2"
	_done(main)
	return result


func test_a_single_level_never_opens_the_hub() -> String:
	var main: Node = _main("seed:31")
	_fly(main, 0.1)
	var lost: LocalSession = main.get("session")
	_lose_and_press(main)
	var result: String = ""
	if (main.get("hub") as HubWiring).is_open():
		result = "a lost single level opened the hub"
	elif main.get("session") == lost:
		result = "a lost single level did not restart"
	main.free()
	return result


## The hub changes only the profile and fitting (MP-2) and reads no comfort setting (ARC-3).
func test_the_hub_wiring_reads_no_comfort_and_writes_no_sim() -> String:
	var code: Array[String] = []
	for line: String in FileAccess.get_file_as_string("res://hub_wiring.gd").split("\n"):
		code.append(line.get_slice("#", 0))  # Comments may name what the hub leaves alone.
	var text: String = "\n".join(code)
	for word: String in ["comfort", "Comfort", ".sim.ships", "sim.collected", "replay"]:
		if text.contains(word):
			return "hub_wiring.gd's code mentions %s" % word
	return ""
