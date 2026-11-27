class_name HubLocker
extends RefCounted

## The Parts Locker as the Workbench's second face (#1413, CRF-1, CRF-3,
## CRW-2, ARC-4): each component kind the bank holds as its icon (#1365) with
## its count, and for the selected one which robots drop it (by their shown
## names, from the robot files) and which upgrades spend it, those the bank can
## build now first and marked. The Workbench shares its face between the tree
## and the locker: one row at the top switches them (`switch_row`), chosen with
## the stick like every other row; the tree stays the default face.
##
## Rows for `HubText` and a drawing as data, so `xr/hub_tree_view.gd` only
## draws it. Reads the model and changes nothing: switching faces is the hub
## text's own state, never the profile's or the fitting's (ARC-3, MP-2).

## The station with the two faces (`HubStationPages.STATIONS`).
const STATION: String = "craft"
const TREE: String = "tree"
const LOCKER: String = "locker"
## A component's row and tile id: this prefix and the component id.
const ITEM_PREFIX: String = "part:"
## The board item type of a component tile.
const PART: String = "part"
## Robot names the "From" line lists before it counts the rest (#1300).
const FROM_SHOWN: int = 2


## Whether station `station` has the Locker face.
static func shows(model: HubModel, station: String) -> bool:
	return station == STATION and model.config.locker.has_locker()


## The row at the top of face `face` that switches to the other face.
static func switch_row(model: HubModel, face: String) -> Dictionary:
	var other: String = LOCKER if face == TREE else TREE
	return HubRows.acting(model.config.words.row("face_locker_row" if other == LOCKER else "face_tree_row"),
		{"action": HubText.ACTION_FACE, "face": other})


## Banked kinds with at least one in the bank, as `HubModel.store` orders
## them; a kind never collected (or all spent) is not shown.
static func kinds(model: HubModel) -> Array[Dictionary]:
	return model.store().filter(func(kind: Dictionary) -> bool: return int(kind["count"]) > 0)


## The Locker face's rows: the switch, then one row per kind with where it
## comes from as its note and the upgrades that spend it as detail rows.
static func rows(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = [switch_row(model, LOCKER)]
	for kind: Dictionary in kinds(model):
		var item: String = ITEM_PREFIX + str(kind["id"])
		var row: Dictionary = HubRows.noted(HubRows.info(words.row("store_row", {"name": kind["name"],
			"count": kind["count"]})), from_line(model, str(kind["id"])))
		row["owns"] = item
		row["item"] = item
		out.append(row)
		out.append_array(uses(model, str(kind["id"])))
	if out.size() == 1:
		out.append(HubRows.noted(HubRows.info(model.config.empty_store), words.row("empty_store_note")))
	return out


## Which robots drop component `id`, by their shown names.
static func from_line(model: HubModel, id: String) -> String:
	var words: HubWords = model.config.words
	var names: Array[String] = model.parts.drops.names(id)
	if names.is_empty():
		return words.row("locker_from_none")
	var listed: String = words.row("list_join").join(names.slice(0, FROM_SHOWN))
	if names.size() <= FROM_SHOWN:
		return words.row("locker_from", {"names": listed})
	return words.row("locker_from_more", {"names": listed, "count": names.size() - FROM_SHOWN})


## Upgrade ids not yet built whose cost names component `id`: those the bank
## can build now first, each part in `HubModel.ordered_upgrades` order.
static func spenders(model: HubModel, id: String) -> Array[String]:
	var ready: Array[String] = []
	var later: Array[String] = []
	for upgrade: UpgradeDef in model.ordered_upgrades():
		if upgrade.cost.has(id) and not model.profile.crafted.has(upgrade.id):
			if HubCraftTree.state(model, upgrade.id) == HubCraftTree.READY:
				ready.append(upgrade.id)
			else:
				later.append(upgrade.id)
	return ready + later


## Component `id`'s detail rows: at most `uses_shown`, one per upgrade that
## spends it, with its icon and `ready` set (and other words) when it can be
## built now; a last row counts those left out.
static func uses(model: HubModel, id: String) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var item: String = ITEM_PREFIX + id
	var ids: Array[String] = spenders(model, id)
	if ids.is_empty():
		return [_detail(words.row("store_unused"), item)]
	var room: int = model.config.locker.uses_shown
	var named: int = ids.size() if ids.size() <= room else room - 1
	var out: Array[Dictionary] = []
	for upgrade: String in ids.slice(0, named):
		var ready: bool = HubCraftTree.state(model, upgrade) == HubCraftTree.READY
		var row: Dictionary = _detail(words.row("locker_use_ready" if ready else "locker_use",
			{"name": HubCraftRows.upgrade_name(model, upgrade)}), item)
		row["icon"] = HubFitBay.upgrade_icon(model, upgrade)
		row["ready"] = ready
		out.append(row)
	if named < ids.size():
		out.append(_detail(words.row("locker_use_more", {"count": ids.size() - named}), item))
	return out


## What the Locker face draws for `rows` (its current rows) with `selected`
## the index of the selected one: {"kind": "locker", "text_floor_m",
## "row_icons": one icon ({} for none) per row, "board": a `HubBoard.drawing`-
## shaped board of "part" tiles}. A tile has `id`, `selected`, `icon`, `figure`
## (the count), `column` of `columns` and `at`; only the line of tiles holding
## the selected one (else the first) is drawn. {} without the Locker face.
static func drawing(model: HubModel, rows: Array[Dictionary], selected: int) -> Dictionary:
	var layout: HubLockerLayout = model.config.locker
	if not layout.has_locker():
		return {}
	var chosen: String = HubBoard.item_of(rows[selected]) if selected >= 0 and selected < rows.size() else ""
	var held: Array[Dictionary] = kinds(model)
	var line: int = 0
	for i: int in held.size():
		if ITEM_PREFIX + str(held[i]["id"]) == chosen:
			line = i / layout.tile_columns
	var items: Array[Dictionary] = []
	for i: int in range(line * layout.tile_columns, mini(held.size(), (line + 1) * layout.tile_columns)):
		var id: String = ITEM_PREFIX + str(held[i]["id"])
		items.append({"type": PART, "id": id, "selected": id == chosen,
			"icon": {"group": "component", "id": str(held[i]["id"])}, "figure": str(held[i]["count"]),
			"column": i % layout.tile_columns, "columns": layout.tile_columns,
			"at": Vector2(0.0, layout.top_y_m - layout.tile_height_m * 0.5)})
	var icons: Array[Dictionary] = []
	for row: Dictionary in rows:
		icons.append(row.get("icon", {}))
	return {"kind": LOCKER, "text_floor_m": layout.text_floor_m, "row_icons": icons,
		"board": {"kind": "board", "tile_height_m": layout.tile_height_m, "icon_size_m": layout.icon_size_m,
			"items": items}}


static func _detail(text: String, item: String) -> Dictionary:
	var row: Dictionary = HubRows.shown(text)
	row["detail_of"] = item
	return row
