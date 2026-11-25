class_name HubText
extends RefCounted

## The hub as lines of text with a selected row (CRW-2, CRF-3, CRF-4, #1058), so
## a hub panel only draws lines: stick up and down calls `move`, left and right
## `turn_page`, A `press`. Every word comes from `data/hub/hub.json` through the
## model's `HubConfig` (ARC-4, NAM-3); names from other data files (upgrade,
## component, role and weapon names) are shown as those files give them, never
## their ids (#1317).
##
## `press` acts only through the `HubModel`, so it changes the profile and the
## fitting and nothing else (MP-2); saving them stays the caller's job.
##
## In the home base room (#1299) each station shows a part of the pages: while
## `station` names one, the rows are its pages' rows (`HubStationPages`), kept to
## the station's row group, and the same `move`, `selected` and `press` act on them.
## The rows and their actions are the pages' own, so a station and the flat
## panel cannot disagree on what a row does.
##
## Fewer words on a screen (#1300): a screen shows at most `rows_shown()` rows,
## from `first_shown()`, scrolled so the selected row stays in view, and a row's
## longer explanation (`note()`) only while it is selected.

const ACTION_CRAFT: String = "craft"
const ACTION_FIT: String = "fit"
## Takes an upgrade fitted elsewhere into the row's slot (#1336).
const ACTION_MOVE: String = "move"
const ACTION_LAUNCH: String = "launch"
const ACTION_RESUME: String = "resume"
## Unmounts every fitted upgrade at once (#1357).
const ACTION_STRIP: String = "strip"
## Upgrade kind that fits each slot kind; a kind not listed offers no upgrade.
## A part slot (#1094) takes only upgrades of its own kind.
const FITS: Dictionary[String, String] = {"primary": "weapon", "utility": "module",
	"shield": "shield", "hull": "hull", "engine": "engine"}

var model: HubModel
## Index into `model.pages()` of the page shown.
var page: int = 0
## Index among the current page's selectable rows; -1 when it has none.
var row: int = 0
## The station in use (a key of `HubStationPages.STATIONS`), or "" for the pages.
var station: String = ""
## The loadout section the last successful launch press gave; {} before one.
var launched: Dictionary = {}
## The action the last successful resume press gave (`{"resume": true}`); {} before one.
var resumed: Dictionary = {}
## Index into the rows (`lines()` without the title) of the first one shown.
var top: int = 0
## The Fitting Bay's chosen slot (`HubFitBay`, #1366), or "" while picking one.
var fit_slot: String = ""


func _init(p_model: HubModel) -> void:
	model = p_model
	_first_row()


## The current page's id.
func page_id() -> String:
	return model.pages()[page]


## Uses station `id`'s rows from now on and selects its first row; an unknown id
## goes back to the pages.
func choose_station(id: String) -> void:
	station = id if HubStationPages.STATIONS.has(id) else ""
	fit_slot = ""
	_first_row()


## Back from a station to the pages, on the page shown before.
func leave_station() -> void:
	choose_station("")


## The current page (or station): its title, then one line per row.
func lines() -> Array[String]:
	var title_page: String = page_id() if station == "" else str(HubStationPages.STATIONS[station]["pages"][0])
	var out: Array[String] = [model.page_title(title_page)]
	for entry: Dictionary in _rows():
		out.append(entry["text"])
	return out


## Index into `lines()` of the selected row; -1 when nothing can be selected.
func selected_line() -> int:
	var selectable: Array[int] = _selectable()
	if row < 0 or row >= selectable.size():
		return -1
	return selectable[row] + 1


## Moves the selection by `delta` rows, stopping at the first and last.
func move(delta: int) -> void:
	var count: int = _selectable().size()
	row = clampi(row + delta, 0, count - 1) if count > 0 else -1
	_scroll()


## Turns `delta` pages, wrapping, and selects the new page's first row.
func turn_page(delta: int) -> void:
	page = posmod(page + delta, model.pages().size())
	_first_row()


## Rows a screen shows at once (`max_rows_visible` in the hub file).
## Fewer while picking a slot on the bay's drawn ship, so the ship has the face.
func rows_shown() -> int:
	if station == HubFitBay.STATION and fit_slot == "" and model.config.fit_layout.has_ship():
		return model.config.fit_layout.slot_rows_visible
	return model.config.max_rows_visible


## Index into the rows (`lines()` without the title) of the first one shown;
## the selected row is always among the `rows_shown()` from there.
func first_shown() -> int:
	_scroll()
	return top


## The selected row's one line of explanation, or "" when it has none.
func note() -> String:
	var line: int = selected_line()
	return str(_rows()[line - 1].get("note", "")) if line > 0 else ""


## What the selected row does: {"action": "craft", "id"}, {"action": "fit",
## "slot", "id"} ("" empties the slot), {"action": "move", "slot", "id"},
## {"action": "launch"}, {"action": "resume"}, {"action": "strip"}, or {} for a row
## that only shows information.
func selected() -> Dictionary:
	var line: int = selected_line()
	if line < 0:
		return {}
	return (_rows()[line - 1]["action"] as Dictionary).duplicate()


## Performs the selected row's action through the model. Returns the model's
## reason, or "" on success (and for an information row); a refused build gives
## the locked row's words instead of the tree's ids (#1317).
func press() -> String:
	var action: Dictionary = selected()
	var reason: String = ""
	match action.get("action", ""):
		HubFitBay.ACTION_SLOT:
			_select_slot(action["slot"], "")
		ACTION_CRAFT:
			reason = model.craft(action["id"])
			if reason != "" and HubCraftRows.reason(model, action["id"]) != "":
				reason = HubCraftRows.reason(model, action["id"])  # Words, not the tree's ids.
		ACTION_FIT:
			reason = model.fit(action["slot"], action["id"])
		ACTION_MOVE:
			reason = model.move(action["slot"], action["id"])
		ACTION_STRIP:
			reason = model.strip()
		ACTION_LAUNCH:
			reason = model.launch_check()
			if reason == "":
				launched = model.launch()
		ACTION_RESUME:
			var result: Variant = model.resume()
			if typeof(result) == TYPE_DICTIONARY:
				resumed = result
			else:
				reason = str(result)
	if reason == "" and fit_slot != "" and action.get("action", "") in [ACTION_FIT, ACTION_MOVE]:
		_select_slot("", fit_slot)  # Fitted: back on the ship, on the slot just filled.
	move(0)  # The rows may have changed; keep the selection on one.
	return reason


## Stick left with a bay slot chosen: back to the ship, on that slot; false otherwise.
func back() -> bool:
	if fit_slot == "":
		return false
	_select_slot("", fit_slot)
	return true


## The slot at `at` (metres on the bay's drawn ship) while one is picked, or "".
func slot_at(at: Vector2) -> String:
	return HubFitBay.slot_at(model, at) if station == HubFitBay.STATION and fit_slot == "" else ""


## Pointing at `at` selects the slot there (`slot_at`), which it returns.
func point_slot(at: Vector2) -> String:
	var slot: String = slot_at(at)
	if slot != "":
		_select_slot("", slot)
	return slot


## What the station in use draws besides its words (`HubFitBay.drawing`), or {}.
func drawing() -> Dictionary:
	if station != HubFitBay.STATION:
		return {}
	return HubFitBay.drawing(model, fit_slot, _rows(), selected_line() - 1)


## Chooses bay slot `chosen` ("" for none) and selects slot `slot`'s row, or the first.
func _select_slot(chosen: String, slot: String) -> void:
	fit_slot = chosen
	_first_row()
	var index: int = HubFitBay.selectable_index(_rows(), slot)
	if index >= 0:
		row = index
		_scroll()


## Every row of the current page or station: `text`, `action`, whether it is
## `selectable`, and on some Fitting Bay rows a `group`.
## A Workbench upgrade's detail rows (`detail_of`) show only under the selected
## upgrade (#1300); they cannot be selected, so hiding them moves no selection.
## A row with no action id may own detail rows by its `owns` key (#1357).
func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = _page_rows(page_id()) if station == "" else _station_rows()
	var owner: String = ""
	var selectable: int = 0
	for entry: Dictionary in rows:
		if entry["selectable"]:
			if selectable == row:
				owner = str(entry.get("owns", (entry["action"] as Dictionary).get("id", "")))
			selectable += 1
	return rows.filter(func(entry: Dictionary) -> bool: return str(entry.get("detail_of", owner)) == owner)


## The station's pages' rows of its group; a later page starts under its
## title. A station with no row of its group shows the group's empty line.
func _station_rows() -> Array[Dictionary]:
	if station == HubFitBay.STATION:
		return HubFitBay.rows(model, fit_slot)
	var spec: Dictionary = HubStationPages.STATIONS[station]
	var rows: Array[Dictionary] = []
	var pages: Array = spec["pages"]
	for i: int in pages.size():
		var kept: Array[Dictionary] = []
		for entry: Dictionary in _page_rows(str(pages[i])):
			if str(entry.get("group", "")) == str(spec["group"]):
				kept.append(entry)
		if i > 0 and not kept.is_empty():
			rows.append(HubRows.shown(model.page_title(str(pages[i]))))
		rows.append_array(kept)
	if rows.is_empty() and spec["group"] == HubStationPages.GROUP_RESUME:
		rows.append(HubRows.shown(_words().row("resume_none")))
	return rows


func _page_rows(id: String) -> Array[Dictionary]:
	match id:
		HubConfig.CREW:
			return HubRows.crew(model) + HubSummaryRows.rows(model)
		HubConfig.STATS:
			return HubRows.stats(model)
		HubConfig.STORE:
			return HubRows.store(model)
		HubConfig.CRAFT:
			return HubCraftRows.rows(model)  # Costs, numbers and unlocks (#1317).
	return HubFitRows.rows(model)


## Indexes into `_rows()` of the selectable rows.
func _selectable() -> Array[int]:
	var out: Array[int] = []
	var rows: Array[Dictionary] = _rows()
	for i: int in rows.size():
		if rows[i]["selectable"]:
			out.append(i)
	return out


## Selects the first selectable row and shows the top of the rows.
func _first_row() -> void:
	row = 0 if not _selectable().is_empty() else -1
	top = 0
	_scroll()


## Index into the rows (`lines()` without the title) of the selection's last
## row: the selected row, or the last of the detail rows under it as far as a
## window can show them with it (#1357); -1 when nothing is selected.
func selection_end() -> int:
	var rows: Array[Dictionary] = _rows()
	var chosen: int = selected_line() - 1
	var last: int = chosen
	while chosen >= 0 and last + 1 < rows.size() and rows[last + 1].has("detail_of") and last - chosen + 1 < rows_shown():
		last += 1
	return last


## Keeps the selected row in view and, as far as the window allows, the detail
## rows under it, so a fit's before and after is seen with it (#1357).
func _scroll() -> void:
	var selectable: Array[bool] = []
	for entry: Dictionary in _rows():
		selectable.append(bool(entry["selectable"]))
	top = HubWindow.scrolled(top, selected_line() - 1, selectable, rows_shown())
	var last: int = selection_end()
	if last >= top + rows_shown():
		top = last - rows_shown() + 1


func _words() -> HubWords:
	return model.config.words
