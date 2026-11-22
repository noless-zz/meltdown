extends RefCounted

## The hub the app opens in (#1171, CRW-2, PLT-2, RUN-8, CMF-8, MP-2), in the
## real main scene: it opens dark before any level flies, the ship is held and
## nothing ticks behind it, "Drop into the mine" flies the run's first level
## with the fitted weapon and fades the view in as between runs, and a waiting
## suspended run shows its resume row and resumes as it does between runs.

const FRAME: float = 1.0 / 72.0
const RUN_SEED: int = 31337
const SAVED_SEED: int = 4242
const NEXT_SEED: int = 77
const PROFILE_PATH: String = "user://t1171_hub_profile.json"
const FITTING_PATH: String = "user://t1171_hub_fitting.json"
const SAVE_PATH: String = "user://t1171_hub_run.json"


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH, SAVE_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


## The main scene as a normal start leaves it: a new run of `RUN_SEED` on
## scratch stores, its first level built, and the start-up hub open on it.
func _started() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var level_start: LevelStart = main.get("level_start")
	var run: RunWiring = RunWiring.new(RUN_SEED, ProfileStore.new(PROFILE_PATH), func() -> int: return NEXT_SEED)
	run.ship.fittings = FittingStore.new(FITTING_PATH)
	run.saves = RunSaveStore.new(SAVE_PATH)
	run.profile.bank({"scrap_alloy": 3, "cell_salts": 2})
	level_start.run = run
	level_start.source = run.level_source()
	(main.get("destroyed") as DestroyedWiring).escape.run = run
	main.call("restart_level")
	StartChoice.open_hub(main.get("hub"), level_start, main.get("destroyed"))
	return main


## Suspends a run of `SAVED_SEED` at its first shaft choice into `SAVE_PATH`.
func _suspend_a_run() -> void:
	var other: RunWiring = RunWiring.new(SAVED_SEED, null, func() -> int: return NEXT_SEED)
	other.saves = RunSaveStore.new(SAVE_PATH)
	other.escape_for_choice({}, 0)
	other.suspend()


func _fly(main: Node, seconds: float, stick: Vector2 = Vector2.ZERO) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_stick"] = stick
	for i: int in ceili(seconds / FRAME):
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)


func _held(main: Node) -> bool:
	return ShipHold.is_held(main.get("dev_menu"), main.get("flight_test"), main.get("session"), main.get("destroyed"))


func test_the_hub_opens_dark_before_any_level_flies_and_holds_the_ship() -> String:
	_clean()
	var main: Node = _started()
	var result: String = _check_open(main)
	main.free()
	_clean()
	return result


func _check_open(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var session: LocalSession = main.get("session")
	var start: Vector3 = session.current_ship().position
	if not hub.is_open() or hub.panel == null or not hub.panel.visible:
		return "the start-up hub did not open"
	if hub.text.model.run_waits():
		return "a resume row shows with no suspended run"
	if not _held(main):
		return "the ship is not held while the hub is open"
	_fly(main, 1.0, Vector2(0.0, 1.0))
	if main.get("session") != session or session.current_ship().position != start or session.ticks_last_advance != 0:
		return "the level flew behind the hub"
	if (main.get("fade_overlay") as FadeOverlay).get_alpha() < 0.99:
		return "the view is not dark behind the hub"
	return ""


func test_drop_into_the_mine_flies_the_fitted_first_level_through_the_fade() -> String:
	_clean()
	var main: Node = _started()
	var result: String = _check_launch(main)
	main.free()
	_clean()
	return result


func _check_launch(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var level_start: LevelStart = main.get("level_start")
	var behind: LocalSession = main.get("session")
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_CRAFT, "id": "needle_gun"}) \
			or not AcceptanceCraftAndFitCheck.press_row(main, hub,
				{"action": HubText.ACTION_FIT, "slot": "primary[0]", "id": "needle_gun"}):
		return "the start-up hub did not craft and fit the needle gun"
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_LAUNCH}):
		return "no launch row"
	var fresh: LocalSession = main.get("session")
	if hub.is_open() or fresh == behind:
		return "the launch did not leave the hub for a new level"
	var want: String = LevelSwitch.SEED_PREFIX + str(level_start.run.state.plan.level_seed(0))
	if level_start.run.state.plan.run_seed != RUN_SEED or level_start.run.state.level_index != 0 \
			or level_start.source != want:
		return "the launch flies %s of run %d, expected level 1 %s of run %d" % [level_start.source,
			level_start.run.state.plan.run_seed, want, RUN_SEED]
	if LevelStart.local_loadout(fresh).ids_of("primary")[0] != "needle_gun":
		return "the run's ship flies %s" % [LevelStart.local_loadout(fresh).ids_of("primary")]
	_fly(main, FRAME)
	var fading: float = (main.get("fade_overlay") as FadeOverlay).get_alpha()
	if fading <= 0.0 or fading >= 1.0:
		return "the view did not fade in after the launch (alpha %.2f)" % fading
	_fly(main, 3.0)
	if (main.get("fade_overlay") as FadeOverlay).get_alpha() > 0.0 or _held(main):
		return "after the fade the view is still dark or the ship held"
	var start: Vector3 = fresh.current_ship().position
	_fly(main, 0.5, Vector2(0.0, 1.0))
	if fresh.current_ship().position == start:
		return "the launched ship does not fly"
	return ""


func test_a_suspended_run_resumes_from_the_start_up_hub() -> String:
	_clean()
	_suspend_a_run()
	var main: Node = _started()
	var result: String = _check_resume(main)
	main.free()
	_clean()
	return result


func _check_resume(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var level_start: LevelStart = main.get("level_start")
	var behind: LocalSession = main.get("session")
	if not hub.is_open() or hub.text.model.waiting() != {"level": 2, "seed": SAVED_SEED}:
		return "the start-up hub offers %s" % (hub.text.model.waiting() if hub.is_open() else {})
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_RESUME}):
		return "no resume row"
	var run: RunWiring = level_start.run
	if hub.is_open() or main.get("session") == behind:
		return "the resume did not leave the hub for a level"
	if run.state.plan.run_seed != SAVED_SEED or run.state.current_depth() != 2 \
			or level_start.source != run.level_source():
		return "the resume flies %s of run %d at depth %d" % [level_start.source, run.state.plan.run_seed,
			run.state.current_depth()]
	if run.saves.has_save():
		return "the save was left, so the run could resume twice"
	return ""
