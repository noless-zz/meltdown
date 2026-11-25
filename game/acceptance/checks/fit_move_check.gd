extends RefCounted

## The `fit_move` check (#1336, CRF-3, CRF-4, DEV-6, decision record 0005),
## lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "fit_move", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_and_fit_profile.json",
##      "checks": ["no_script_errors", "fit_move"]}
##
## m4's craft-and-fit flow with a move added: after the replay the hub opens on
## the run (`HubWiring.open_for`) with the profile and fitting in scratch files
## under `user://`. Scripted stick and A presses build the first weapon the
## Workbench offers and mount it in Primary 1. Primary 2 must then offer it
## only as a move, never as a second mount; the move is pressed, the scratch
## fitting must hold it in Primary 2 alone, and the launch must fly the ship
## file's own Primary 1 with the weapon in Primary 2. It moves the run on, so it
## is the step's last check. How the rows read stays human-checked (#950).

const CHECK: String = "fit_move"
const PROFILE_FILE: String = "user://meltdown_acceptance_fit_move_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_fit_move_fitting.json"
const FROM: String = "primary[0]"
const TO: String = "primary[1]"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or hub == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = _craft_fit_move_launch(main, hub, level_start.run, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _craft_fit_move_launch(main: Node, hub: HubWiring, run: RunWiring, measurements: Dictionary) -> Array:
	if not hub.open_for(run):
		return [AcceptanceReport.RESULT_FAIL, "the hub did not open"]
	var weapon: String = AcceptanceCraftAndFitCheck.first_weapon(hub.text.model)
	measurements["crafted"] = weapon
	if weapon == "":
		return [AcceptanceReport.RESULT_FAIL, "the Workbench offers no weapon for the profile's bank"]
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_CRAFT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no Workbench row builds %s" % weapon]
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_FIT, "slot": FROM, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no Fitting Bay row mounts %s in %s" % [weapon, FROM]]
	if AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_FIT, "slot": TO, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "%s is offered as a second mount in %s" % [weapon, TO]]
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_MOVE, "slot": TO, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no Fitting Bay row moves %s to %s" % [weapon, TO]]
	var saved: Array[String] = FittingStore.new(FITTING_FILE).load_fitting().primary
	measurements["fitted"] = ",".join(saved)
	if saved != (["", weapon] as Array[String]):
		return [AcceptanceReport.RESULT_FAIL, "after the move the fitting holds primary %s" % [saved]]
	var granted: String = hub.text.model.tree.get_upgrade(weapon).grants
	var stock: Array = hub.text.model.ship_data[ShipTuning.LOADOUT_KEY]["primary"]
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_LAUNCH}) or hub.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the launch row did not leave the hub: %s" % hub.reason_text()]
	var flown: Array[String] = LevelStart.local_loadout(main.get("session") as LocalSession).ids_of("primary")
	measurements["primary"] = ",".join(flown)
	if flown.size() < 2 or flown[0] != str(stock[0]) or flown[1] != granted:
		return [AcceptanceReport.RESULT_FAIL, "the run flies primary %s, expected %s then %s" % [flown, stock[0], granted]]
	return [AcceptanceReport.RESULT_PASS, "built %s, mounted it, moved it to Primary 2 and the run flies it there" % weapon]


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
