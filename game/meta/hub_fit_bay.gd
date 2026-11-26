class_name HubFitBay
extends RefCounted

## The Fitting Bay station as a ship with slots (#1366, CRF-4, CRF-5, CMB-1,
## CRW-2): fitting is two choices, never one long list. First the pilot picks a
## slot, on the drawn ship by pointing or with the stick; then one of the items
## that fit it, each shown with its icon and a one-line name, with the before
## and after under the highlighted one (#1357). One item, one slot (#1336): an
## item fitted elsewhere is offered as a move.
##
## These are rows for `HubText`, so the stick, the A press and the window of at
## most `max_rows_visible` rows work as on every other station, and pressing
## goes through the same `HubModel.fit`, `move` and `strip` as the flat panel's
## Fitting Bay page (ARC-3, MP-2). Only the station shows the bay; the flat
## panel keeps `HubFitRows`. The drawing is described here as data, with icons
## named by group and id (`xr/hub_icons.gd` keys), so `xr/` only draws it.

## The station that shows the bay (`HubStationPages.STATIONS`).
const STATION: String = "fit"
## Takes a slot into the choice of what goes in it.
const ACTION_SLOT: String = "slot"
## `HubIcons` group of each upgrade kind; a ship part is drawn by its family.
const ICON_GROUPS: Dictionary[String, String] = {"weapon": "weapon", "module": "utility",
	"shield": "part_family", "hull": "part_family", "engine": "part_family"}


## The station's rows: while no slot is `chosen`, one row per slot (pressing
## it chooses the slot; a slot nothing can go in only shows), the strip row and
## the ship summary; once one is, its name and what it can take.
static func rows(model: HubModel, chosen: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var built: Array[String] = model.crafted()
	if chosen == "":
		for slot: Dictionary in model.fit_slots():
			var line: String = HubFitRows.slot_line(model, slot)
			var offered: bool = not HubFitRows.choices(model, slot, built).is_empty()
			var entry: Dictionary = HubRows.acting(line, {"action": ACTION_SLOT, "slot": slot["slot"]}) if offered else HubRows.info(line)
			entry["slot"] = slot["slot"]
			out.append(entry)
		out.append_array(HubFitRows.strip_rows(model))
		out.append_array(HubSummaryRows.rows(model))
		return out
	var slot: Dictionary = slot_of(model, chosen)
	if slot.is_empty():
		return out
	out.append(HubRows.shown(model.config.words.slot_name(slot["kind"], slot["index"])))
	out.append_array(HubFitBoard.trim(model, HubFitRows.choices(model, slot, built)))  # Bars say them (#1385).
	return out


## The `fit_slots` row of `slot`, or {}.
static func slot_of(model: HubModel, slot: String) -> Dictionary:
	for each: Dictionary in model.fit_slots():
		if each["slot"] == slot:
			return each
	return {}


## The icon of what `slot` (a `fit_slots` row) holds: {"group", "id"}, or {}
## for an empty mark (nothing fitted, or a part slot at stock).
static func slot_icon(model: HubModel, slot: Dictionary) -> Dictionary:
	if slot["upgrade"] != "":
		return upgrade_icon(model, slot["upgrade"])
	if slot["part"] != "":
		return {"group": "weapon", "id": slot["part"]}
	return {}


## The icon of upgrade `id`: its weapon or module by what it grants, a ship
## part by its family; {} for an id the tree does not know.
static func upgrade_icon(model: HubModel, id: String) -> Dictionary:
	if not model.tree.has_upgrade(id):
		return {}
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	var group: String = ICON_GROUPS.get(upgrade.kind, "")
	if group == "":
		return {}
	return {"group": group, "id": upgrade.kind if group == "part_family" else upgrade.grants}


## What the station draws, for `rows` (its current rows) with `selected` the
## index of the selected one: {} when the hub file draws no ship. Otherwise
## {"choosing": bool, "outline": [Vector2], "center_y_m", "slot_size_m",
## "hull_color", "slots": [{"slot", "at", "icon", "selected"}] for each slot
## the file places, "row_icons": one icon ({} for none) per row, and "board":
## the summary's or a mount's bars (`HubFitBoard.drawing`, #1385) or {}}; with
## a board, "text_floor_m" too, so the words stay above it.
static func drawing(model: HubModel, chosen: String, rows: Array[Dictionary], selected: int) -> Dictionary:
	var layout: HubFitLayout = model.config.fit_layout
	if not layout.has_ship():
		return {}
	var picked: String = chosen
	if picked == "" and selected >= 0 and selected < rows.size():
		picked = str(rows[selected].get("slot", ""))
	var slots: Array[Dictionary] = []
	for slot: Dictionary in model.fit_slots():
		var at: Variant = layout.position_of(slot["kind"], slot["index"])
		if at == null:
			continue
		slots.append({"slot": slot["slot"], "at": at, "icon": slot_icon(model, slot), "selected": slot["slot"] == picked})
	var icons: Array[Dictionary] = []
	for entry: Dictionary in rows:
		var action: Dictionary = entry["action"]
		var shows: bool = chosen != "" and str(action.get("id", "")) != ""
		icons.append(upgrade_icon(model, action["id"]) if shows else {})
	var board: Dictionary = HubFitBoard.drawing(model, chosen, rows, selected)
	var out: Dictionary = {"choosing": chosen != "", "outline": layout.outline, "center_y_m": layout.center_y_m,
		"slot_size_m": layout.slot_size_m, "hull_color": layout.hull_color, "slots": slots, "row_icons": icons,
		"board": board}
	if not board.is_empty():
		out["text_floor_m"] = board["text_floor_m"]
	return out


## Index among the selectable `rows` of the one for `slot`, or -1.
static func selectable_index(rows: Array[Dictionary], slot: String) -> int:
	var index: int = 0
	for entry: Dictionary in rows:
		if not entry["selectable"]:
			continue
		if str(entry.get("slot", "")) == slot:
			return index
		index += 1
	return -1


## The slot drawn nearest `at` (a point on the drawing, metres from its
## origin) within the file's pick radius, or "".
static func slot_at(model: HubModel, at: Vector2) -> String:
	var layout: HubFitLayout = model.config.fit_layout
	var best: String = ""
	var best_miss: float = layout.pick_radius_m
	for slot: Dictionary in model.fit_slots():
		var spot: Variant = layout.position_of(slot["kind"], slot["index"])
		if spot != null and (spot as Vector2).distance_to(at) <= best_miss:
			best = slot["slot"]
			best_miss = (spot as Vector2).distance_to(at)
	return best
