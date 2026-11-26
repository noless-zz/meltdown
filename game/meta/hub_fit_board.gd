class_name HubFitBoard
extends RefCounted

## The Fitting Bay's ship summary as drawn bars (#1385, CRF-4, CRW-1, CRW-2,
## GFX-2): pictures first, words second (#1359).
##
## - While the pilot picks a slot and the stick is on a summary row, the ship
##   gives way to the summary's bars, drawn as the Crew Quarters draws them
##   (`HubBoard.bars`): the fill is the current value, a tick marks stock, the
##   number beside them.
## - While a slot is chosen, the selected item's change to each attribute is a
##   pair of bars on one scale, the before over the after, with the stock tick
##   across both and the "Speed 20 to 22" words beside them; those words then
##   leave the rows, so they are said once.
##
## Every value comes from `HubModel.summary()` and `HubModel.preview()` (ARC-3,
## MP-2); sizes and colours from the hub file's `boards` and `fit_bars`
## sections (`HubBoardLayout`, `HubFitBars`). Without both the bay keeps its
## words. The drawing is data in `HubBoard.drawing`'s shape, so
## `xr/hub_board_view.gd` draws it.

const PAIR: String = "pair"
const CHANGE_PREFIX: String = "change:"


## Whether the bay draws its numbers as bars.
static func shows(model: HubModel) -> bool:
	return model.config.fit_bars.has_bars() and model.config.boards.has_boards()


## Rows a screen shows while slot `chosen` is chosen, or -1 when the bars do not change it.
static func rows_shown(model: HubModel, chosen: String) -> int:
	return model.config.fit_bars.compare_rows_visible if chosen != "" and shows(model) else -1


## The bay's item rows without the before and after words the bars draw: the
## first `strips_visible` change rows under each item leave; any more stay as words.
static func trim(model: HubModel, rows: Array[Dictionary]) -> Array[Dictionary]:
	if not shows(model):
		return rows
	var drawn: Dictionary[String, int] = {}
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		if row.has("detail_of"):
			var owner: String = str(row["detail_of"])
			drawn[owner] = drawn.get(owner, 0) + 1
			if drawn[owner] <= model.config.fit_bars.strips_visible:
				continue
		out.append(row)
	return out


## What the bay draws in place of its ship, or under its item rows, for `rows`
## with `selected` the selected one's index: a `HubBoard.drawing`-shaped board
## of summary bars while picking a slot (`chosen` "") on a summary row, of
## change pairs while a slot is chosen and the selected row would change
## something; {} otherwise. A pair item has `icon`, `figure` (its words),
## `before`, `after` and `mark` (0..1 of its length), and the board
## `pair_bar_length_m`, `pair_bar_height_m`, `before_color` and `after_color`.
static func drawing(model: HubModel, chosen: String, rows: Array[Dictionary], selected: int) -> Dictionary:
	if not shows(model) or selected < 0 or selected >= rows.size():
		return {}
	var boards: HubBoardLayout = model.config.boards
	var row: Dictionary = rows[selected]
	if chosen == "":
		var item: String = HubBoard.item_of(row)
		if not item.begins_with(HubSummaryRows.OWNS_PREFIX):
			return {}
		return _board(boards, boards.text_floor_m, boards.strip_height_m, HubBoard.window(boards, HubBoard.bars(model, item)))
	var action: Dictionary = row["action"]
	if not str(action.get("action", "")) in [HubText.ACTION_FIT, HubText.ACTION_MOVE]:
		return {}
	var items: Array[Dictionary] = pairs(model, action)
	if items.is_empty():
		return {}
	var bars: HubFitBars = model.config.fit_bars
	var board: Dictionary = _board(boards, bars.text_floor_m, bars.strip_height_m, items)
	board.merge({"pair_bar_length_m": bars.pair_bar_length_m, "pair_bar_height_m": bars.pair_bar_height_m,
		"before_color": bars.before_color, "after_color": bars.after_color})
	return board


## One pair per attribute fit or move `action` would change and the hub file
## names, at most `strips_visible`, placed top down from `top_y_m`.
static func pairs(model: HubModel, action: Dictionary) -> Array[Dictionary]:
	var bars: HubFitBars = model.config.fit_bars
	var words: HubWords = model.config.words
	var stocks: Dictionary[String, float] = {}
	for entry: Dictionary in model.summary():
		stocks[str(entry["stat"])] = float(entry["stock"])
	var out: Array[Dictionary] = []
	for change: Dictionary in model.preview(action):
		var text: String = HubSummaryRows.change_text(words, change)
		if text == "" or out.size() >= bars.strips_visible:
			continue
		var stat: String = change["stat"]
		var stock: float = stocks.get(stat, 0.0)
		var before: float = change["before"]
		var after: float = change["after"]
		var full: float = maxf(maxf(stock * model.config.boards.bar_headroom, maxf(before, after)),
			stock + float(HubBoard.crew_cap(model, stat)))
		full = full if full > 0.0 else 1.0
		out.append({"type": PAIR, "id": CHANGE_PREFIX + stat, "selected": false, "icon": HubBoard.attribute(model, stat),
			"figure": text, "before": clampf(before / full, 0.0, 1.0), "after": clampf(after / full, 0.0, 1.0),
			"mark": clampf(stock / full, 0.0, 1.0) if change["ship"] else -1.0,
			"at": Vector2(0.0, bars.top_y_m - bars.strip_height_m * (float(out.size()) + 0.5))})
	return out


static func _board(boards: HubBoardLayout, floor_m: float, strip_m: float, items: Array[Dictionary]) -> Dictionary:
	return {"kind": "board", "text_floor_m": floor_m, "strip_height_m": strip_m, "icon_size_m": boards.icon_size_m,
		"bar_length_m": boards.bar_length_m, "bar_height_m": boards.bar_height_m, "tile_height_m": boards.tile_height_m,
		"items": items}
