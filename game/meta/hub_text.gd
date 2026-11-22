class_name HubText
extends RefCounted

## The hub as lines of text with a selected row (CRW-2, CRF-3, CRF-4, #1058), so
## a hub panel only draws lines: stick up and down calls `move`, left and right
## `turn_page`, A `press`. Every word comes from `data/hub/hub.json` through the
## model's `HubConfig` (ARC-4, NAM-3); ids from other data files (upgrade and
## component names, role names, the ship file's part ids) are shown as those
## files give them.
##
## `press` acts only through the `HubModel`, so it changes the profile and the
## fitting and nothing else (MP-2); saving them stays the caller's job.

const ACTION_CRAFT: String = "craft"
const ACTION_FIT: String = "fit"
const ACTION_LAUNCH: String = "launch"
## Upgrade kind that fits each slot kind; a kind not listed offers no upgrade.
## A part slot (#1094) takes only upgrades of its own kind.
const FITS: Dictionary[String, String] = {"primary": "weapon", "utility": "module",
	"shield": "shield", "hull": "hull", "engine": "engine"}

var model: HubModel
## Index into `model.pages()` of the page shown.
var page: int = 0
## Index among the current page's selectable rows; -1 when it has none.
var row: int = 0
## The loadout section the last successful launch press gave; {} before one.
var launched: Dictionary = {}


func _init(p_model: HubModel) -> void:
	model = p_model
	row = 0 if not _selectable().is_empty() else -1


## The current page's id.
func page_id() -> String:
	return model.pages()[page]


## The current page: its title, then one line per row.
func lines() -> Array[String]:
	var out: Array[String] = [model.page_title(page_id())]
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
## "slot", "id"} ("" empties the slot), {"action": "launch"}, or {} for a row
## that only shows information.
func selected() -> Dictionary:
	var line: int = selected_line()
	if line < 0:
		return {}
	return (_rows()[line - 1]["action"] as Dictionary).duplicate()


## Performs the selected row's action through the model. Returns the model's
## reason unchanged, or "" on success (and for an information row).
func press() -> String:
	var action: Dictionary = selected()
	var reason: String = ""
	match action.get("action", ""):
		ACTION_CRAFT:
			reason = model.craft(action["id"])
		ACTION_FIT:
			reason = model.fit(action["slot"], action["id"])
		ACTION_LAUNCH:
			reason = model.launch_check()
			if reason == "":
				launched = model.launch()
	move(0)  # The rows may have changed; keep the selection on one.
	return reason


## Every row of the current page: `text`, `action` and whether it is `selectable`.
func _rows() -> Array[Dictionary]:
	match page_id():
		HubConfig.CREW:
			return _crew_rows()
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


func _crew_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for member: Dictionary in model.crew():
		rows.append(_info(_words().row("crew_row", {"role": member["role_name"] if member["role_name"] != "" else member["role"],
			"amount": member["amount"], "stat": _words().stat_name(member["stat"])})))
	if rows.is_empty():
		rows.append(_shown(model.config.empty_crew))
	return rows


func _store_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for kind: Dictionary in model.store():
		rows.append(_info(_words().row("store_row", {"name": kind["name"], "tier": kind["tier"], "count": kind["count"]})))
	if rows.is_empty():
		rows.append(_shown(model.config.empty_store))
	return rows


func _craft_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ready: Array[String] = model.craftable()
	if not ready.is_empty():
		rows.append(_shown(_words().row("ready_header")))
	for id: String in ready:
		rows.append(_acting(_words().row("ready_row", {"name": _name(id)}), {"action": ACTION_CRAFT, "id": id}))
	var locked: Array[Dictionary] = model.locked()
	if not locked.is_empty():
		rows.append(_shown(_words().row("locked_header")))
	for entry: Dictionary in locked:
		var id: String = entry["id"]
		rows.append(_acting(_words().row("locked_row", {"name": _name(id), "reason": entry["reason"]}),
			{"action": ACTION_CRAFT, "id": id}))
	var built: Array[String] = model.crafted()
	if not built.is_empty():
		rows.append(_shown(_words().row("built_header")))
	for id: String in built:
		rows.append(_info(_words().row("built_row", {"name": _name(id)})))
	return rows


## Each slot with what it holds, the crafted upgrades of its kind it could take,
## and a row to strip a fitted upgrade; then the launch row.
func _fit_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var built: Array[String] = model.crafted()
	for slot: Dictionary in model.fit_slots():
		var fitted: String = _words().row("slot_empty")
		if slot["upgrade"] != "":
			fitted = _words().row("slot_upgrade", {"name": _name(slot["upgrade"])})
		elif slot["part"] != "":
			fitted = _words().row("slot_part", {"part": slot["part"]})
		elif Fitting.PART_KEYS.has(slot["kind"]):
			fitted = _words().row("slot_stock")
		rows.append(_info(_words().row("slot_row", {"slot": _words().slot_name(slot["kind"], slot["index"]), "fitted": fitted})))
		for id: String in built:
			if id != slot["upgrade"] and model.tree.get_upgrade(id).kind == FITS.get(slot["kind"], ""):
				rows.append(_acting(_words().row("fit_option_row", {"name": _name(id)}),
					{"action": ACTION_FIT, "slot": slot["slot"], "id": id}))
		if slot["upgrade"] != "":
			rows.append(_acting(_words().row("clear_row"), {"action": ACTION_FIT, "slot": slot["slot"], "id": ""}))
	rows.append(_acting(_words().row("launch_row"), {"action": ACTION_LAUNCH}))
	return rows


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


## A header or empty-page text, skipped by the selection.
static func _shown(text: String) -> Dictionary:
	return {"text": text, "action": {}, "selectable": false}
