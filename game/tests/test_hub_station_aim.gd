extends RefCounted

## The home base room's stations, continued from `test_hub_stations.gd` (#1299,
## CRW-2, RUN-8): the hub text's stations are the room's, every page is on a
## station, the right controller's aim picks the station it passes nearest and
## a still hand does not undo a stick step, and each station keeps its rows.

const STATIONS_TEST: GDScript = preload("res://tests/test_hub_stations.gd")
const ORDER: Array[String] = ["crew", "logbook", "craft", "fit", "resume", "launch"]


static func _hub(profile: Profile) -> HubText:
	return STATIONS_TEST._hub(profile)


static func _rich_profile() -> Profile:
	return STATIONS_TEST._rich_profile()


static func _open(hub: HubText) -> HubStations:
	return STATIONS_TEST._open(hub)


static func _free(stations: HubStations) -> void:
	STATIONS_TEST._free(stations)


static func _tap(stations: HubStations, action: String) -> Dictionary:
	return STATIONS_TEST._tap(stations, action)


func test_the_station_ids_match_the_room() -> String:
	var meta_ids: Array = HubStationPages.STATIONS.keys()
	meta_ids.sort()
	var room_ids: Array = HubRoomSpec.STATION_IDS.duplicate()
	room_ids.sort()
	if meta_ids != room_ids:
		return "hub text stations %s, room stations %s" % [meta_ids, room_ids]
	var shown: Array[String] = []
	for id: String in HubStationPages.STATIONS:
		for page: Variant in HubStationPages.STATIONS[id]["pages"]:
			if not shown.has(str(page)):
				shown.append(str(page))
	for page: String in HubConfig.PAGE_IDS:
		if not shown.has(page):
			return "no station shows page %s" % page
	return ""


func test_pointing_picks_the_station_under_the_aim() -> String:
	var room: HubRoom = HubRoom.new()
	var points: Dictionary[String, Vector3] = room.station_points()
	var result: String = ""
	var hand: Vector3 = Vector3(0.2, -0.4, -0.3)
	for id: String in ORDER:
		var picked: String = HubStations.pick(hand, points[id] - hand, points, HubStations.POINT_RADIUS_M)
		if picked != id and result == "":
			result = "aiming at %s picks '%s'" % [id, picked]
	if result == "" and HubStations.pick(hand, Vector3.UP, points, HubStations.POINT_RADIUS_M) != "":
		result = "aiming at the ceiling picks a station"
	if result == "" and HubStations.pick(hand, hand - points["fit"], points, HubStations.POINT_RADIUS_M) != "":
		result = "aiming away from the fit station picks one behind the hand"
	room.free()
	return result


func test_pointing_highlights_and_a_still_hand_keeps_a_stick_step() -> String:
	var stations: HubStations = _open(_hub(Profile.new()))
	var points: Dictionary[String, Vector3] = (stations.get_parent() as HubRoom).station_points()
	var hand: Vector3 = Vector3(0.2, -0.4, -0.3)
	var result: String = ""
	stations.point(hand, points["resume"] - hand)
	if stations.highlighted_id() != "resume":
		result = "pointing at resume highlights %s" % stations.highlighted_id()
	_tap(stations, DevMenuModel.RIGHT)
	stations.point(hand, points["resume"] - hand)
	if result == "" and stations.highlighted_id() != "launch":
		result = "a still hand undid the stick step: %s" % stations.highlighted_id()
	stations.point(hand, Vector3.UP)
	stations.point(hand, points["crew"] - hand)
	_tap(stations, DevMenuModel.CONFIRM)
	if result == "" and stations.in_use != "crew":
		result = "A after pointing at crew used %s" % stations.in_use
	_free(stations)
	return result


func test_the_fit_station_keeps_the_slots_and_the_launch_station_the_launch_row() -> String:
	var hub: HubText = _hub(_rich_profile())
	hub.choose_station("fit")
	for i: int in 200:
		if hub.selected().get("action", "") == HubText.ACTION_LAUNCH:
			return "the fit station offers the launch row"
		var before: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == before:
			break
	if hub.lines()[0] != hub.model.page_title(HubConfig.FIT):
		return "the fit station's title is %s" % hub.lines()[0]
	hub.choose_station("launch")
	if hub.selected() != {"action": HubText.ACTION_LAUNCH} or hub.lines().size() != 2:
		return "the launch station shows %s" % [hub.lines()]
	hub.choose_station("craft")
	if hub.lines()[1] != hub.model.config.words.row("face_locker_row"):  # Its own face since #1413.
		return "the craft station does not open the Parts Locker: %s" % [hub.lines()]
	hub.leave_station()
	if hub.station != "" or hub.lines()[0] != hub.model.page_title(hub.page_id()):
		return "leaving the station did not go back to the pages"
	return ""
