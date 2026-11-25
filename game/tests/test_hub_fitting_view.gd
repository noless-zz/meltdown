extends RefCounted

## The Fitting Bay's drawing on its station (#1366, CRF-4, CRW-2, ARC-3, MP-2):
## the ship with a node per slot, the fitted item's icon or an empty ring, the
## selected slot ringed again; item rows with their icons while choosing; the
## aim picking a slot on the ship; and stick left stepping back to the ship
## before it leaves the station.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const Bay: GDScript = preload("res://tests/test_hub_fit_bay.gd")
const VIEW_FILE: String = "res://xr/hub_fitting_view.gd"


static func _on_the_bay() -> Array:
	var hub: HubText = Bay._built_hub()
	hub.leave_station()
	var stations: HubStations = Stations._open(hub)
	Stations._use(stations, HubFitBay.STATION)
	return [hub, stations]


func test_the_ship_draws_every_slot_with_its_icon_or_an_empty_ring() -> String:
	var opened: Array = _on_the_bay()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var view: HubFittingView = stations.view(HubFitBay.STATION)
	var result: String = ""
	if view == null or not view.visible or not view.ship.visible:
		result = "the fit station shows no ship"
	elif view.slot_nodes.size() != hub.model.fit_slots().size():
		result = "the ship draws %d slots, the ship has %d" % [view.slot_nodes.size(), hub.model.fit_slots().size()]
	elif view.selected_slot != str(hub.selected().get("slot", "")):
		result = "the ring is on \"%s\", the stick on %s" % [view.selected_slot, hub.selected()]
	if result == "":
		var icons: HubIcons = HubIcons.load_file()
		for slot: Dictionary in hub.model.fit_slots():
			var drawn: HubIcon = view.slot_nodes[slot["slot"]].get_child(0) as HubIcon
			var icon: Dictionary = HubFitBay.slot_icon(hub.model, slot)
			var parts: int = 1 if icon.is_empty() else (icons.icon(icon["group"], icon["id"])["parts"] as Array).size()
			if drawn == null or drawn.part_count() != parts:
				result = "%s draws %s, expected %d parts" % [slot["slot"], drawn, parts]
				break
	Stations._free(stations)
	return result


func test_choosing_an_item_shows_the_list_with_icons() -> String:
	var opened: Array = _on_the_bay()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	Stations._press(stations, hub, {"action": HubFitBay.ACTION_SLOT, "slot": "primary[0]"})
	var view: HubFittingView = stations.view(HubFitBay.STATION)
	var result: String = ""
	if hub.fit_slot != "primary[0]" or view.ship.visible:
		result = "after choosing primary[0] the bay is on \"%s\", ship shown: %s" % [hub.fit_slot, view.ship.visible]
	elif view.row_icons.is_empty() or view.row_icons.size() > 5:
		result = "the item list draws %d icons" % view.row_icons.size()
	Stations._free(stations)
	return result


func test_the_aim_picks_a_slot_on_the_ship() -> String:
	var opened: Array = _on_the_bay()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	stations.advance(HubStations.SETTLE_SECONDS)
	var room: Node = stations.get_parent()
	var view: HubFittingView = stations.view(HubFitBay.STATION)
	var spot: Transform3D = HubScreenMeasure.in_space_of(view.slot_nodes["engine"], room)
	var facing: Vector3 = spot.basis.z.normalized()
	var origin: Vector3 = spot.origin + facing * 0.6
	var result: String = ""
	if stations.point(origin, -facing) != "engine" or str(hub.selected().get("slot", "")) != "engine":
		result = "aiming at the engine slot selected %s" % [hub.selected()]
	elif view.selected_slot != "engine":
		result = "the ring is on \"%s\" after aiming at the engine" % view.selected_slot
	elif stations.point(origin, facing) != "":
		result = "aiming away from the screen picked a slot"
	Stations._free(stations)
	return result


func test_stick_left_steps_back_to_the_ship_then_leaves() -> String:
	var opened: Array = _on_the_bay()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	Stations._press(stations, hub, {"action": HubFitBay.ACTION_SLOT, "slot": "primary[1]"})
	Stations._tap(stations, DevMenuModel.LEFT)
	var result: String = ""
	if stations.in_use != HubFitBay.STATION or hub.fit_slot != "" or not stations.view(HubFitBay.STATION).ship.visible:
		result = "the first stick left left the station or stayed in the list"
	Stations._tap(stations, DevMenuModel.LEFT)
	if result == "" and stations.in_use != "":
		result = "the second stick left stayed in the station"
	if result == "" and stations.view(HubFitBay.STATION).visible:
		result = "the ship still shows after leaving the station"
	Stations._free(stations)
	return result


func test_the_view_writes_nothing_and_reads_no_comfort() -> String:
	var source: String = FileAccess.get_file_as_string(VIEW_FILE)
	for banned: String in ["Profile", "Fitting.", "ComfortSettings", "Input.", "HubModel"]:
		if source.find(banned) >= 0:
			return "%s names %s" % [VIEW_FILE, banned]
	return ""
