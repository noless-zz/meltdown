extends RefCounted

## The robots drawn as placeholder shapes (CMB-3, MP-2, ARC-4): one mesh per
## robot at the blended pose, pooled nodes, removed robots hidden, a look per
## type from data that covers every robot data file, and a range-checked look
## file whose errors name the field.

const ROBOTS_DIR: String = "res://data/robots"
const SCRIPT_PATH: String = "res://view/robot_view.gd"
const OUTSIDE_DIRS: Array[String] = ["res://xr", "res://meta", "res://net"]
const EPSILON: float = 1e-4


func _def(id: String) -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))


func _robot(id: String, position: Vector3) -> RobotState:
	return RobotState.new(_def(id), position)


func _valid_entry() -> Dictionary:
	return {"shape": "box", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5]}


func _valid_look() -> Dictionary:
	return {"default": _valid_entry(), "robots": {"drone": _valid_entry()}}


func _robot_ids() -> Array[String]:
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			ids.append(_def(file.get_basename()).id)
	return ids


func test_three_robots_are_drawn_at_the_blended_positions() -> String:
	var view: RobotView = RobotView.new()
	var previous: Array[RobotState] = [
		_robot("drone", Vector3(0, 0, 0)), _robot("glider", Vector3(5, 0, 0)), _robot("warden", Vector3(-5, 1, 0)),
	]
	var current: Array[RobotState] = [
		_robot("drone", Vector3(0, 0, -0.1)), _robot("glider", Vector3(5, 0.2, 0)), _robot("warden", Vector3(-5, 1, 0)),
	]
	var before: Array[int] = []
	for robot: RobotState in previous + current:
		before.append(robot.state_hash())
	view.show_robots(previous, current, 0.25)
	var result: String = ""
	var shown: int = 0
	for index: int in view.node_count():
		if view.node(index).visible:
			shown += 1
	if shown != 3 or view.node_count() != 3:
		result = "%d of %d meshes visible for 3 robots" % [shown, view.node_count()]
	for index: int in 3:
		var want: Vector3 = previous[index].position.lerp(current[index].position, 0.25)
		var got: Vector3 = view.node(index).position
		if result == "" and got.distance_to(want) > EPSILON:
			result = "robot %d drawn at %s, expected %s" % [index, got, want]
	var after: Array[int] = []
	for robot: RobotState in previous + current:
		after.append(robot.state_hash())
	if result == "" and after != before:
		result = "show_robots changed the robots"
	var size: float = view.node(1).transform.basis.get_scale().x
	var want_size: float = previous[1].def.radius * float(view.look_for("glider")["scale"])
	if result == "" and absf(size - want_size) > EPSILON:
		result = "glider drawn at scale %s, expected %s" % [size, want_size]
	view.free()
	return result


func test_a_removed_robot_is_hidden_and_nodes_are_pooled() -> String:
	var view: RobotView = RobotView.new()
	var three: Array[RobotState] = [
		_robot("drone", Vector3(0, 0, 0)), _robot("hauler", Vector3(4, 0, 0)), _robot("needler", Vector3(8, 0, 0)),
	]
	view.show_robots(three, three, 0.5)
	var ids: Array[int] = []
	for index: int in view.node_count():
		ids.append(view.node(index).get_instance_id())
	# The middle robot was destroyed: the array shifts down by one.
	var two: Array[RobotState] = [three[0], three[2]]
	view.show_robots(three, two, 0.5)
	var result: String = ""
	if view.node_count() != 3 or view.get_child_count() != 3:
		result = "pool changed size: %d nodes, %d children" % [view.node_count(), view.get_child_count()]
	for index: int in 3:
		if result == "" and view.node(index).get_instance_id() != ids[index]:
			result = "node %d was replaced" % index
	if result == "" and view.node(2).visible:
		result = "the removed robot's mesh is still visible"
	# The needler moved down to index 1; it must not slide from the hauler's spot.
	if result == "" and view.node(1).position.distance_to(three[2].position) > EPSILON:
		result = "shifted robot drawn at %s, expected %s" % [view.node(1).position, three[2].position]
	view.show_robots(two, [] as Array[RobotState], 0.5)
	for index: int in 3:
		if result == "" and view.node(index).visible:
			result = "node %d visible with no robots" % index
	view.free()
	return result


func test_shipped_look_covers_every_robot_data_file() -> String:
	var view: RobotView = RobotView.new()
	var result: String = view.look_error
	var robot_ids: Array[String] = _robot_ids()
	if result == "" and robot_ids.size() < 6:
		result = "only %d robot data files found" % robot_ids.size()
	for id: String in robot_ids:
		if result == "" and not view.looked_ids().has(id):
			result = "robot_look.json has no entry for \"%s\"" % id
	var seen: Dictionary = {}
	for id: String in view.looked_ids():
		var look: Dictionary = view.look_for(id)
		var pair: String = "%s %s" % [look["shape"], look["emission_color"]]
		if result == "" and seen.has(pair):
			result = "\"%s\" and \"%s\" share shape and colour" % [seen[pair], id]
		seen[pair] = id
	view.free()
	return result


func test_unknown_id_uses_the_default_look() -> String:
	var view: RobotView = RobotView.new()
	var parsed: Dictionary = RobotView.parse_look(FileAccess.get_file_as_string(RobotView.DEFAULT_LOOK_FILE))
	var result: String = ""
	if view.look_for("no_such_robot") != parsed["default"]:
		result = "an unknown id did not get the default look"
	view.free()
	return result


func test_bad_look_file_is_rejected_with_the_field_named() -> String:
	var cases: Array[Array] = []
	var bad_shape: Dictionary = _valid_look()
	bad_shape["robots"]["drone"]["shape"] = "torus"
	cases.append([bad_shape, "robots.drone.shape"])
	var bad_scale: Dictionary = _valid_look()
	bad_scale["robots"]["drone"]["scale"] = 9.0
	cases.append([bad_scale, "robots.drone.scale"])
	var bool_scale: Dictionary = _valid_look()
	bool_scale["default"]["scale"] = true
	cases.append([bool_scale, "default.scale"])
	var bad_color: Dictionary = _valid_look()
	bad_color["robots"]["drone"]["emission_color"] = [1.0, 2.0, 0.0]
	cases.append([bad_color, "robots.drone.emission_color"])
	var short_color: Dictionary = _valid_look()
	short_color["default"]["emission_color"] = [1.0, 0.0]
	cases.append([short_color, "default.emission_color"])
	var missing: Dictionary = _valid_look()
	missing["robots"]["drone"].erase("scale")
	cases.append([missing, "scale"])
	var extra: Dictionary = _valid_look()
	extra["robots"]["drone"]["glow"] = 1.0
	cases.append([extra, "glow"])
	var no_default: Dictionary = _valid_look()
	no_default.erase("default")
	cases.append([no_default, "default"])
	if RobotView.parse_look(JSON.stringify(_valid_look())).has("error"):
		return "the valid look was rejected"
	for case: Array in cases:
		var parsed: Dictionary = RobotView.parse_look(JSON.stringify(case[0]))
		if not parsed.has("error"):
			return "accepted a look with a bad \"%s\"" % case[1]
		if not String(parsed["error"]).contains(case[1]):
			return "error \"%s\" does not name \"%s\"" % [parsed["error"], case[1]]
	return ""


func test_a_rejected_look_file_falls_back() -> String:
	var view: RobotView = RobotView.new()
	var error: String = view.load_look("res://view/no_such_look.json")
	var result: String = ""
	if error == "" or view.look_error != error:
		result = "a missing look file set no error"
	elif not view.looked_ids().is_empty():
		result = "a missing look file kept ids %s" % [view.looked_ids()]
	elif view.look_for("drone")["shape"] != RobotView.FALLBACK_LOOK["shape"]:
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
