extends RefCounted

## The home base screens in the room (#1359, CRW-2, CMF-8, ARC-3, MP-2): every
## word reads at the look's angle from the seat while choosing and with each
## station in use and settled forward; the station in use comes towards the eye
## and grows over the look's time and goes back when left, moving nothing but
## its screen; the station A would use and the one in use are framed, the
## others not; a screen shows at most the look's rows.

const STATIONS_TEST: GDScript = preload("res://tests/test_hub_stations.gd")
const CHECK: GDScript = preload("res://acceptance/checks/hub_screens_check.gd")
const FRAME: float = 1.0 / 72.0


static func _open() -> HubStations:
	return STATIONS_TEST._open(STATIONS_TEST._hub(STATIONS_TEST._rich_profile()))


static func _eye_distance(stations: HubStations, id: String) -> float:
	var room: Node = stations.get_parent()
	return HubScreenMeasure.in_space_of(stations.screen(id), room).origin.length()


func test_every_word_reads_from_the_seat() -> String:
	var stations: HubStations = _open()
	var room: HubRoom = stations.get_parent() as HubRoom
	var look: Dictionary = HubScreenLook.load_file()
	var worst: Dictionary = {"deg": INF, "px": INF, "contrast": INF, "text": "", "where": ""}
	var result: String = CHECK.judge_view(room, stations, look, "choosing", worst)
	for id: String in stations.ids:
		if result != "":
			break
		STATIONS_TEST._use(stations, id)
		stations.advance(HubStations.SETTLE_SECONDS)
		result = CHECK.judge_view(room, stations, look, id, worst)
	if result == "" and is_inf(float(worst["px"])):
		result = "no words were measured"
	STATIONS_TEST._free(stations)
	return result


func test_a_small_font_fails_the_size_floor() -> String:
	var look: Dictionary = HubScreenLook.load_file().duplicate()
	look["row_font_size"] = 16.0
	var room: HubRoom = HubRoom.new()
	var stations: HubStations = HubStations.new(room, HubPanelLook.load_file(), look)
	room.add_child(stations)
	stations.open(STATIONS_TEST._hub(STATIONS_TEST._rich_profile()))
	stations.update({})
	STATIONS_TEST._use(stations, "craft")
	stations.advance(HubStations.SETTLE_SECONDS)
	var worst: Dictionary = {"deg": INF, "px": INF, "contrast": INF, "text": "", "where": ""}
	var problem: String = CHECK.judge_view(room, stations, look, "craft", worst)
	room.free()
	return "" if problem.contains("deg") else "16 px rows pass the size floor: \"%s\"" % problem


func test_the_station_in_use_comes_forward_and_goes_back() -> String:
	var stations: HubStations = _open()
	var look: Dictionary = HubScreenLook.load_file()
	var room: Node3D = stations.get_parent() as Node3D
	var room_at: Transform3D = room.transform
	var stations_at: Transform3D = stations.transform
	var resting: float = _eye_distance(stations, "fit")
	STATIONS_TEST._use(stations, "fit")
	var screen: HubStationScreen = stations.screen("fit")
	var half: int = roundi(float(look["focus_seconds"]) * 0.5 / FRAME)
	for i: int in half:
		stations.advance(FRAME)
	var result: String = ""
	if screen.focus() <= 0.2 or screen.focus() >= 0.8:
		result = "half way through %s s the screen is at %.2f" % [look["focus_seconds"], screen.focus()]
	for i: int in half + 2:
		stations.advance(FRAME)
	var near: float = _eye_distance(stations, "fit")
	if result == "" and not is_equal_approx(screen.focus(), 1.0):
		result = "after %s s the screen is at %.2f" % [look["focus_seconds"], screen.focus()]
	if result == "" and absf(resting - near - float(look["focus_forward_m"])) > 0.01:
		result = "the screen came %.3f m nearer, expected %s" % [resting - near, look["focus_forward_m"]]
	if result == "" and not is_equal_approx(screen.scale.x, float(look["focus_scale"])):
		result = "the screen grew to %.2f, expected %s" % [screen.scale.x, look["focus_scale"]]
	if result == "" and stations.screen("craft").focus() != 0.0:
		result = "a station not in use moved"
	if result == "" and (room.transform != room_at or stations.transform != stations_at):
		result = "the room or the stations moved, not only the screen"  # CMF-8
	STATIONS_TEST._tap(stations, DevMenuModel.LEFT)
	stations.advance(HubStations.SETTLE_SECONDS)
	if result == "" and (screen.focus() != 0.0 or absf(_eye_distance(stations, "fit") - resting) > 0.0001):
		result = "left, the screen stays at %.2f" % screen.focus()
	STATIONS_TEST._free(stations)
	return result


func test_the_choice_is_framed() -> String:
	var stations: HubStations = _open()
	var result: String = ""
	for id: String in stations.ids:
		if stations.screen(id).framed() != (id == stations.highlighted_id()):
			result = "while choosing %s, %s is framed: %s" % [stations.highlighted_id(), id, stations.screen(id).framed()]
	STATIONS_TEST._tap(stations, DevMenuModel.RIGHT)
	if result == "" and not stations.screen(stations.highlighted_id()).framed():
		result = "the station stepped to is not framed"
	STATIONS_TEST._use(stations, "logbook")
	for id: String in stations.ids:
		if result == "" and stations.screen(id).framed() != (id == "logbook"):
			result = "with the logbook in use, %s is framed: %s" % [id, stations.screen(id).framed()]
	STATIONS_TEST._free(stations)
	return result


func test_a_screen_shows_at_most_the_rows_in_the_look() -> String:
	var stations: HubStations = _open()
	var shown: int = int(HubScreenLook.load_file()["rows_shown"])
	var result: String = "" if shown <= 5 else "the look shows %d rows, over #1300's five" % shown
	STATIONS_TEST._use(stations, "craft")
	for i: int in 30:
		STATIONS_TEST._tap(stations, DevMenuModel.DOWN)
		var lines: int = stations.texts().size() - 1 - (1 if stations.reason_text() != "" else 0)
		if result == "" and lines > shown:
			result = "the craft station shows %d rows" % lines
	STATIONS_TEST._free(stations)
	return result
