class_name HubBoard
extends RefCounted

## The Crew Quarters and the Logbook as drawn boards (#1368, CRW-1, CRW-2,
## ARC-4): pictures and figures first, words second (#1359). The Crew
## Quarters shows each crew role as a card (its icon, name and count, and what
## it gives as an attribute icon and a number) and, while a ship number's row
## is selected, the ship summary's attributes (#1357) as bars against stock.
## The Logbook shows each counter as a figure with a short caption, and a
## counter that is part of another (a won run of all runs) also as a bar.
##
## The stick still walks the station's rows; each row names the board item it
## stands for (`item`, or a summary row's `owns`), and the board marks that
## item. The drawing is described here as data, laid out by `HubBoardLayout`,
## so `xr/hub_board_view.gd` only draws it. Reads the model and changes
## nothing (MP-2).

const CREW_STATION: String = "crew"
const LOG_STATION: String = "logbook"
const CREW_PREFIX: String = "crew:"
const STATS_PREFIX: String = "stats:"
const CARD: String = "card"
const BAR: String = "bar"
const TILE: String = "tile"


## Whether station `station` draws a board.
static func shows(model: HubModel, station: String) -> bool:
	return station in [CREW_STATION, LOG_STATION] and model.config.boards.has_boards()


## The board item row `row` stands for, or "".
static func item_of(row: Dictionary) -> String:
	return str(row.get("item", row.get("owns", row.get("detail_of", ""))))


## Station `station`'s rows as a board shows them: a crew row loses its note,
## which its card already shows, so the words on the screen stay few (#1300).
static func trim(model: HubModel, station: String, rows: Array[Dictionary]) -> Array[Dictionary]:
	if not shows(model, station):
		return rows
	for row: Dictionary in rows:
		if item_of(row).begins_with(CREW_PREFIX):
			row.erase("note")
	return rows


## What station `station` draws for `rows` (its current rows) with `selected`
## the index of the selected one: {"kind": "board", "text_floor_m", "strip_height_m",
## "icon_size_m", "bar_length_m", "bar_height_m", "tile_height_m", "items": [..]}.
## Each item has `type` ("card", "bar" or "tile"), `id`, `selected` and `at`
## (its middle on the face; a strip spans the face, a tile has `column` of
## `columns`), and:
## - a card: `icon`, `name`, `figure_icon`, `figure`;
## - a bar: `icon`, `figure`, `fill` and `mark` (current and stock, 0..1 of its length);
## - a tile: `figure`, `caption`, and `fill` (0..1), or -1.0 for no bar.
## {} when the station draws no board.
static func drawing(model: HubModel, station: String, rows: Array[Dictionary], selected: int) -> Dictionary:
	if not shows(model, station):
		return {}
	var layout: HubBoardLayout = model.config.boards
	var chosen: String = item_of(rows[selected]) if selected >= 0 and selected < rows.size() else ""
	var items: Array[Dictionary] = []
	if station == LOG_STATION:
		items = _tiles(model, chosen)
	elif chosen.begins_with(HubSummaryRows.OWNS_PREFIX):
		items = _window(layout, _bars(model, chosen))
	else:
		items = _window(layout, _cards(model, chosen))
	return {"kind": "board", "text_floor_m": layout.text_floor_m, "strip_height_m": layout.strip_height_m,
		"icon_size_m": layout.icon_size_m, "bar_length_m": layout.bar_length_m, "bar_height_m": layout.bar_height_m,
		"tile_height_m": layout.tile_height_m, "items": items}


## One card per crew role the profile holds.
static func _cards(model: HubModel, chosen: String) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	for group: Dictionary in model.crew_groups():
		var role: String = group["role"]
		var name: String = group["role_name"] if group["role_name"] != "" else role
		var stat: String = ShipSummary.CREW_SHIP_KEYS.get(group["stat"], group["stat"])
		var id: String = CREW_PREFIX + role
		out.append({"type": CARD, "id": id, "selected": id == chosen, "icon": {"group": "crew", "id": role},
			"name": words.row("crew_capped_row" if group["capped"] else "crew_row", {"role": name, "count": group["count"]}),
			"figure_icon": _attribute(model, stat), "figure": HubSummaryRows.signed(float(group["total"]))})
	return out


## One bar per summary attribute the hub file names (as its rows do).
static func _bars(model: HubModel, chosen: String) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var headroom: float = model.config.boards.bar_headroom
	var out: Array[Dictionary] = []
	for entry: Dictionary in model.summary():
		if HubSummaryRows.value_text(words, entry) == "":
			continue
		var stock: float = entry["stock"]
		var current: float = entry["current"]
		var full: float = maxf(maxf(stock * headroom, current), stock + float(_crew_cap(model, entry["stat"])))
		full = full if full > 0.0 else 1.0
		var figure: String = words.row("summary_value", {"current": HubSummaryRows.number(current),
			"stock": HubSummaryRows.number(stock)}) if entry["ship"] else HubSummaryRows.number(current)
		var id: String = HubSummaryRows.OWNS_PREFIX + str(entry["stat"])
		out.append({"type": BAR, "id": id, "selected": id == chosen, "icon": _attribute(model, entry["stat"]),
			"figure": figure, "fill": clampf(current / full, 0.0, 1.0), "mark": clampf(stock / full, 0.0, 1.0)})
	return out


## One tile per Logbook counter, `tile_columns` to a line.
static func _tiles(model: HubModel, chosen: String) -> Array[Dictionary]:
	var layout: HubBoardLayout = model.config.boards
	var counters: Dictionary = model.stats()
	var out: Array[Dictionary] = []
	for i: int in ProfileStats.KEYS.size():
		var key: String = ProfileStats.KEYS[i]
		var count: int = int(counters.get(key, 0))
		var fill: float = -1.0
		if layout.log_bars.has(key):
			var whole: int = int(counters.get(layout.log_bars[key], 0))
			fill = clampf(float(count) / float(whole), 0.0, 1.0) if whole > 0 else 0.0
		var line: int = i / layout.tile_columns
		out.append({"type": TILE, "id": STATS_PREFIX + key, "selected": STATS_PREFIX + key == chosen,
			"figure": str(count), "caption": layout.log_captions[key], "fill": fill,
			"column": i % layout.tile_columns, "columns": layout.tile_columns,
			"at": Vector2(0.0, layout.top_y_m - layout.tile_height_m * (float(line) + 0.5))})
	return out


## The `strips_visible` strips around the selected one, placed top down.
static func _window(layout: HubBoardLayout, strips: Array[Dictionary]) -> Array[Dictionary]:
	var chosen: int = strips.find_custom(func(each: Dictionary) -> bool: return each["selected"])
	var start: int = maxi(0, chosen - layout.strips_visible + 1)
	var out: Array[Dictionary] = strips.slice(start, start + layout.strips_visible)
	for i: int in out.size():
		out[i]["at"] = Vector2(0.0, layout.top_y_m - layout.strip_height_m * (float(i) + 0.5))
	return out


## The `attribute` icon of summary stat `stat`, or {} when the file names none.
static func _attribute(model: HubModel, stat: String) -> Dictionary:
	var id: String = model.config.boards.attribute_icon(stat)
	return {"group": "attribute", "id": id} if id != "" else {}


## The most the crew may add to summary stat `stat`, or 0.
static func _crew_cap(model: HubModel, stat: String) -> int:
	if model.roles == null or model.roles.error != "":
		return 0
	for crew_stat: String in model.roles.caps():
		if ShipSummary.CREW_SHIP_KEYS.get(crew_stat, crew_stat) == stat:
			return model.roles.cap(crew_stat)
	return 0
