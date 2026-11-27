extends RefCounted

## The crafting moment at the Workbench (#1402, CRF-3, CRW-2, CMF-3, CMF-8,
## ARC-3, ARC-4): a craft through the real stations fills the node over the
## look file's time while the spent components fly in and the item's icon
## grows to rest; the nodes it unlocks glow up from locked without a flash;
## a redraw mid-moment keeps it; reopening the hub does not replay it; and the
## profile and screens are the same with and without it.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const MOMENT_FILE: String = "res://xr/hub_craft_moment.gd"
const FRAME_S: float = 1.0 / 60.0


## The rich profile at the Workbench, its first weapon not yet built.
static func _at_the_bench() -> Array:
	var hub: HubText = Stations._hub(Stations._rich_profile())
	hub.model.parts = HubPartInfo.load_shipped()
	var stations: HubStations = Stations._open(hub)
	Stations._use(stations, HubCraftTree.STATION)
	return [hub, stations, AcceptanceCraftAndFitCheck.first_weapon(hub.model)]


static func _craft(stations: HubStations, hub: HubText, id: String) -> bool:
	return not Stations._press(stations, hub, {"action": HubText.ACTION_CRAFT, "id": id}).is_empty()


static func _part_scale(view: HubTreeView, id: String, part: String) -> float:
	var drawn: Node3D = view.nodes[id].get_node(part)
	return drawn.scale.x if drawn.visible else 0.0


func test_a_craft_fills_the_node_flies_the_components_and_grows_the_item() -> String:
	var opened: Array = _at_the_bench()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var weapon: String = opened[2]
	var view: HubTreeView = stations.tree_view(HubCraftTree.STATION)
	var look: Dictionary = HubScreenLook.load_file()
	var problem: String = ""
	if weapon == "" or view.states.get(weapon, "") != HubTreeView.READY:
		problem = "the rich profile shows no buildable weapon: %s" % [view.states]
	elif not _craft(stations, hub, weapon):
		problem = "no row builds %s" % weapon
	elif not view.moment.running() or view.moment.crafted != weapon:
		problem = "building %s started no moment (%s)" % [weapon, view.moment.crafted]
	elif view.moment.flying_count() == 0:
		problem = "no component icon flies from the cost rows"
	elif _part_scale(view, weapon, "Frame") != 0.0 or _part_scale(view, weapon, "Icon") != 0.0:
		problem = "the node shows built before it fills"
	var fill_s: float = look["craft_fill_seconds"]
	var peak_seen: float = 0.0
	var fills: Array[float] = []
	var t: float = 0.0
	while problem == "" and view.moment.running() and t < 10.0:
		view.advance(FRAME_S)
		t += FRAME_S
		if view.moment.running():
			fills.append(view.moment.fill())
			peak_seen = maxf(peak_seen, view.moment.item_scale())
			if t < float(look["craft_fly_seconds"]) - FRAME_S and view.moment.item_scale() != 0.0:
				problem = "the item shows before the components arrive (%.2f s)" % t
	if problem == "":
		var half: float = fills[int(fill_s * 0.5 / FRAME_S)]
		var whole: float = fills[int(fill_s / FRAME_S) + 1]
		if half <= 0.2 or half >= 0.8 or whole < 1.0:
			problem = "half way the node is %.2f filled, after %.2f s %.2f" % [half, fill_s, whole]
		elif absf(peak_seen - float(look["craft_item_peak"])) > 0.02:
			problem = "the item grew to %.2f, the look asks %.2f" % [peak_seen, look["craft_item_peak"]]
		elif view.moment.get_child_count() != 0 or view.moment.flying_count() != 0:
			problem = "the moment left %d pieces" % view.moment.get_child_count()
		elif view.states[weapon] != HubTreeView.BUILT or _part_scale(view, weapon, "Icon") != 1.0 \
				or _part_scale(view, weapon, "Frame") != 1.0:
			problem = "after the moment %s is not drawn built at rest" % weapon
	Stations._free(stations)
	return problem


func test_unlocked_nodes_glow_up_without_a_flash() -> String:
	var opened: Array = _at_the_bench()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var weapon: String = opened[2]
	var view: HubTreeView = stations.tree_view(HubCraftTree.STATION)
	var look: Dictionary = HubScreenLook.load_file()
	var problem: String = "" if _craft(stations, hub, weapon) else "no row builds %s" % weapon
	var unlocked: Array[String] = view.moment.unlocked.duplicate()
	if problem == "" and unlocked.is_empty():
		problem = "building %s unlocked nothing drawn (%s)" % [weapon, HubCraftTree.children(hub.model, weapon)]
	for id: String in unlocked:
		if problem == "" and (view.states[id] != HubTreeView.READY or _part_scale(view, id, "Frame") != 0.0):
			problem = "%s does not start from looking locked" % id
	var alpha: float = look["unlock_glow_alpha"]
	# Smoothstep's steepest step is 1.5 times the mean step.
	var biggest: float = alpha / (float(look["unlock_glow_seconds"]) / FRAME_S) * 1.6
	var last: float = 0.0
	var top_at: float = -1.0
	var t: float = 0.0
	while problem == "" and view.moment.running():
		view.advance(FRAME_S)
		t += FRAME_S
		var now: float = view.moment.glow_alpha() if view.moment.running() else 0.0
		if absf(now - last) > biggest:
			problem = "the glow jumps %.3f in a frame at %.2f s" % [now - last, t]
		if now > alpha + 0.0001:
			problem = "the glow reaches %.2f, over the look's %.2f" % [now, alpha]
		if top_at < 0.0 and now >= alpha - 0.0001:
			top_at = t - float(look["craft_fill_seconds"])
		last = now
	if problem == "" and (top_at < 0.0 or top_at >= 1.0):
		problem = "the glow took %.2f s to come up, not under 1 s" % top_at
	for id: String in unlocked:
		if problem == "" and (view.states[id] != HubTreeView.READY or _part_scale(view, id, "Frame") != 1.0):
			problem = "%s does not end drawn buildable at rest" % id
	Stations._free(stations)
	return problem


func test_a_redraw_mid_moment_keeps_it_and_reopening_does_not_replay_it() -> String:
	var opened: Array = _at_the_bench()
	var hub: HubText = opened[0]
	var stations: HubStations = opened[1]
	var weapon: String = opened[2]
	var view: HubTreeView = stations.tree_view(HubCraftTree.STATION)
	var problem: String = "" if _craft(stations, hub, weapon) else "no row builds %s" % weapon
	view.advance(0.2)
	Stations._tap(stations, DevMenuModel.DOWN)  # Redraws every node at rest.
	if problem == "" and (not view.moment.running() or view.moment.elapsed != 0.2):
		problem = "a redraw ended or restarted the moment"
	elif problem == "" and view.nodes.has(weapon) and _part_scale(view, weapon, "Icon") != view.moment.item_scale():
		problem = "after a redraw the item's icon is %.2f, the moment says %.2f" % [
			_part_scale(view, weapon, "Icon"), view.moment.item_scale()]
	stations.close()
	view.advance(FRAME_S)
	if problem == "" and view.moment.running():
		problem = "closing the hub did not end the moment"
	stations.open(hub)
	stations.update({})
	Stations._use(stations, HubCraftTree.STATION)
	if problem == "" and view.moment.running():
		problem = "reopening the hub replayed the moment"
	Stations._free(stations)
	return problem


func test_the_profile_and_screens_are_the_same_without_the_moment() -> String:
	var animated: Array = _at_the_bench()
	var plain: Array = _at_the_bench()
	var plain_view: HubTreeView = (plain[1] as HubStations).tree_view(HubCraftTree.STATION)
	plain_view.moments_enabled = false
	var problem: String = ""
	for opened: Array in [animated, plain]:
		if not _craft(opened[1], opened[0], opened[2]):
			problem = "no row builds %s" % opened[2]
	var view: HubTreeView = (animated[1] as HubStations).tree_view(HubCraftTree.STATION)
	var mid: String = (animated[0] as HubText).model.profile.to_json()
	view.advance(HubStations.SETTLE_SECONDS)
	var other: String = (plain[0] as HubText).model.profile.to_json()
	if problem == "" and plain_view.moment.running():
		problem = "a view without moments played one"
	elif problem == "" and (mid != other or (animated[0] as HubText).model.profile.to_json() != other):
		problem = "the profile differs with the moment: %s / %s" % [mid, other]
	elif problem == "" and ((animated[1] as HubStations).texts() != (plain[1] as HubStations).texts() or view.states != plain_view.states):
		problem = "the screens differ with the moment"
	var source: String = FileAccess.get_file_as_string(MOMENT_FILE)
	for banned: String in ["Profile", "Fitting.", "Comfort", "Input.", "HubModel", "HubCraftTree", "HubText", "save("]:
		if problem == "" and source.find(banned) >= 0:
			problem = "%s names %s" % [MOMENT_FILE, banned]
	Stations._free(animated[1])
	Stations._free(plain[1])
	return problem


func test_a_glow_that_comes_up_in_a_second_or_more_is_refused() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubScreenLook.DEFAULT_FILE))
	for each: Array in [["unlock_glow_seconds", 1.0], ["craft_fill_seconds", 0.0], ["unlock_glow_color", [1.0, 2.0, 0.0]]]:
		var data: Dictionary = shipped.duplicate(true)
		data[each[0]] = each[1]
		if not str(HubScreenLook.parse(JSON.stringify(data)).get("error", "")).contains(each[0]):
			return "%s = %s is not refused" % each
	return ""
