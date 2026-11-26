class_name HubCraftTree
extends RefCounted

## The Workbench station as a drawn tech tree (#1367, CRF-3, CRF-6, CRF-7,
## CRW-2, CMF-8, ARC-4): each upgrade a node with its icon (#1365), an edge
## for each "needs", and three states told apart by shape and frame: built,
## can build now, locked. Laid out from the upgrade files and the hub file's
## `craft_tree` section (`HubTreeLayout`), so a new upgrade file is a new node
## and nothing here changes.
##
## These are rows for `HubText`, one per node in the order `order` walks the
## tree (a node, then what it unlocks, depth first, branch by branch), so the
## stick steps along the edges, and pressing a node goes through the same
## `HubModel.craft` and `Crafting` as the flat panel's Workbench page (MP-2).
## Under the selected node its cost, effect and unlocks show one fact per line
## (`HubCraftRows.details`), each with its icon. The drawing is described here
## as data, so `xr/hub_tree_view.gd` only draws it.

## The station that shows the tree (`HubStationPages.STATIONS`).
const STATION: String = "craft"
const BUILT: String = "built"
const READY: String = "ready"
const LOCKED: String = "locked"
## Room the window keeps beyond the outer nodes' centres, in node sizes.
const EDGE_ROOM: float = 0.5


## Whether station `station` draws the tree.
static func shows(model: HubModel, station: String) -> bool:
	return station == STATION and model.config.craft_tree.has_tree()


## Upgrade ids depth first: branch by branch (`UpgradeDef.BRANCHES`), each
## root by tier then id, then what it unlocks the same way. An upgrade that
## needs several is visited under the first it needs.
static func order(model: HubModel) -> Array[String]:
	var out: Array[String] = []
	for branch: String in UpgradeDef.BRANCHES:
		for upgrade: UpgradeDef in _sorted(model, func(each: UpgradeDef) -> bool:
				return each.branch == branch and (each.requires.is_empty() or not model.tree.has_upgrade(each.requires[0]))):
			_visit(model, upgrade.id, out)
	for upgrade: UpgradeDef in _sorted(model, func(_each: UpgradeDef) -> bool: return true):
		if not out.has(upgrade.id):
			_visit(model, upgrade.id, out)  # A branch outside BRANCHES still shows.
	return out


## The upgrades visited under `id`: those whose first need is `id`.
static func children(model: HubModel, id: String) -> Array[String]:
	var out: Array[String] = []
	for upgrade: UpgradeDef in _sorted(model, func(each: UpgradeDef) -> bool:
			return not each.requires.is_empty() and each.requires[0] == id):
		out.append(upgrade.id)
	return out


## Every node's place in tree metres: x from the first leaf's column, y by tier.
static func positions(model: HubModel) -> Dictionary[String, Vector2]:
	var layout: HubTreeLayout = model.config.craft_tree
	var placed: Dictionary[String, Vector2] = {}
	var column: Array[float] = [0.0]
	var last_branch: Array[String] = [""]
	for id: String in order(model):
		var upgrade: UpgradeDef = model.tree.get_upgrade(id)
		if upgrade.requires.is_empty() or not model.tree.has_upgrade(upgrade.requires[0]):
			_place(model, layout, id, placed, column, last_branch)
	return placed


## "built", "ready" (can build now) or "locked".
static func state(model: HubModel, id: String) -> String:
	if model.profile.crafted.has(id):
		return BUILT
	return READY if model.tree.missing(id, model.profile.crafted, model.profile.banked) == "" else LOCKED


## The station's rows: one per node, with its detail rows under it.
static func rows(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	for id: String in order(model):
		var name: String = HubCraftRows.upgrade_name(model, id)
		var row: Dictionary = {}
		match state(model, id):
			BUILT:
				row = HubRows.info(words.row("built_row", {"name": name}))
			READY:
				row = HubRows.acting(words.row("ready_row", {"name": name}), {"action": HubText.ACTION_CRAFT, "id": id})
			_:
				row = HubRows.acting(words.row("locked_row", {"name": name}), {"action": HubText.ACTION_CRAFT, "id": id})
				row["note"] = words.row("locked_note", {"reason": HubCraftRows.reason(model, id)})
		row["owns"] = id
		row["node"] = id
		out.append(row)
		out.append_array(HubCraftRows.details(model, id))
	return out


## Where the window's middle sits in tree metres, with node `selected` in view.
static func window_middle(model: HubModel, selected: String) -> float:
	var layout: HubTreeLayout = model.config.craft_tree
	var placed: Dictionary[String, Vector2] = positions(model)
	if placed.is_empty():
		return 0.0
	var low: float = INF
	var high: float = -INF
	for at: Vector2 in placed.values():
		low = minf(low, at.x)
		high = maxf(high, at.x)
	var room: float = layout.node_size_m * EDGE_ROOM
	var half: float = layout.window_m * 0.5
	if high - low + room * 2.0 <= layout.window_m:
		return (low + high) * 0.5
	if not placed.has(selected):
		return low - room + half
	return clampf(placed[selected].x, low - room + half, high + room - half)


## What the station draws for `rows` (its current rows) with `selected` the
## index of the selected one: {"kind": "tree", "nodes": [{"id", "at", "icon",
## "state", "selected"}] for the nodes inside the window, "edges": [{"from",
## "to", "lit"}] cut at the window's sides, "node_size_m", "edge_width_m",
## "text_floor_m", "row_icons": one icon ({} for none) per row}. `at` is
## metres on the screen's face. {} when the hub file draws no tree.
static func drawing(model: HubModel, rows: Array[Dictionary], selected: int) -> Dictionary:
	var layout: HubTreeLayout = model.config.craft_tree
	if not layout.has_tree():
		return {}
	var chosen: String = selected_node(rows, selected)
	var placed: Dictionary[String, Vector2] = on_face(model, chosen)
	var half: float = layout.window_m * 0.5
	var nodes: Array[Dictionary] = []
	for id: String in order(model):
		if absf(placed[id].x) <= half + 0.0001:
			nodes.append({"id": id, "at": placed[id], "icon": HubFitBay.upgrade_icon(model, id),
				"state": state(model, id), "selected": id == chosen})
	var edges: Array[Dictionary] = []
	for upgrade: UpgradeDef in model.tree.upgrades:
		for need: String in upgrade.requires:
			var cut: Array = _clip(placed[need], placed[upgrade.id], half)
			if not cut.is_empty():
				edges.append({"from": cut[0], "to": cut[1], "lit": chosen in [need, upgrade.id]})
	var icons: Array[Dictionary] = []
	for row: Dictionary in rows:
		icons.append(row.get("icon", {}))
	return {"kind": "tree", "nodes": nodes, "edges": edges, "node_size_m": layout.node_size_m,
		"edge_width_m": layout.edge_width_m, "text_floor_m": layout.text_floor_m, "row_icons": icons}


## Every node's place on the face with the window scrolled to `selected`.
static func on_face(model: HubModel, selected: String) -> Dictionary[String, Vector2]:
	var middle: float = window_middle(model, selected)
	var placed: Dictionary[String, Vector2] = positions(model)
	for id: String in placed:
		placed[id] = Vector2(placed[id].x - middle, placed[id].y)
	return placed


## The node of the selected row, or of the node row it is a detail of; "".
static func selected_node(rows: Array[Dictionary], selected: int) -> String:
	if selected < 0 or selected >= rows.size():
		return ""
	return str(rows[selected].get("node", rows[selected].get("detail_of", "")))


## The node drawn nearest `at` (metres on the face) within the pick radius,
## with the window scrolled to `selected`; "".
static func node_at(model: HubModel, selected: String, at: Vector2) -> String:
	var layout: HubTreeLayout = model.config.craft_tree
	var best: String = ""
	var best_miss: float = layout.pick_radius_m
	var placed: Dictionary[String, Vector2] = on_face(model, selected)
	for id: String in placed:
		var miss: float = placed[id].distance_to(at)
		if absf(placed[id].x) <= layout.window_m * 0.5 + 0.0001 and miss <= best_miss:
			best = id
			best_miss = miss
	return best


## Index among the selectable `rows` of node `id`'s row, or -1.
static func selectable_index(rows: Array[Dictionary], id: String) -> int:
	var index: int = 0
	for row: Dictionary in rows:
		if not row["selectable"]:
			continue
		if str(row.get("node", "")) == id:
			return index
		index += 1
	return -1


## Places `id` and what it unlocks: a leaf takes the next column, a parent
## sits over the middle of its children.
static func _place(model: HubModel, layout: HubTreeLayout, id: String, placed: Dictionary[String, Vector2],
		column: Array[float], last_branch: Array[String]) -> void:
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	var y: float = layout.top_y_m - float(upgrade.tier - 1) * layout.tier_step_m
	var kids: Array[String] = children(model, id)
	if kids.is_empty():
		if last_branch[0] != "" and last_branch[0] != upgrade.branch:
			column[0] += layout.branch_gap_m
		last_branch[0] = upgrade.branch
		placed[id] = Vector2(column[0], y)
		column[0] += layout.column_step_m
		return
	var low: float = INF
	var high: float = -INF
	for kid: String in kids:
		_place(model, layout, kid, placed, column, last_branch)
		low = minf(low, placed[kid].x)
		high = maxf(high, placed[kid].x)
	placed[id] = Vector2((low + high) * 0.5, y)


static func _visit(model: HubModel, id: String, out: Array[String]) -> void:
	if out.has(id):
		return
	out.append(id)
	for kid: String in children(model, id):
		_visit(model, kid, out)


## The upgrades `keep` accepts, by tier then id.
static func _sorted(model: HubModel, keep: Callable) -> Array[UpgradeDef]:
	var out: Array[UpgradeDef] = []
	for upgrade: UpgradeDef in model.tree.upgrades:
		if keep.call(upgrade):
			out.append(upgrade)
	out.sort_custom(func(a: UpgradeDef, b: UpgradeDef) -> bool: return a.tier < b.tier if a.tier != b.tier else a.id < b.id)
	return out


## The part of the line `a`..`b` with x within -`half`..`half`, or [].
static func _clip(a: Vector2, b: Vector2, half: float) -> Array:
	if (a.x < -half and b.x < -half) or (a.x > half and b.x > half):
		return []
	var from: Vector2 = a
	var to: Vector2 = b
	for edge: float in [-half, half]:
		if (from.x - edge) * (to.x - edge) < 0.0:
			var cut: Vector2 = from.lerp(to, (edge - from.x) / (to.x - from.x))
			if absf(from.x) > half:
				from = cut
			else:
				to = cut
	return [from, to]
