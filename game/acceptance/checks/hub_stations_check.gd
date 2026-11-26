extends RefCounted

## The `hub_stations` check (#1299, CRW-2, CRF-3, CRF-4, PLT-5, decision
## record 0012), lane-c's file under `acceptance/checks/`. In
## `suites/m6/base.json`:
##
##     {"id": "hub_stations", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_and_fit_profile.json",
##      "checks": ["no_script_errors", "hub_stations"]}
##
## After the replay the ship is lost and restart pressed, as a lost run opens
## the hub, with the profile and fitting kept in scratch files. Scripted
## controller values then go through the scene's own `apply_controls` and
## `advance_frame`: the stick steps to the craft station and A takes it into
## use, which must show its rows while the others show only their titles; its
## screen must show the selected upgrade's cost with what is held, and the
## stick walked over its rows must show every buildable and locked upgrade's
## cost while it is selected (#1317, #1394); its first ready weapon is built; the fit station mounts it in Primary 1; the
## launch station's launch row leaves the hub. The new run must fly the weapon
## first. The flat panel must stay hidden throughout. It moves the run on, so
## it is the step's last check. Pointing at a station is covered by unit tests;
## how it feels stays human-checked in the headset.

const CHECK: String = "hub_stations"
const PROFILE_FILE: String = "user://meltdown_acceptance_hub_stations_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_hub_stations_fitting.json"
const SLOT: String = "primary[0]"
const ROOM_CHECK: GDScript = preload("res://acceptance/checks/hub_room_check.gd")


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
	var verdict: Array = ROOM_CHECK.judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		verdict = _craft_fit_launch(main, hub, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _craft_fit_launch(main: Node, hub: HubWiring, measurements: Dictionary) -> Array:
	if hub.stations == null or (hub.panel != null and hub.panel.visible):
		return [AcceptanceReport.RESULT_FAIL, "the hub opened on the flat panel, not the stations"]
	var weapon: String = AcceptanceCraftAndFitCheck.first_weapon(hub.text.model)
	measurements["crafted"] = weapon
	if weapon == "":
		return [AcceptanceReport.RESULT_FAIL, "the profile's bank builds no weapon"]
	if not AcceptanceCraftAndFitCheck.choose_station(main, hub, "craft"):
		return [AcceptanceReport.RESULT_FAIL, "the stick and A did not take the craft station into use"]
	var shown: String = _only_in_use_shows_rows(hub)
	if shown == "":
		shown = _workbench_shows_costs(main, hub, measurements)
	if shown != "":
		return [AcceptanceReport.RESULT_FAIL, shown]
	if not AcceptanceCraftAndFitCheck.press_in_station(main, hub, {"action": HubText.ACTION_CRAFT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no row of the craft station builds %s" % weapon]
	if not ProfileStore.new(PROFILE_FILE).load_profile().crafted.has(weapon):
		return [AcceptanceReport.RESULT_FAIL, "building %s was not saved to the profile" % weapon]
	if not AcceptanceCraftAndFitCheck.choose_station(main, hub, "fit") or not \
			AcceptanceCraftAndFitCheck.press_in_station(main, hub, {"action": HubText.ACTION_FIT, "slot": SLOT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no row of the fit station mounts %s in %s" % [weapon, SLOT]]
	if FittingStore.new(FITTING_FILE).load_fitting().primary[0] != weapon:
		return [AcceptanceReport.RESULT_FAIL, "mounting %s was not saved to the fitting" % weapon]
	var granted: String = hub.text.model.tree.get_upgrade(weapon).grants
	if not AcceptanceCraftAndFitCheck.choose_station(main, hub, "launch") or not \
			AcceptanceCraftAndFitCheck.press_in_station(main, hub, {"action": HubText.ACTION_LAUNCH}) or hub.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the launch station did not leave the hub: %s" % hub.reason_text()]
	var flown: Array[String] = LevelStart.local_loadout(main.get("session") as LocalSession).ids_of("primary")
	measurements["primary"] = ",".join(flown)
	if flown.is_empty() or flown[0] != granted:
		return [AcceptanceReport.RESULT_FAIL, "the run flies primary %s, expected %s first" % [flown, granted]]
	return [AcceptanceReport.RESULT_PASS, "built %s at the craft station, mounted it at the fit station, launched" %
		weapon]


## "" when the station in use shows rows, no more than the hub file allows
## (#1300: the title, `max_rows_visible` rows, a note and a reason), and every
## other one only its title.
static func _only_in_use_shows_rows(hub: HubWiring) -> String:
	if hub.stations.texts().size() < 2:
		return "the station in use shows no rows: %s" % [hub.stations.texts()]
	if hub.stations.texts().size() > hub.text.rows_shown() + 3:
		return "the station in use shows %d lines: %s" % [hub.stations.texts().size(), hub.stations.texts()]
	for id: String in hub.stations.ids:
		var words: Node = hub.room.get_node_or_null("Station_%s/Screen/%s" % [id, HubStationScreen.NODE_NAME])
		var count: int = 0
		for label: Node in words.get_children() if words != null else []:
			count += 1 if label is Label3D and (label as Label3D).visible else 0
		if id != hub.stations.in_use and count != 1:
			return "the %s station shows %d lines, expected its title only" % [id, count]
	return ""


## "" when the craft station's screen shows its selected upgrade's cost, and
## walking the stick over its rows shows each upgrade's cost in turn (#1394):
## since #1351 a cost shows only under the selected upgrade.
static func _workbench_shows_costs(main: Node, hub: HubWiring, measurements: Dictionary) -> String:
	var model: HubModel = hub.text.model
	var id: String = str(hub.text.selected().get("id", ""))
	if id == "":
		return "the craft station selects no upgrade"
	var cost: String = AcceptanceWorkbenchCosts.cost_line(model, id)
	measurements["cost"] = cost
	if not hub.stations.texts().has(cost):
		return "the craft station's screen does not show \"%s\": %s" % [cost, hub.stations.texts()]
	var seen: Dictionary[String, Array] = AcceptanceWorkbenchCosts.walk(hub.text, hub.stations.texts,
		func(delta: int) -> void: _stick(main, delta))
	measurements["costs_seen"] = seen.size()
	return AcceptanceWorkbenchCosts.judge(model, seen)


## One stick move through the scene's own controls: a frame with nothing held,
## then one with the stick held up (-1) or down (1), as `AcceptanceCraftAndFitCheck` taps.
static func _stick(main: Node, delta: int) -> void:
	for stick: Vector2 in [Vector2.ZERO, Vector2(0.0, -float(delta))]:
		var values: Dictionary = ControllerSampler.idle_values()
		values["right_stick"] = stick
		main.call("apply_controls", values)
		main.call("advance_frame", AcceptanceCraftAndFitCheck.FRAME)


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
