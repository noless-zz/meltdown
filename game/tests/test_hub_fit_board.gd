extends RefCounted

## The Fitting Bay's numbers as bars (#1385, CRF-4, CRW-1, CRW-2, ARC-3,
## ARC-4, MP-2): on a summary row the summary's bars take the ship's place;
## with a slot chosen the selected item's change to each attribute is a pair
## of bars, before over after, on one scale with the stock mark, and its words
## leave the rows. Every value comes from `HubModel.summary()` and `preview()`;
## sizes and colours from the hub file. The drawing is in `test_hub_fit_bars_view.gd`.

const FitBay: GDScript = preload("res://tests/test_hub_fit_bay.gd")


static func _section() -> Dictionary:
	return {"compare_rows_visible": 2, "text_floor_m": 0.0, "top_y_m": 0.0, "strip_height_m": 0.02,
		"strips_visible": 5, "pair_bar_length_m": 0.11, "pair_bar_height_m": 0.0055,
		"before_color": [0.4, 0.4, 0.4], "after_color": [0.8, 0.8, 0.8]}


## The first crafted engine part on `hub` whose mount changes something, and its changes.
static func _engine(hub: HubText) -> Array:
	for id: String in hub.model.crafted():
		if hub.model.tree.get_upgrade(id).kind == "engine":
			var changes: Array[Dictionary] = hub.model.preview({"action": HubText.ACTION_FIT, "slot": "engine", "id": id})
			if not changes.is_empty():
				return [id, changes]
	return ["", []]


## Moves the stick from the top until the selected row is the summary row of `stat`.
static func _on_summary(hub: HubText, stat: String) -> bool:
	hub.move(-1000)
	for i: int in 300:
		var board: Dictionary = hub.drawing().get("board", {})
		for item: Dictionary in board.get("items", []):
			if item["selected"] and item["id"] == HubSummaryRows.OWNS_PREFIX + stat:
				return true
		var line: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == line:
			return false
	return false


func test_the_section_is_read_and_every_bad_key_named() -> String:
	var shipped: HubFitBars = HubConfig.load_shipped().fit_bars
	if not shipped.has_bars():
		return "the shipped hub file draws no bars: %s" % shipped.error
	var good: HubFitBars = HubFitBars.parse(_section())
	if not good.has_bars() or good.strips_visible != 5 or good.before_color != Color(0.4, 0.4, 0.4):
		return "a good section read as %s" % good.error
	for bad: Array in [["strips_visible", 2.5, "whole number"], ["pair_bar_length_m", 9.0, "pair_bar_length_m"],
			["after_color", [2, 0, 0], "after_color"], ["shade", 1, "unknown key \"shade\""]]:
		var section: Dictionary = _section()
		section[bad[0]] = bad[1]
		var parsed: HubFitBars = HubFitBars.parse(section)
		if parsed.has_bars() or not parsed.error.contains(bad[2]):
			return "%s = %s gave \"%s\"" % [bad[0], bad[1], parsed.error]
	var missing: Dictionary = _section()
	missing.erase("before_color")
	if HubFitBars.parse(missing).has_bars():
		return "a section without before_color was read"
	return ""


func test_a_summary_row_shows_the_summary_bars_in_place_of_the_ship() -> String:
	var hub: HubText = FitBay._built_hub()
	if not hub.drawing()["board"].is_empty():
		return "a slot row already draws bars"
	if not _on_summary(hub, "max_shield"):
		return "no summary row draws the shield's bar: %s" % [hub.lines()]
	var board: Dictionary = hub.drawing()["board"]
	var entry: Dictionary = {}
	for each: Dictionary in hub.model.summary():
		if each["stat"] == "max_shield":
			entry = each
	var bar: Dictionary = {}
	for item: Dictionary in board["items"]:
		if item["id"] == "summary:max_shield":
			bar = item
	var full: float = maxf(maxf(float(entry["stock"]) * hub.model.config.boards.bar_headroom, float(entry["current"])),
		float(entry["stock"]) + float(HubBoard.crew_cap(hub.model, "max_shield")))
	if bar.get("type") != HubBoard.BAR or not is_equal_approx(bar["fill"], float(entry["current"]) / full) \
			or not is_equal_approx(bar["mark"], float(entry["stock"]) / full):
		return "the shield bar is %s for %s" % [bar, entry]
	if board["items"].size() > hub.model.config.boards.strips_visible:
		return "%d bars at once" % board["items"].size()
	if hub.drawing().get("text_floor_m") != hub.model.config.boards.text_floor_m:
		return "the words have no floor above the bars"
	return ""


func test_a_mount_shows_before_and_after_as_two_bars_on_one_scale() -> String:
	var hub: HubText = FitBay._built_hub()
	var found: Array = _engine(hub)
	var engine: String = found[0]
	var changes: Array = found[1]
	if engine == "":
		return "no engine part changes anything"
	var mount: Dictionary = {"action": HubText.ACTION_FIT, "slot": "engine", "id": engine}
	FitBay._select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "engine"})
	hub.press()
	if not FitBay._select(hub, mount):
		return "no row mounts %s" % engine
	var items: Array = hub.drawing()["board"].get("items", [])
	if items.size() != changes.size():
		return "%d pairs for %d changes" % [items.size(), changes.size()]
	var stocks: Dictionary = {}
	for entry: Dictionary in hub.model.summary():
		stocks[entry["stat"]] = float(entry["stock"])
	for i: int in changes.size():
		var change: Dictionary = changes[i]
		var pair: Dictionary = items[i]
		var stock: float = stocks[change["stat"]]
		var full: float = maxf(maxf(stock * hub.model.config.boards.bar_headroom, maxf(change["before"], change["after"])),
			stock + float(HubBoard.crew_cap(hub.model, change["stat"])))
		if pair["type"] != HubFitBoard.PAIR or not is_equal_approx(pair["before"], change["before"] / full) \
				or not is_equal_approx(pair["after"], change["after"] / full) or not is_equal_approx(pair["mark"], stock / full):
			return "%s is drawn %s for %s against stock %s" % [change["stat"], pair, change, stock]
		if pair["figure"] != HubSummaryRows.change_text(hub.model.config.words, change):
			return "the pair reads \"%s\"" % pair["figure"]
		if is_equal_approx(pair["before"], pair["after"]):
			return "%s's two bars are the same length" % change["stat"]
	if hub.model.fitting.parts["engine"] != "":
		return "drawing the bars fitted the part"
	return ""


func test_the_bars_take_the_change_words_off_the_rows() -> String:
	var hub: HubText = FitBay._built_hub()
	var found: Array = _engine(hub)
	var mount: Dictionary = {"action": HubText.ACTION_FIT, "slot": "engine", "id": found[0]}
	var words: String = HubSummaryRows.change_text(hub.model.config.words, (found[1] as Array)[0])
	FitBay._select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "engine"})
	hub.press()
	FitBay._select(hub, mount)
	if hub.lines().has(words) or hub.rows_shown() != hub.model.config.fit_bars.compare_rows_visible:
		return "with bars the rows are %s, %d shown" % [hub.lines(), hub.rows_shown()]
	hub.model.config.fit_bars = HubFitBars.new()  # A file without the section keeps its words.
	FitBay._select(hub, mount)
	if not hub.lines().has(words) or not hub.drawing()["board"].is_empty():
		return "without bars the rows are %s" % [hub.lines()]
	return ""


func test_every_mount_fits_its_changes_in_the_strips() -> String:
	var hub: HubText = FitBay._built_hub()
	var most: int = 0
	for slot: Dictionary in hub.model.fit_slots():
		for row: Dictionary in HubFitRows.choices(hub.model, slot, hub.model.crafted()):
			var action: Dictionary = row["action"]
			if str(action.get("id", "")) != "":
				most = maxi(most, HubFitBoard.pairs(hub.model, action).size())
				var said: int = HubSummaryRows.change_rows(hub.model, action).size()
				if said > hub.model.config.fit_bars.strips_visible:
					return "%s changes %d numbers, more than %d strips" % [action, said, hub.model.config.fit_bars.strips_visible]
	return "" if most > 1 else "no mount changes two numbers, so the strips are never tried"


func test_the_bars_change_nothing() -> String:
	var hub: HubText = FitBay._built_hub()
	var profile: String = hub.model.profile.to_json()
	var fitting: String = hub.model.fitting.to_json()
	_on_summary(hub, "max_speed")
	FitBay._select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "engine"})
	hub.press()
	for i: int in 10:
		hub.drawing()
		hub.move(1)
	if hub.model.profile.to_json() != profile or hub.model.fitting.to_json() != fitting:
		return "drawing the bars changed the profile or the fitting"
	return ""
