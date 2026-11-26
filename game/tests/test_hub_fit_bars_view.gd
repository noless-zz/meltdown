extends RefCounted

## The Fitting Bay's bars on its station screen (#1385, CRF-4, CRW-2, MP-2,
## ARC-3): the summary's bars take the ship's place on a summary row, a
## mount's before and after are two bars under the item rows, every word stays
## inside the face at the rows' size and clear of the rows, no part of a strip
## overlaps another, and drawing writes nothing.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const FitBay: GDScript = preload("res://tests/test_hub_fit_bay.gd")
const BoardView: GDScript = preload("res://tests/test_hub_board_view.gd")
const FitBoard: GDScript = preload("res://tests/test_hub_fit_board.gd")


## A bay station whose profile has built every part, in use.
static func _bay() -> Array:
	var hub: HubText = FitBay._built_hub()
	var stations: HubStations = Stations._open(hub)
	Stations._use(stations, HubFitBay.STATION)
	return [hub, stations]


## Steps the stick down until the bay's view draws a board; false at the foot.
static func _down_to_board(stations: HubStations) -> bool:
	for i: int in 60:
		var view: HubFittingView = stations.view(HubFitBay.STATION)
		if view != null and view.board.visible:
			return true
		Stations._tap(stations, DevMenuModel.DOWN)
	return false


## Chooses the engine slot and steps to the first item whose mount changes something.
static func _on_mount(stations: HubStations, hub: HubText) -> bool:
	var engine: String = FitBoard._engine(hub)[0]
	for i: int in 60:
		if hub.selected() == {"action": HubFitBay.ACTION_SLOT, "slot": "engine"}:
			break
		Stations._tap(stations, DevMenuModel.DOWN)
	Stations._tap(stations, DevMenuModel.CONFIRM)
	for i: int in 30:
		if hub.selected() == {"action": HubText.ACTION_FIT, "slot": "engine", "id": engine}:
			return stations.view(HubFitBay.STATION).board.visible
		Stations._tap(stations, DevMenuModel.DOWN)
	return false


## Each word and part of the board as a problem, or "".
static func _check_board(stations: HubStations) -> String:
	var view: HubFittingView = stations.view(HubFitBay.STATION)
	var screen: Dictionary = HubScreenLook.load_file()
	var half: Vector2 = stations.screen(HubFitBay.STATION).face_size() * 0.5
	for found: Node in view.board.find_children("*", "Label3D", true, false):
		var label: Label3D = found
		var width: float = ThemeDB.fallback_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.font_size).x * label.pixel_size
		var at: Vector3 = HubScreenMeasure.in_space_of(label, view).origin
		var low: float = at.x if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else at.x - width
		var cap: float = label.font_size * label.pixel_size * float(screen["cap_height_ratio"]) * 0.5
		if label.font_size != int(screen["row_font_size"]):
			return "\"%s\" is drawn at %d px" % [label.text, label.font_size]
		if low < -half.x + HubStationScreen.MARGIN_M * 0.5 or low + width > half.x or at.y - cap < -half.y:
			return "\"%s\" runs off the face at %s" % [label.text, at]
	for id: String in view.board.items:
		var parts: Array[Dictionary] = BoardView._parts(view.board.items[id])
		for i: int in parts.size():
			for j: int in range(i + 1, parts.size()):
				var a: Dictionary = parts[i]
				var b: Dictionary = parts[j]
				if not (a["x"][1] <= b["x"][0] or b["x"][1] <= a["x"][0] or a["y"][1] <= b["y"][0] or b["y"][1] <= a["y"][0]):
					return "on %s, \"%s\" overlaps \"%s\"" % [id, a["name"], b["name"]]
	return ""


func test_a_summary_row_draws_bars_in_place_of_the_ship() -> String:
	var opened: Array = _bay()
	var stations: HubStations = opened[1]
	var view: HubFittingView = stations.view(HubFitBay.STATION)
	var result: String = ""
	if view == null or not view.ship.visible or view.board.visible:
		result = "the bay does not open on its ship"
	elif not _down_to_board(stations):
		result = "no row of the bay draws the summary's bars"
	elif view.ship.visible or view.can_point() or view.board.fills.is_empty() \
			or view.board.marks.size() != view.board.fills.size() or not view.board.selected_item.begins_with("summary:"):
		result = "the summary row drew %s, ship shown %s" % [view.board.items.keys(), view.ship.visible]
	else:
		for step: int in 20:
			result = _check_board(stations) if result == "" and view.board.visible else result
			Stations._tap(stations, DevMenuModel.DOWN)
	Stations._free(stations)
	return result


func test_a_mount_draws_before_and_after_under_the_rows() -> String:
	var opened: Array = _bay()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var result: String = ""
	if not _on_mount(stations, hub):
		result = "no engine mount draws bars: %s" % [stations.texts()]
	else:
		var board: HubBoardView = stations.view(HubFitBay.STATION).board
		var changes: Array = FitBoard._engine(hub)[1]
		var stat: String = "change:" + str(changes[0]["stat"])
		var floor_m: float = hub.model.config.fit_bars.text_floor_m
		if board.items.size() != changes.size() or not board.befores.has(stat) or not board.fills.has(stat):
			result = "drew %s for %d changes" % [board.items.keys(), changes.size()]
		elif board.item_texts(stat) != [HubSummaryRows.change_text(hub.model.config.words, changes[0])]:
			result = "the pair reads %s" % [board.item_texts(stat)]
		elif is_equal_approx(board.befores[stat], board.fills[stat]):
			result = "the before and after bars are the same length"
		elif stations.screen(HubFitBay.STATION).shown_rows().any(func(line: Dictionary) -> bool: return line["y"] < floor_m):
			result = "a row is drawn below the bars' floor: %s" % [stations.screen(HubFitBay.STATION).shown_rows()]
		else:
			result = _check_board(stations)
	Stations._free(stations)
	return result


func test_drawing_the_bars_writes_nothing() -> String:
	var opened: Array = _bay()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var profile: String = hub.model.profile.to_json()
	var fitting: String = hub.model.fitting.to_json()
	_down_to_board(stations)
	_on_mount(stations, hub)
	var result: String = ""
	if hub.model.profile.to_json() != profile or hub.model.fitting.to_json() != fitting:
		result = "showing the bars changed the profile or the fitting"
	Stations._free(stations)
	return result
