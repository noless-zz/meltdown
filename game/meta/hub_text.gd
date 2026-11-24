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


func _init(p_model: HubModel) -> void:
	model = p_model
	row = 0 if not _selectable().is_empty() else -1


## The current page's id.
func page_id() -> String:
	return model.pages()[page]


## Uses station `id`'s rows from now on and selects its first row; an unknown id
## goes back to the pages.
func choose_station(id: String) -> void:
	station = id if HubStationPages.STATIONS.has(id) else ""
	row = 0 if not _selectable().is_empty() else -1


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


## Turns `delta` pages, wrapping, and selects the new page's first row.
func turn_page(delta: int) -> void:
	page = posmod(page + delta, model.pages().size())
	row = 0 if not _selectable().is_empty() else -1


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
func _rows() -> Array[Dictionary]:
	return _page_rows(page_id()) if station == "" else _station_rows()


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
			rows.append(_shown(model.page_title(str(pages[i]))))
		rows.append_array(kept)
	if rows.is_empty() and spec["group"] == HubStationPages.GROUP_RESUME:
		rows.append(_shown(_words().row("resume_none")))
	return rows


func _page_rows(id: String) -> Array[Dictionary]:
	match id:
		HubConfig.CREW:
			return _crew_rows()
		HubConfig.STATS:
			return _stats_rows()
		HubConfig.STORE:
			return _store_rows()
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


## One row per role with how many hold it and the total they give (#1336).
func _crew_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for group: Dictionary in model.crew_groups():
		rows.append(_info(_words().row("crew_capped_row" if group["capped"] else "crew_row", {
			"role": group["role_name"] if group["role_name"] != "" else group["role"], "count": group["count"],
			"amount": group["total"], "stat": _words().stat_name(group["stat"])})))
	if rows.is_empty():
		rows.append(_shown(model.config.empty_crew))
	return rows


## One line per counter, none selectable; above them the empty-profile line
## while every counter is still 0.
func _stats_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var counters: Dictionary = model.stats()
	var any: bool = false
	for key: String in ProfileStats.KEYS:
		any = any or int(counters.get(key, 0)) != 0
	if not any:
		rows.append(_shown(_words().row("stats_empty")))
	for key: String in ProfileStats.KEYS:
		rows.append(_shown(_words().row(HubWords.STATS_ROW_PREFIX + key, {"count": int(counters.get(key, 0))})))
	return rows


func _store_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for kind: Dictionary in model.store():
		rows.append(_info(_words().row("store_row", {"name": kind["name"], "tier": kind["tier"], "count": kind["count"]})))
		rows.append(_shown(ComponentUses.line(_words(), model.ordered_upgrades(), kind["id"])))  # What it is for (#1336).
	if rows.is_empty():
		rows.append(_shown(model.config.empty_store))
	return rows


## The Workbench rows: costs, numbers and unlocks under each upgrade (#1317).
func _craft_rows() -> Array[Dictionary]:
	return HubCraftRows.rows(model)


## Each slot with what it holds, the crafted upgrades of its kind it could take,
## and a row to strip a fitted upgrade. One crafted upgrade is one item (#1336):
## one fitted nowhere is offered as a mount, one fitted in another slot as a
## move that names where it is now. While a suspended run waits, a row to
## resume it (#1106, RUN-8) sits directly above the launch row, so the two ways
## into the mine are side by side (owner's decision, #1172); a note under the
## launch row says launching discards the waiting run.
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
		rows.append(_info(_words().row("slot_row", {"slot": _words().slot_name(slot["kind"], slot["index"]), "fitted": fitted})))
		for id: String in built:
			if id != slot["upgrade"] and model.tree.get_upgrade(id).kind == FITS.get(slot["kind"], ""):
				rows.append(_option(slot["slot"], id))
		if slot["upgrade"] != "":
			rows.append(_acting(_words().row("clear_row"), {"action": ACTION_FIT, "slot": slot["slot"], "id": ""}))
	if not waiting.is_empty():
		rows.append(_grouped(_acting(_words().row("resume_row", waiting), {"action": ACTION_RESUME}),
			HubStationPages.GROUP_RESUME))
	rows.append(_grouped(_acting(_words().row("launch_row"), {"action": ACTION_LAUNCH}),
		HubStationPages.GROUP_LAUNCH))
	if not waiting.is_empty():
		rows.append(_grouped(_shown(_words().row("launch_discard_note")), HubStationPages.GROUP_LAUNCH))
	return rows


## The row offering upgrade `id` for `slot`: a mount, or a move from where it is.
func _option(slot: String, id: String) -> Dictionary:
	var now: String = model.fitting.slot_of(id)
	if now == "":
		return _acting(_words().row("fit_option_row", {"name": _name(id)}), {"action": ACTION_FIT, "slot": slot, "id": id})
	return _acting(_words().row("move_option_row", {"name": _name(id), "from": _words().named_slot(now)}),
		{"action": ACTION_MOVE, "slot": slot, "id": id})


func _words() -> HubWords:
	return model.config.words


## The upgrade's name from its data file, or its id when the tree lacks it.
func _name(id: String) -> String:
	return model.tree.get_upgrade(id).display_name if model.tree.has_upgrade(id) else id


## A row that can be selected but does nothing.
static func _info(text: String) -> Dictionary:
	return {"text": text, "action": {}, "selectable": true}


## A row that takes `action` when pressed.
static func _acting(text: String, action: Dictionary) -> Dictionary:
	return {"text": text, "action": action, "selectable": true}


static func _grouped(entry: Dictionary, group: String) -> Dictionary:
	entry["group"] = group
	return entry


## A header or empty-page text, skipped by the selection.
static func _shown(text: String) -> Dictionary:
	return {"text": text, "action": {}, "selectable": false}
