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
func rows_shown() -> int:
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
## {"action": "launch"}, {"action": "resume"}, or {} for a row
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
		ACTION_CRAFT:
			reason = model.craft(action["id"])
			if reason != "" and HubCraftRows.reason(model, action["id"]) != "":
				reason = HubCraftRows.reason(model, action["id"])  # Words, not the tree's ids.
		ACTION_FIT:
			reason = model.fit(action["slot"], action["id"])
		ACTION_MOVE:
			reason = model.move(action["slot"], action["id"])
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
	move(0)  # The rows may have changed; keep the selection on one.
	return reason


## Every row of the current page or station: `text`, `action`, whether it is
## `selectable`, and on some Fitting Bay rows a `group`.
## A Workbench upgrade's detail rows (`detail_of`) show only under the selected
## upgrade (#1300); they cannot be selected, so hiding them moves no selection.
func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = _page_rows(page_id()) if station == "" else _station_rows()
	var owner: String = ""
	var selectable: int = 0
	for entry: Dictionary in rows:
		if entry["selectable"]:
			if selectable == row:
				owner = str((entry["action"] as Dictionary).get("id", ""))
			selectable += 1
	return rows.filter(func(entry: Dictionary) -> bool: return str(entry.get("detail_of", owner)) == owner)


## The station's pages' rows of its group; a later page starts under its
## title. A station with no row of its group shows the group's empty line.
func _station_rows() -> Array[Dictionary]:
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
			return HubRows.crew(model)
		HubConfig.STATS:
			return HubRows.stats(model)
		HubConfig.STORE:
			return HubRows.store(model)
		HubConfig.CRAFT:
			return _craft_rows()
	return _fit_rows()


## Indexes into `_rows()` of the selectable rows.
func _selectable() -> Array[int]:
	var out: Array[int] = []
	var rows: Array[Dictionary] = _rows()
	for i: int in rows.size():
		if rows[i]["selectable"]:
			out.append(i)
	return out


## The Workbench rows: costs, numbers and unlocks under each upgrade (#1317).
func _craft_rows() -> Array[Dictionary]:
	return HubCraftRows.rows(model)


## Each slot with what it holds, the crafted upgrades of its kind it could take,
## and a row to strip a fitted upgrade. One crafted upgrade is one item (#1336):
## one fitted nowhere is offered as a mount, one fitted in another slot as a
## move that names where it is now. While a suspended run waits, a row to
## resume it (#1106, RUN-8) sits directly above the launch row, so the two ways
## into the mine are side by side (owner's decision, #1172); the launch row's
## note says launching discards the waiting run.
func _fit_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var waiting: Dictionary = model.waiting()
	var built: Array[String] = model.crafted()
	for slot: Dictionary in model.fit_slots():
		var fitted: String = _words().row("slot_empty")
		if slot["upgrade"] != "":
			fitted = _words().row("slot_upgrade", {"name": _name(slot["upgrade"])})
		elif slot["part"] != "":
			var part: String = model.parts.weapon_name(slot["part"])
			fitted = _words().row("slot_part", {"part": part}) if part != "" else _words().row("slot_stock")
		elif Fitting.PART_KEYS.has(slot["kind"]):
			fitted = _words().row("slot_stock")
		rows.append(HubRows.info(_words().row("slot_row", {"slot": _words().slot_name(slot["kind"], slot["index"]), "fitted": fitted})))
		for id: String in built:
			if id != slot["upgrade"] and model.tree.get_upgrade(id).kind == FITS.get(slot["kind"], ""):
				rows.append(_option(slot["slot"], id))
		if slot["upgrade"] != "":
			rows.append(HubRows.acting(_words().row("clear_row"), {"action": ACTION_FIT, "slot": slot["slot"], "id": ""}))
	if not waiting.is_empty():
		rows.append(HubRows.grouped(HubRows.noted(HubRows.acting(_words().row("resume_row", waiting), {"action": ACTION_RESUME}),
			_words().row("resume_note", waiting)), HubStationPages.GROUP_RESUME))
	var launch: Dictionary = HubRows.acting(_words().row("launch_row"), {"action": ACTION_LAUNCH})
	if not waiting.is_empty():
		HubRows.noted(launch, _words().row("launch_discard_note"))
	rows.append(HubRows.grouped(launch, HubStationPages.GROUP_LAUNCH))
	return rows


## The row offering upgrade `id` for `slot`: a mount, or a move whose note
## says where it is now.
func _option(slot: String, id: String) -> Dictionary:
	var now: String = model.fitting.slot_of(id)
	if now == "":
		return HubRows.acting(_words().row("fit_option_row", {"name": _name(id)}), {"action": ACTION_FIT, "slot": slot, "id": id})
	return HubRows.noted(HubRows.acting(_words().row("move_option_row", {"name": _name(id)}),
		{"action": ACTION_MOVE, "slot": slot, "id": id}), _words().row("move_note", {"from": _words().named_slot(now)}))


## Selects the first selectable row and shows the top of the rows.
func _first_row() -> void:
	row = 0 if not _selectable().is_empty() else -1
	top = 0
	_scroll()


func _scroll() -> void:
	var rows: Array[Dictionary] = _rows()
	var selectable: Array[bool] = []
	for entry: Dictionary in rows:
		selectable.append(bool(entry["selectable"]))
	top = HubWindow.scrolled(top, selected_line() - 1, selectable, rows_shown())


func _words() -> HubWords:
	return model.config.words


## The upgrade's name from its data file, or its id when the tree lacks it.
func _name(id: String) -> String:
	return model.tree.get_upgrade(id).display_name if model.tree.has_upgrade(id) else id
