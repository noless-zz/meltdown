extends RefCounted

## The `hub_screens` check (#1359, CRW-2, CMF-8, PLT-2, DEV-6, decision record
## 0012), lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "hub_screens", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_and_fit_profile.json",
##      "checks": ["no_script_errors", "hub_screens"]}
##
## After the replay a lost run opens the hub in the home base room, as in
## `hub_room`. The check then reads the base from the seat's eye point: while
## choosing, and with each station in turn taken into use through the scene's
## own controls and settled forward. For every visible word in the room it
## works out the capital height's angle at the eye and the pixels it covers on
## the Quest 3 eye buffer (`HubScreenLook`'s `eye_height_px` and
## `vertical_fov_deg`), and for every word on a screen its contrast with the
## screen's face. It fails under `min_text_deg`, `min_text_px` or
## `min_contrast`, when a word runs off its screen's face, when a screen
## material emits more than
## `max_screen_emission` or as much as the room's brightest other glow, or
## when the station that A would use, or the one in use, has no frame.
##
## The sizes are measured from the scene's nodes and projected at the Quest
## 3's resolution, not read back from a rendered image: the headless runner
## draws nothing. Whether the words are comfortable for two minutes stays a
## headset check.

const CHECK: String = "hub_screens"
const PROFILE_FILE: String = "user://meltdown_acceptance_hub_screens_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_hub_screens_fitting.json"
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
		verdict = _judge_every_station(main, hub, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _judge_every_station(main: Node, hub: HubWiring, measurements: Dictionary) -> Array:
	if hub.stations == null:
		return [AcceptanceReport.RESULT_FAIL, "the hub opened on the flat panel, not the stations"]
	var look: Dictionary = HubScreenLook.load_file()
	var worst: Dictionary = {"deg": INF, "px": INF, "contrast": INF, "text": "", "where": ""}
	var problem: String = emission_problem(hub.room.spec, look)
	if problem == "":
		problem = judge_view(hub.room, hub.stations, look, "choosing", worst)
	for id: String in hub.stations.ids:
		if problem != "":
			break
		if not AcceptanceCraftAndFitCheck.choose_station(main, hub, id):
			problem = "the stick and A did not take the %s station into use" % id
			break
		hub.stations.advance(HubStations.SETTLE_SECONDS)
		problem = judge_view(hub.room, hub.stations, look, id, worst)
	measurements["smallest_text_px"] = snappedf(worst["px"], 0.1)
	measurements["smallest_text_deg"] = snappedf(worst["deg"], 0.01)
	measurements["smallest_text"] = "%s (%s)" % [worst["text"], worst["where"]]
	measurements["lowest_contrast"] = snappedf(worst["contrast"], 0.1)
	if problem != "":
		return [AcceptanceReport.RESULT_FAIL, problem]
	return [AcceptanceReport.RESULT_PASS, "smallest text %.1f px (%.2f deg) at %dx%d per eye, lowest contrast %.1f:1" % [
		worst["px"], worst["deg"], int(look["eye_width_px"]), int(look["eye_height_px"]), worst["contrast"]]]


## "" when every screen material glows at most `max_screen_emission` and less
## than the room's brightest other glow, so no screen outshines the room.
static func emission_problem(spec: HubRoomSpec, look: Dictionary) -> String:
	var screens: Array[String] = []
	for station: Dictionary in spec.stations:
		if not screens.has(station["screen"]):
			screens.append(station["screen"])
	var brightest_other: float = 0.0
	for key: String in spec.materials:
		if not screens.has(key):
			brightest_other = maxf(brightest_other, glow(spec.materials[key]))
	for key: String in screens:
		var each: float = glow(spec.materials[key])
		if each > float(look["max_screen_emission"]):
			return "the %s material glows %.2f, over %.2f" % [key, each, look["max_screen_emission"]]
		if brightest_other > 0.0 and each >= brightest_other:
			return "the %s material glows %.2f, the brightest in the room" % [key, each]
	return ""


## A material's brightest emitted channel.
static func glow(material: Dictionary) -> float:
	var emission: Color = material["emission"]
	return maxf(emission.r, maxf(emission.g, emission.b)) * float(material["emission_energy"])


## "" when every visible word in `room` reads at the look's sizes from the eye
## point and every word on a screen against its face; `worst` keeps the
## smallest and lowest seen, `where` names the view in it.
static func judge_view(room: HubRoom, stations: HubStations, look: Dictionary, where: String,
		worst: Dictionary) -> String:
	var problem: String = ""
	for sized: Dictionary in HubScreenMeasure.label_sizes(room, room, look["cap_height_ratio"], look["vertical_fov_deg"],
			look["eye_height_px"]):
		if float(sized["px"]) < float(worst["px"]):
			worst.merge({"deg": sized["deg"], "px": sized["px"], "text": sized["text"], "where": where}, true)
		if problem == "" and (float(sized["deg"]) < float(look["min_text_deg"]) or float(sized["px"]) < float(look["min_text_px"])):
			problem = "\"%s\" (%s) is %.2f deg, %.1f px at the seat; the least is %s deg, %s px" % [sized["text"], where,
				sized["deg"], sized["px"], look["min_text_deg"], look["min_text_px"]]
	for id: String in stations.ids:
		var screen: HubStationScreen = stations.screen(id)
		var face: Color = ((screen.get_node("Face") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		for child: Node in screen.get_children():
			var label: Label3D = child as Label3D
			if label == null or not label.visible:
				continue
			var wide: float = ThemeDB.fallback_font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
				label.width if label.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0, label.font_size).x * label.pixel_size
			if problem == "" and wide > screen.face_size().x:
				problem = "\"%s\" on the %s screen is %.3f m wide, the face %.3f m" % [label.text, id, wide, screen.face_size().x]
			var ratio: float = HubScreenMeasure.contrast(label.modulate, face)
			worst["contrast"] = minf(float(worst["contrast"]), ratio)
			if problem == "" and ratio < float(look["min_contrast"]):
				problem = "\"%s\" on the %s screen has contrast %.1f:1, under %s:1" % [label.text, id, ratio, look["min_contrast"]]
	var marked: String = stations.in_use if stations.in_use != "" else stations.highlighted_id()
	if problem == "" and not stations.screen(marked).framed():
		problem = "the %s station is chosen but has no frame (%s)" % [marked, where]
	return problem


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
