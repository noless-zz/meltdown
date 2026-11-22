class_name AcceptanceCraftAndFitCheck
extends RefCounted

## The `craft_and_fit` check of a run step (#1093, CRW-2, CRF-3, CRF-4,
## DEV-6, decision record 0005). In a suite:
##
##     {"id": "craft_and_fit", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_and_fit_profile.json",
##      "checks": ["no_script_errors", "craft_and_fit"]}
##
## The step's scratch profile holds banked components and nothing crafted.
## After the replay the check opens the hub on the run as the end of a run
## opens it (`HubWiring.open_for`), with the profile and fitting saved to
## scratch files under `user://`, never the pilot's own. Scripted controller
## values then go through the scene's own `apply_controls` and `advance_frame`,
## as a pilot's would, to build the first weapon the Workbench offers, mount it
## in Primary 1 and press "Drop into the mine". The run's level must then fly
## that weapon in its first primary slot, and both scratch files must hold the
## craft and the fit. Like run_advances it swaps the scene's session, so it is
## the step's last check. How the panel reads in the headset stays
## human-checked (#950).

const PROFILE_FILE: String = "user://meltdown_acceptance_hub_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_hub_fitting.json"
const SLOT: String = "primary[0]"
const FRAME: float = 1.0 / 72.0
## Stick moves and page turns tried before a row counts as missing.
const MAX_MOVES: int = 200
const STICK_DOWN: Vector2 = Vector2(0.0, -1.0)
const STICK_RIGHT: Vector2 = Vector2(1.0, 0.0)


## "" or the problem with the step's fields: the check needs a scratch profile.
static func parse_step(field: String, step: AcceptanceStep) -> String:
	if step.has_check(AcceptanceStep.CHECK_CRAFT_AND_FIT) and step.profile_path == "":
		return "%s.%s: needed by the %s check" % [field, AcceptanceFittedStart.KEY_PROFILE,
			AcceptanceStep.CHECK_CRAFT_AND_FIT]
	return ""


## [result, message]; `measurements` gets the crafted weapon and the loadout flown.
static func run(main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or hub == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	_remove_scratch()
	var run: RunWiring = level_start.run
	run.store = ProfileStore.new(PROFILE_FILE)
	run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = _craft_fit_launch(main, hub, run, measurements)
	_remove_scratch()
	return verdict


static func _craft_fit_launch(main: Node, hub: HubWiring, run: RunWiring,
		measurements: Dictionary) -> Array:
	if not hub.open_for(run):
		return [AcceptanceReport.RESULT_FAIL, "the hub did not open"]
	var weapon: String = first_weapon(hub.text.model)
	measurements["crafted"] = weapon
	if weapon == "":
		return [AcceptanceReport.RESULT_FAIL, "the Workbench offers no weapon for the profile's bank"]
	if not press_row(main, hub, {"action": HubText.ACTION_CRAFT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no Workbench row builds %s" % weapon]
	if not ProfileStore.new(PROFILE_FILE).load_profile().crafted.has(weapon):
		return [AcceptanceReport.RESULT_FAIL, "building %s was not saved to the profile" % weapon]
	if not press_row(main, hub, {"action": HubText.ACTION_FIT, "slot": SLOT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no Fitting Bay row mounts %s in %s" % [weapon, SLOT]]
	if FittingStore.new(FITTING_FILE).load_fitting().primary[0] != weapon:
		return [AcceptanceReport.RESULT_FAIL, "mounting %s was not saved to the fitting" % weapon]
	var granted: String = hub.text.model.tree.get_upgrade(weapon).grants  # The weapon file the upgrade fits.
	if not press_row(main, hub, {"action": HubText.ACTION_LAUNCH}) or hub.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the launch row did not leave the hub: %s" % hub.panel.reason_text()]
	var flown: Array[String] = LevelStart.local_loadout(main.get("session") as LocalSession).ids_of("primary")
	measurements["primary"] = ",".join(flown)
	if flown.is_empty() or flown[0] != granted:
		return [AcceptanceReport.RESULT_FAIL, "the run flies primary %s, expected %s first" % [flown, granted]]
	return [AcceptanceReport.RESULT_PASS, "built %s, mounted it and the run flies it" % weapon]


## The first upgrade of kind weapon `model` can build now, or "".
static func first_weapon(model: HubModel) -> String:
	for id: String in model.craftable():
		if model.tree.get_upgrade(id).kind == HubText.FITS["primary"]:
			return id
	return ""


## Moves through the open hub with the right stick, a page at a time, until
## the selected row does `want`, and presses A on it. False when no row does.
static func press_row(main: Node, hub: HubWiring, want: Dictionary) -> bool:
	var last: int = -2
	for i: int in MAX_MOVES:
		if not hub.is_open():
			return false
		if hub.text.selected() == want:
			_tap(main, {DestroyedWiring.RESTART_BUTTON: true}, Vector2.ZERO)
			return true
		var line: int = hub.text.selected_line()
		_tap(main, {}, STICK_RIGHT if line == last else STICK_DOWN)  # At a page's foot, turn it.
		last = -2 if line == last else line
	return false


## A frame with nothing held, then one with `buttons` and `stick` held.
static func _tap(main: Node, buttons: Dictionary, stick: Vector2) -> void:
	_frame(main, {}, Vector2.ZERO)
	_frame(main, buttons, stick)


static func _frame(main: Node, buttons: Dictionary, stick: Vector2) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	values["right_stick"] = stick
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
