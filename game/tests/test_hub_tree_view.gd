extends RefCounted

## The Workbench's tree on its station (#1367, CRF-3, CRW-2, CMF-8, ARC-3,
## MP-2): a node per upgrade in the window, its state as a shape (square frame
## built, round frame ready, smaller and unframed locked), the selected node
## ringed, the edges drawn, icons beside the detail rows, and the aim picking
## a node on the tree.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const VIEW_FILE: String = "res://xr/hub_tree_view.gd"


static func _on_the_bench() -> Array:
	var profile: Profile = Stations._rich_profile()
	var hub: HubText = Stations._hub(profile)
	hub.model.parts = HubPartInfo.load_shipped()
	hub.model.craft("ember_coil")
	var stations: HubStations = Stations._open(hub)
	Stations._use(stations, HubCraftTree.STATION)
	return [hub, stations]


func test_each_state_is_a_shape() -> String:
	var opened: Array = _on_the_bench()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var view: HubTreeView = stations.tree_view(HubCraftTree.STATION)
	var result: String = ""
	if view == null or not view.visible or stations.view(HubCraftTree.STATION) != null:
		result = "the Workbench draws no tree view"
	else:
		var drawing: Dictionary = hub.drawing()
		if view.nodes.size() != (drawing["nodes"] as Array).size() or view.edge_count == 0:
			result = "%d nodes and %d edges drawn for %d nodes" % [view.nodes.size(), view.edge_count, drawing["nodes"].size()]
		for id: String in view.nodes:
			var frame: Node = view.nodes[id].get_node_or_null("Frame")
			var icon: HubIcon = view.nodes[id].get_node("Icon") as HubIcon
			var size: float = drawing["node_size_m"]
			match view.states[id]:
				HubTreeView.BUILT:
					if frame == null or frame.get_child_count() != 4:
						result = "built %s has no square frame" % id
				HubTreeView.READY:
					if not frame is HubIcon:
						result = "ready %s has no round frame" % id
				_:
					if frame != null or icon.size_m >= size:
						result = "locked %s is framed or full size" % id
		var states: Array = view.states.values()
		for each: String in [HubTreeView.BUILT, HubTreeView.READY, HubTreeView.LOCKED]:
			if result == "" and not states.has(each):
				result = "no node drawn %s: %s" % [each, view.states]
		if result == "" and (view.selected_node == "" or view.nodes[view.selected_node].get_node_or_null("Selected") == null):
			result = "no node is ringed as selected"
		if result == "" and view.row_icons.is_empty():
			result = "the detail rows have no icons"
	Stations._free(stations)
	return result


## The rows above the tree stay above it: none is placed below the floor.
func test_the_words_keep_off_the_tree() -> String:
	var opened: Array = _on_the_bench()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var result: String = ""
	var floor_m: float = hub.model.config.craft_tree.text_floor_m
	# The tree's top: the first tier's selection ring.
	var top_node: float = hub.model.config.craft_tree.top_y_m + hub.model.config.craft_tree.node_size_m * HubTreeView.SELECTED_RING * 0.5
	if floor_m > top_node + 0.02 or floor_m < top_node:
		result = "the text floor %s does not sit just over the tree's top %s" % [floor_m, top_node]
	for line: Dictionary in stations.screen(HubCraftTree.STATION).shown_rows():
		if result == "" and float(line["y"]) < floor_m:
			result = "row %d sits at %s, under the floor %s" % [line["row"], line["y"], floor_m]
	Stations._free(stations)
	return result


func test_the_aim_picks_a_node() -> String:
	var opened: Array = _on_the_bench()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	stations.advance(HubStations.SETTLE_SECONDS)
	var room: Node = stations.get_parent()
	var view: HubTreeView = stations.tree_view(HubCraftTree.STATION)
	var target: String = ""
	for id: String in view.nodes:
		if id != view.selected_node:
			target = id
	var spot: Transform3D = HubScreenMeasure.in_space_of(view.nodes[target], room)
	var facing: Vector3 = spot.basis.z.normalized()
	var origin: Vector3 = spot.origin + facing * 0.6
	var result: String = ""
	if stations.point(origin, -facing) != target:
		result = "aiming at %s picked something else" % target
	elif HubCraftTree.selected_node(hub._rows(), hub.selected_line() - 1) != target or view.selected_node != target:
		result = "after aiming at %s the selection is %s, the ring on %s" % [target, hub.selected(), view.selected_node]
	elif stations.point(origin, facing) != "":
		result = "aiming away from the screen picked a node"
	Stations._free(stations)
	return result


func test_the_view_writes_nothing_and_names_no_meta_class() -> String:
	var source: String = FileAccess.get_file_as_string(VIEW_FILE)
	for banned: String in ["Profile", "Fitting.", "ComfortSettings", "Input.", "HubModel", "HubCraftTree", "HubText"]:
		if source.find(banned) >= 0:
			return "%s names %s" % [VIEW_FILE, banned]
	return ""
