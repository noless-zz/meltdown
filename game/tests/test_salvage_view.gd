extends RefCounted

## Floating salvage drawn as placeholder shapes (SLV-1, LGT-1, ARC-4): one mesh
## per item at the blended position, a view-only spin, pooled nodes, a look
## per part from data covering every part in the salvage catalogue, glowing, and never
## sharing a shape and colour with a robot.

const WEAPONS_DIR: String = "res://data/weapons"
const SCRIPT_PATH: String = "res://view/salvage_view.gd"
const OUTSIDE_DIRS: Array[String] = ["res://xr", "res://meta", "res://net"]
const EPSILON: float = 1e-4


func _valid_entry() -> Dictionary:
	return {"shape": "torus", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5]}


func _valid_look() -> Dictionary:
	return {"default": _valid_entry(), "parts": {"pulse_cannon": _valid_entry()}}


func _hashes(items: Array[SalvageItem]) -> Array[int]:
	var out: Array[int] = []
	for item: SalvageItem in items:
		out.append(item.state_hash())
	return out


func test_items_are_drawn_at_the_blended_positions_and_not_changed() -> String:
	var view: SalvageView = SalvageView.new()
	var previous: Array[SalvageItem] = [
		SalvageItem.new("pulse_cannon", Vector3(0, 0, 0), Vector3(0, 0, -6)),
		SalvageItem.new("needle_gun", Vector3(5, 0, 0)),
		SalvageItem.new("slug_thrower", Vector3(-5, 1, 0), Vector3(1.2, 0, 0)),
	]
	var current: Array[SalvageItem] = [
		SalvageItem.new("pulse_cannon", Vector3(0, 0, -0.1), Vector3(0, 0, -5.8)),
		SalvageItem.new("needle_gun", Vector3(5, 0, 0)),
		SalvageItem.new("slug_thrower", Vector3(-4.98, 1, 0), Vector3(1.16, 0, 0)),
	]
	var before: Array[int] = _hashes(previous) + _hashes(current)
	view.show_salvage(previous, current, 0.25)
	var result: String = ""
	var shown: int = 0
	for index: int in view.node_count():
		if view.node(index).visible:
			shown += 1
	if shown != 3 or view.node_count() != 3:
		result = "%d of %d meshes visible for 3 items" % [shown, view.node_count()]
	for index: int in 3:
		var want: Vector3 = previous[index].position.lerp(current[index].position, 0.25)
		var got: Vector3 = view.node(index).position
		if result == "" and got.distance_to(want) > EPSILON:
			result = "item %d drawn at %s, expected %s" % [index, got, want]
	if result == "" and _hashes(previous) + _hashes(current) != before:
		result = "show_salvage changed the items"
	var size: float = view.node(2).transform.basis.get_scale().x
	var want_size: float = SalvageItem.RADIUS * float(view.look_for("slug_thrower")["scale"])
	if result == "" and absf(size - want_size) > EPSILON:
		result = "slug thrower drawn at scale %s, expected %s" % [size, want_size]
	view.free()
	return result


func test_items_spin_in_the_view_only() -> String:
	var view: SalvageView = SalvageView.new()
	var items: Array[SalvageItem] = [SalvageItem.new("arc_lance", Vector3(1, 2, 3))]
	var before: Array[int] = _hashes(items)
	view.show_salvage(items, items, 1.0)
	var first: Basis = view.node(0).transform.basis
	view.advance_spin(0.5)
	view.show_salvage(items, items, 1.0)
	var second: Basis = view.node(0).transform.basis
	var result: String = ""
	if first.is_equal_approx(second):
		result = "the item did not turn after half a second"
	elif _hashes(items) != before:
		result = "spinning changed the item"
	elif view.node(0).position.distance_to(items[0].position) > EPSILON:
		result = "spinning moved the item to %s" % view.node(0).position
	var turned: float = absf(angle_difference(0.0, view.spin_angle))
	if result == "" and absf(turned - SalvageView.SPIN_RADIANS_PER_SECOND * 0.5) > EPSILON:
		result = "spun %s rad in 0.5 s, expected %s" % [turned, SalvageView.SPIN_RADIANS_PER_SECOND * 0.5]
	if result == "" and (SalvageView.SPIN_RADIANS_PER_SECOND <= 0.0 or SalvageView.SPIN_RADIANS_PER_SECOND > PI):
		result = "spin of %s rad/s is not slow" % SalvageView.SPIN_RADIANS_PER_SECOND
	view.free()
	return result


func test_a_picked_up_item_is_hidden_and_nodes_are_pooled() -> String:
	var view: SalvageView = SalvageView.new()
	var three: Array[SalvageItem] = [
		SalvageItem.new("pulse_cannon", Vector3(0, 0, 0)),
		SalvageItem.new("needle_gun", Vector3(4, 0, 0)),
		SalvageItem.new("needle_gun", Vector3(8, 0, 0)),
	]
	view.show_salvage(three, three, 0.5)
	var ids: Array[int] = []
	for index: int in view.node_count():
		ids.append(view.node(index).get_instance_id())
	# The middle item was taken: the array shifts down by one, and the item now
	# at index 1 is the same part type as the one that was there.
	var two: Array[SalvageItem] = [three[0], three[2]]
	view.show_salvage(three, two, 0.5)
	var result: String = ""
	if view.node_count() != 3 or view.get_child_count() != 3:
		result = "pool changed size: %d nodes, %d children" % [view.node_count(), view.get_child_count()]
	for index: int in 3:
		if result == "" and view.node(index).get_instance_id() != ids[index]:
			result = "node %d was replaced" % index
	if result == "" and view.node(2).visible:
		result = "the taken item's mesh is still visible"
	if result == "" and view.node(1).position.distance_to(three[2].position) > EPSILON:
		result = "shifted item drawn at %s, expected %s" % [view.node(1).position, three[2].position]
	view.show_salvage(two, [] as Array[SalvageItem], 0.5)
	for index: int in 3:
		if result == "" and view.node(index).visible:
			result = "node %d visible with no salvage" % index
	view.free()
	return result


## Only weapons that can be dropped need a look: crafted-only weapons stay out
## of the salvage catalogue (#1105), so that is the list to cover.
func test_shipped_look_covers_every_salvage_part() -> String:
	var view: SalvageView = SalvageView.new()
	var result: String = view.look_error
	var weapon_ids: Array[String] = []
	weapon_ids.assign(SpawnLoader.load_parts(WEAPONS_DIR).keys())
	if result == "" and weapon_ids.is_empty():
		result = "no salvage parts found"
	for id: String in weapon_ids:
		if result == "" and not view.looked_ids().has(id):
			result = "salvage_look.json has no entry for part \"%s\"" % id
	view.free()
	return result


func test_salvage_glows_and_never_looks_like_a_robot() -> String:
	var view: SalvageView = SalvageView.new()
	var robots: RobotView = RobotView.new()
	var result: String = robots.look_error
	var robot_pairs: Dictionary = {}
	for id: String in robots.looked_ids() + [""]:
		var look: Dictionary = robots.look_for(id)
		robot_pairs["%s %s" % [look["shape"], look["emission_color"]]] = id
	var items: Array[SalvageItem] = []
	for id: String in view.looked_ids() + ["no_such_part"]:
		var look: Dictionary = view.look_for(id)
		var pair: String = "%s %s" % [look["shape"], look["emission_color"]]
		if result == "" and robot_pairs.has(pair):
			result = "part \"%s\" looks like robot \"%s\" (%s)" % [id, robot_pairs[pair], pair]
		items.append(SalvageItem.new(id, Vector3(items.size() * 3.0, 0, 0)))
	view.show_salvage(items, items, 1.0)
	for index: int in items.size():
		var material: StandardMaterial3D = _glow_of(view.node(index))
		if result == "" and (material == null or not material.emission_enabled):
			result = "part \"%s\" is not emissive" % items[index].part_id
		elif result == "" and material.emission.get_luminance() < 0.3:
			result = "part \"%s\" glows too dimly to read in the dark" % items[index].part_id
	view.free()
	robots.free()
	return result


## The glowing material of a drawn part: its single mesh's, or, for a part
## drawn as a model (#1308), the glow pieces'.
static func _glow_of(node: MeshInstance3D) -> StandardMaterial3D:
	if node.mesh != null:
		return node.mesh.material as StandardMaterial3D
	var model: Node3D = PickupModel.model_of(node)
	if model == null:
		return null
	for piece: Node in model.get_children():
		var material: StandardMaterial3D = (piece as MeshInstance3D).material_override as StandardMaterial3D
		if material != null and material.emission_enabled:
			return material
	return null


func test_unknown_id_uses_the_default_look() -> String:
	var view: SalvageView = SalvageView.new()
	var parsed: Dictionary = SalvageView.parse_look(FileAccess.get_file_as_string(SalvageView.DEFAULT_LOOK_FILE))
	var result: String = ""
	if view.look_for("no_such_part") != parsed["default"]:
		result = "an unknown id did not get the default look"
	view.free()
	return result


func test_bad_look_file_is_rejected_with_the_field_named() -> String:
	var cases: Array[Array] = []
	var bad_shape: Dictionary = _valid_look()
	bad_shape["parts"]["pulse_cannon"]["shape"] = "cone"
	cases.append([bad_shape, "parts.pulse_cannon.shape"])
	var bad_scale: Dictionary = _valid_look()
	bad_scale["parts"]["pulse_cannon"]["scale"] = 9.0
	cases.append([bad_scale, "parts.pulse_cannon.scale"])
	var bool_scale: Dictionary = _valid_look()
	bool_scale["default"]["scale"] = true
	cases.append([bool_scale, "default.scale"])
	var bad_color: Dictionary = _valid_look()
	bad_color["parts"]["pulse_cannon"]["emission_color"] = [1.0, 2.0, 0.0]
	cases.append([bad_color, "parts.pulse_cannon.emission_color"])
	var short_color: Dictionary = _valid_look()
	short_color["default"]["emission_color"] = [1.0, 0.0]
	cases.append([short_color, "default.emission_color"])
	var missing: Dictionary = _valid_look()
	missing["parts"]["pulse_cannon"].erase("scale")
	cases.append([missing, "scale"])
	var extra: Dictionary = _valid_look()
	extra["parts"]["pulse_cannon"]["glow"] = 1.0
	cases.append([extra, "glow"])
	var no_parts: Dictionary = _valid_look()
	no_parts.erase("parts")
	cases.append([no_parts, "parts"])
	if SalvageView.parse_look(JSON.stringify(_valid_look())).has("error"):
		return "the valid look was rejected"
	for case: Array in cases:
		var parsed: Dictionary = SalvageView.parse_look(JSON.stringify(case[0]))
		if not parsed.has("error"):
			return "accepted a look with a bad \"%s\"" % case[1]
		if not String(parsed["error"]).contains(case[1]):
			return "error \"%s\" does not name \"%s\"" % [parsed["error"], case[1]]
	return ""


func test_a_rejected_look_file_falls_back() -> String:
	var view: SalvageView = SalvageView.new()
	var error: String = view.load_look("res://view/no_such_look.json")
	var result: String = ""
	if error == "" or view.look_error != error:
		result = "a missing look file set no error"
	elif not view.looked_ids().is_empty():
		result = "a missing look file kept ids %s" % [view.looked_ids()]
	elif view.look_for("pulse_cannon")["shape"] != SalvageView.FALLBACK_LOOK["shape"]:
		result = "a missing look file did not fall back"
	view.free()
	return result


func test_reads_no_layer_above_core() -> String:
	var source: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	for root: String in OUTSIDE_DIRS:
		for file: String in DirAccess.get_files_at(root) if DirAccess.dir_exists_absolute(root) else PackedStringArray():
			if not file.ends_with(".gd"):
				continue
			var head: String = FileAccess.get_file_as_string("%s/%s" % [root, file]).get_slice("\n", 0)
			if head.begins_with("class_name "):
				var class_id: String = head.trim_prefix("class_name ").strip_edges()
				var found: RegEx = RegEx.create_from_string("\\b%s\\b" % class_id)
				if found.search(source) != null:
					return "%s references %s from %s" % [SCRIPT_PATH, class_id, root]
	return ""
