extends RefCounted

## The board view on the Crew Quarters and Logbook screens (#1368, CRW-1,
## CRW-2, MP-2): it draws what the hub text describes, frames the selected
## item, keeps every word inside the face at the rows' size, and writes nothing.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const Board: GDScript = preload("res://tests/test_hub_board.gd")


static func _on(profile: Profile, station: String) -> Array:
	var hub: HubText = Stations._hub(profile)
	hub.model.parts = HubPartInfo.load_shipped()  # Every ship number gets a bar.
	var stations: HubStations = Stations._open(hub)
	Stations._use(stations, station)
	return [hub, stations]


func test_the_crew_quarters_draws_a_card_per_role_with_the_selection_framed() -> String:
	var opened: Array = _on(Board._crewed(), HubBoard.CREW_STATION)
	var stations: HubStations = opened[1]
	var view: HubBoardView = stations.board_view(HubBoard.CREW_STATION)
	var result: String = ""
	if view == null or not view.visible:
		result = "the Crew Quarters draws no board"
	elif view.items.size() != 4 or view.selected_item != "crew:shield_tech":
		result = "drew %s with %s selected" % [view.items.keys(), view.selected_item]
	elif view.items["crew:shield_tech"].get_node_or_null("Selected") == null:
		result = "the selected card has no frame"
	elif view.items["crew:surveyor"].get_node_or_null("Selected") != null:
		result = "an unselected card is framed"
	elif view.item_texts("crew:shield_tech") != ["Shield Technician ×2", "+10"]:
		result = "the card reads %s" % [view.item_texts("crew:shield_tech")]
	Stations._free(stations)
	return result


func test_bars_and_logbook_figures_are_drawn() -> String:
	var opened: Array = _on(Board._crewed(), HubBoard.CREW_STATION)
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var result: String = ""
	for i: int in 40:
		if stations.board_view(HubBoard.CREW_STATION).selected_item == "summary:max_shield":
			break
		Stations._tap(stations, DevMenuModel.DOWN)
	var view: HubBoardView = stations.board_view(HubBoard.CREW_STATION)
	if view.selected_item != "summary:max_shield":
		result = "the stick never reached the shield's bar"
	elif not is_equal_approx(view.fills["summary:max_shield"], 60.0 / 75.0) \
			or not is_equal_approx(view.marks["summary:max_shield"], 50.0 / 75.0):
		result = "the shield bar is drawn %s against %s" % [view.fills, view.marks]
	Stations._tap(stations, DevMenuModel.LEFT)
	hub.model.profile.stats.runs_started = 4
	hub.model.profile.stats.runs_won = 1
	Stations._use(stations, HubBoard.LOG_STATION)
	var log: HubBoardView = stations.board_view(HubBoard.LOG_STATION)
	if result == "" and (log == null or log.items.size() != ProfileStats.KEYS.size()):
		result = "the Logbook draws %s" % [log.items.keys() if log != null else "nothing"]
	elif result == "" and not is_equal_approx(log.fills.get("stats:runs_won", -1.0), 0.25):
		result = "the won bar is %s" % log.fills
	elif result == "" and log.item_texts("stats:runs_won") != ["1", "Won"]:
		result = "the won figure reads %s" % [log.item_texts("stats:runs_won")]
	Stations._free(stations)
	return result


func test_every_board_word_is_inside_the_face_at_the_row_size() -> String:
	var opened: Array = _on(Board._crewed(), HubBoard.CREW_STATION)
	var stations: HubStations = opened[1]
	var screen: Dictionary = HubScreenLook.load_file()
	var result: String = ""
	for station: String in [HubBoard.CREW_STATION, HubBoard.LOG_STATION]:
		Stations._use(stations, station)
		for step: int in 30:
			var view: HubBoardView = stations.board_view(station)
			var half: Vector2 = stations.screen(station).face_size() * 0.5
			for found: Node in view.find_children("*", "Label3D", true, false):
				var label: Label3D = found
				var width: float = ThemeDB.fallback_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					label.font_size).x * label.pixel_size
				var at: Vector3 = HubScreenMeasure.in_space_of(label, view).origin
				if result == "" and label.font_size != int(screen["row_font_size"]):
					result = "\"%s\" is drawn at %d px" % [label.text, label.font_size]
				var low: float = at.x - width * 0.5
				if label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
					low = at.x if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else at.x - width
				if result == "" and (low < -half.x or low + width > half.x or absf(at.y) > half.y):
					result = "\"%s\" on the %s station runs off the face at %s" % [label.text, station, at]
			Stations._tap(stations, DevMenuModel.DOWN)
	Stations._free(stations)
	return result


func test_the_board_writes_nothing() -> String:
	var opened: Array = _on(Board._crewed(), HubBoard.CREW_STATION)
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var before: String = hub.model.profile.to_json()
	var fitting: Dictionary = hub.model.fitting.to_dict() if hub.model.fitting.has_method("to_dict") else {}
	for station: String in [HubBoard.CREW_STATION, HubBoard.LOG_STATION]:
		Stations._use(stations, station)
		for step: int in 20:
			Stations._tap(stations, DevMenuModel.DOWN if step < 15 else DevMenuModel.CONFIRM)
	var result: String = ""
	if hub.model.profile.to_json() != before:
		result = "using the boards changed the profile"
	elif hub.model.fitting.has_method("to_dict") and hub.model.fitting.to_dict() != fitting:
		result = "using the boards changed the fitting"
	Stations._free(stations)
	return result


## Each drawn part of an item as {"name", "x": [low, high], "y": [low, high]}:
## words by their capital height, icons by their size, bars by their track.
static func _parts(item: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cap: float = float(HubScreenLook.load_file()["cap_height_ratio"])
	for child: Node in item.get_children():
		var at: Vector3 = (child as Node3D).position
		if child is Label3D:
			var label: Label3D = child
			var width: float = ThemeDB.fallback_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.font_size).x * label.pixel_size
			var low: float = at.x - width * 0.5
			if label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
				low = at.x if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else at.x - width
			var half: float = label.font_size * label.pixel_size * cap * 0.5
			out.append({"name": label.text, "x": [low, low + width], "y": [at.y - half, at.y + half]})
		elif child is HubIcon:
			var size: float = (child as HubIcon).size_m * 0.5
			out.append({"name": "icon", "x": [at.x - size, at.x + size], "y": [at.y - size, at.y + size]})
		elif child.name == "Track":
			var scale: Vector3 = (child as Node3D).scale * 0.5
			out.append({"name": "bar", "x": [at.x - scale.x, at.x + scale.x], "y": [at.y - scale.y, at.y + scale.y]})
	return out


func test_nothing_on_a_card_bar_or_figure_overlaps() -> String:
	var opened: Array = _on(Board._crewed(), HubBoard.CREW_STATION)
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	hub.model.profile.stats.runs_started = 6
	hub.model.profile.stats.runs_won = 2
	var result: String = ""
	for station: String in [HubBoard.CREW_STATION, HubBoard.LOG_STATION]:
		Stations._use(stations, station)
		for step: int in 20:
			var view: HubBoardView = stations.board_view(station)
			for id: String in view.items:
				var parts: Array[Dictionary] = _parts(view.items[id])
				for i: int in parts.size():
					for j: int in range(i + 1, parts.size()):
						var a: Dictionary = parts[i]
						var b: Dictionary = parts[j]
						var apart: bool = a["x"][1] <= b["x"][0] or b["x"][1] <= a["x"][0] \
							or a["y"][1] <= b["y"][0] or b["y"][1] <= a["y"][0]
						if result == "" and not apart:
							result = "on %s, \"%s\" overlaps \"%s\"" % [id, a["name"], b["name"]]
			Stations._tap(stations, DevMenuModel.DOWN)
	Stations._free(stations)
	return result
