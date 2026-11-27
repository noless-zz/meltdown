extends RefCounted

## The Workbench station as a tech tree (#1367, CRF-3, CRF-6, CRW-2, CMF-8,
## ARC-4): laid out from the upgrade files with no two nodes on top of each
## other, the stick walking along the edges, the three states per profile,
## the selected node's lines one fact each within `max_row_chars`, the window
## scrolling to the selected node, pointing at a node, and building through
## the same `HubModel.craft` as the flat panel. On the shipped data files.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")


static func _on_the_bench(profile: Profile) -> HubText:
	var hub: HubText = Stations._hub(profile)
	hub.model.parts = HubPartInfo.load_shipped()
	hub.choose_station(HubCraftTree.STATION)
	return hub


## Selects node `id` with the stick; false when the stick never reaches it.
static func _select(hub: HubText, id: String) -> bool:
	hub.move(-1000)
	for i: int in 200:
		if HubCraftTree.selected_node(hub._rows(), hub.selected_line() - 1) == id:
			return true
		hub.move(1)
	return false


func test_the_shipped_file_draws_a_tree() -> String:
	var hub: HubText = _on_the_bench(Profile.new())
	var layout: HubTreeLayout = hub.model.config.craft_tree
	if not layout.has_tree() or not HubCraftTree.shows(hub.model, HubCraftTree.STATION):
		return "the shipped hub file draws no tree: %s" % layout.error
	if HubCraftTree.shows(hub.model, HubFitBay.STATION):
		return "the Fitting Bay draws the tree"
	if hub.rows_shown() != layout.rows_visible or hub.drawing().get("kind", "") != "tree":
		return "the Workbench shows %d rows and draws %s" % [hub.rows_shown(), hub.drawing().get("kind", "")]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	data.erase(HubConfig.KEY_CRAFT_TREE)
	var bare: HubConfig = HubConfig.parse_json(JSON.stringify(data))
	if bare.error != "" or bare.craft_tree.has_tree():
		return "a file without craft_tree draws a tree (%s)" % bare.error
	for bad: Variant in [[], {"rows_visible": 3}, 7]:
		data[HubConfig.KEY_CRAFT_TREE] = bad
		if not HubConfig.parse_json(JSON.stringify(data)).error.contains(HubTreeLayout.KEY):
			return "craft_tree %s was accepted" % str(bad)
	return ""


## Every upgrade is a node; no two overlap; each tier is a row, deeper lower;
## every edge runs from an upgrade down to one that needs it.
func test_the_layout_comes_from_the_data_with_no_overlap() -> String:
	var hub: HubText = _on_the_bench(Profile.new())
	var model: HubModel = hub.model
	var layout: HubTreeLayout = model.config.craft_tree
	var placed: Dictionary[String, Vector2] = HubCraftTree.positions(model)
	if placed.size() != model.tree.upgrades.size():
		return "%d nodes for %d upgrades" % [placed.size(), model.tree.upgrades.size()]
	var ids: Array[String] = placed.keys()
	for i: int in ids.size():
		var upgrade: UpgradeDef = model.tree.get_upgrade(ids[i])
		if not is_equal_approx(placed[ids[i]].y, layout.top_y_m - (upgrade.tier - 1) * layout.tier_step_m):
			return "%s (tier %d) sits at y %s" % [ids[i], upgrade.tier, placed[ids[i]].y]
		for need: String in upgrade.requires:
			if placed[need].y <= placed[ids[i]].y:
				return "%s is not above %s, which needs it" % [need, ids[i]]
		for j: int in range(i + 1, ids.size()):
			var apart: Vector2 = (placed[ids[i]] - placed[ids[j]]).abs()
			if apart.x < layout.node_size_m and apart.y < layout.node_size_m:
				return "%s and %s overlap: %s and %s" % [ids[i], ids[j], placed[ids[i]], placed[ids[j]]]
	return ""


## Stepping down from a node that unlocks others goes to the first of them;
## every node comes after the one it first needs; every upgrade is a row.
func test_the_stick_follows_the_edges() -> String:
	var hub: HubText = _on_the_bench(Profile.new())
	var model: HubModel = hub.model
	var order: Array[String] = HubCraftTree.order(model)
	if order.size() != model.tree.upgrades.size():
		return "the walk visits %d of %d upgrades" % [order.size(), model.tree.upgrades.size()]
	for i: int in order.size():
		var upgrade: UpgradeDef = model.tree.get_upgrade(order[i])
		if not upgrade.requires.is_empty() and order.find(upgrade.requires[0]) > i:
			return "%s comes before %s, which it needs" % [order[i], upgrade.requires[0]]
		var kids: Array[String] = HubCraftTree.children(model, order[i])
		if not kids.is_empty() and order[i + 1] != kids[0]:
			return "down from %s goes to %s, not %s" % [order[i], order[i + 1], kids[0]]
	hub.move(-1000)
	hub.move(1)  # Past the face switch at the top (#1413).
	var walked: Array[String] = []
	for i: int in order.size():
		walked.append(HubCraftTree.selected_node(hub._rows(), hub.selected_line() - 1))
		hub.move(1)
	if walked != order:
		return "the stick walks %s, expected %s" % [walked, order]
	return ""


func test_each_node_has_its_state_for_the_profile() -> String:
	var empty: HubText = _on_the_bench(Profile.new())
	for id: String in HubCraftTree.order(empty.model):
		if HubCraftTree.state(empty.model, id) != HubCraftTree.LOCKED:
			return "with nothing banked %s is %s" % [id, HubCraftTree.state(empty.model, id)]
	var hub: HubText = _on_the_bench(Stations._rich_profile())
	var model: HubModel = hub.model
	if model.craft("slug_thrower") != "":
		return "the rich profile cannot build the slug thrower"
	var cases: Dictionary[String, String] = {"slug_thrower": HubCraftTree.BUILT, "drift_mortar": HubCraftTree.READY,
		"needle_gun": HubCraftTree.READY, "arc_lance": HubCraftTree.LOCKED}
	var drawn: Dictionary = {}
	for node: Dictionary in HubCraftTree.drawing(model, HubCraftTree.rows(model), -1)["nodes"]:
		drawn[node["id"]] = node["state"]
	for id: String in cases:
		if HubCraftTree.state(model, id) != cases[id]:
			return "%s is %s, expected %s" % [id, HubCraftTree.state(model, id), cases[id]]
		if drawn.has(id) and drawn[id] != cases[id]:
			return "%s is drawn %s" % [id, drawn[id]]
	return ""


## Every node's row, note and detail lines fit a row, hold one fact each, and
## only the selected node's show; a cost line has its component's icon.
func test_the_selected_nodes_lines_fit_and_carry_icons() -> String:
	for profile: Profile in [Profile.new(), Stations._rich_profile()]:
		var hub: HubText = _on_the_bench(profile)
		var limit: int = hub.model.config.max_row_chars
		for id: String in HubCraftTree.order(hub.model):
			if not _select(hub, id):
				return "the stick never reaches %s" % id
			var lines: Array[String] = hub.lines().slice(1)
			lines.append(hub.note())
			for line: String in lines:
				if line.length() > limit:
					return "\"%s\" under %s has %d characters" % [line, id, line.length()]
			var details: Array[Dictionary] = HubCraftRows.details(hub.model, id)
			var upgrade: UpgradeDef = hub.model.tree.get_upgrade(id)
			if details.size() < upgrade.cost.size() + 1:
				return "%s shows %d detail lines for %d costs and its effect" % [id, details.size(), upgrade.cost.size()]
			var icons: Array = hub.drawing()["row_icons"]
			var shown: Array[Dictionary] = hub._rows()
			for i: int in shown.size():
				if shown[i].has("detail_of") and (shown[i]["detail_of"] != id or (icons[i] as Dictionary).is_empty()):
					return "row \"%s\" shows under %s with icon %s" % [shown[i]["text"], id, icons[i]]
			if (details[0]["icon"] as Dictionary).get("group", "") != "component":
				return "%s's first cost line has no component icon" % id
	return ""


## The window shows the selected node however far along the tree it is,
## draws only the nodes inside it, lights the selected node's edges, and
## cuts edges at its sides.
func test_the_window_scrolls_to_the_selected_node() -> String:
	var hub: HubText = _on_the_bench(Profile.new())
	var model: HubModel = hub.model
	var half: float = model.config.craft_tree.window_m * 0.5
	var order: Array[String] = HubCraftTree.order(model)
	var middles: Array[float] = []
	for id: String in [order[0], order[-1]]:
		_select(hub, id)
		var drawing: Dictionary = hub.drawing()
		var selected: Array = (drawing["nodes"] as Array).filter(func(node: Dictionary) -> bool: return node["selected"])
		if selected.size() != 1 or selected[0]["id"] != id:
			return "with %s selected the drawing selects %s" % [id, selected]
		if (drawing["nodes"] as Array).size() >= order.size():
			return "the window draws all %d nodes; the shipped tree is wider than it" % order.size()
		for node: Dictionary in drawing["nodes"]:
			if absf((node["at"] as Vector2).x) > half + 0.0001:
				return "%s is drawn outside the window at %s" % [node["id"], node["at"]]
		var lit: int = 0
		for edge: Dictionary in drawing["edges"]:
			lit += 1 if edge["lit"] else 0
			for end: Vector2 in [edge["from"], edge["to"]]:
				if absf(end.x) > half + 0.0001:
					return "an edge runs past the window's side to %s" % end
		var expected: int = model.tree.get_upgrade(id).requires.size() + HubCraftTree.children(model, id).size()
		if lit > expected:
			return "%s lights %d edges, it has %d" % [id, lit, expected]
		middles.append(HubCraftTree.window_middle(model, id))
	if middles[0] >= middles[1]:
		return "the window does not move along the tree: %s" % [middles]
	return ""


func test_pointing_at_a_node_selects_it() -> String:
	var hub: HubText = _on_the_bench(Profile.new())
	var nodes: Array = hub.drawing()["nodes"]
	var target: Dictionary = nodes[nodes.size() / 2]
	if hub.point_slot(target["at"]) != target["id"]:
		return "pointing at %s's place picked \"%s\"" % [target["id"], hub.slot_at(target["at"])]
	if HubCraftTree.selected_node(hub._rows(), hub.selected_line() - 1) != target["id"]:
		return "pointing at %s left %s selected" % [target["id"], hub.selected()]
	if hub.slot_at(Vector2(0.0, 0.5)) != "":
		return "pointing off the tree picked a node"
	return ""


## A on a node that can be built builds it through `HubModel.craft`; A on a
## locked one changes nothing and says why in words.
func test_a_builds_through_the_same_code() -> String:
	var profile: Profile = Stations._rich_profile()
	var hub: HubText = _on_the_bench(profile)
	if not _select(hub, "ember_coil") or hub.press() != "" or not profile.crafted.has("ember_coil"):
		return "A on Ember Coil did not build it: %s" % [profile.crafted]
	if profile.count_of("cell_salts") != 17 or HubCraftTree.state(hub.model, "ember_coil") != HubCraftTree.BUILT:
		return "building Ember Coil left %d Cell Salts" % profile.count_of("cell_salts")
	var before: Array[String] = profile.crafted.duplicate()
	_select(hub, "hollow_spike")
	var reason: String = hub.press()
	if reason != HubCraftRows.reason(hub.model, "hollow_spike") or profile.crafted != before:
		return "A on the locked Hollow Spike said \"%s\" and built %s" % [reason, profile.crafted]
	return ""
