extends RefCounted

## Leader lines on the runtime's real controller model (issue #652, PLT-5,
## CMF-1): measured parts first, then the per-profile table in
## `res://xr/controller_anchors.json`, and the generic shape's own points when
## no runtime model is shown. CI has no runtime and no vendors plugin, so the
## runtime model is simulated by the signals and by named nodes added by hand.

const QUEST3: String = "/interaction_profiles/meta/touch_controller_plus"
const EVERY_LABEL: Dictionary = {
	"stick": "up\nleft  +  right\ndown", "stick_click": "click", "button_upper": "upper",
	"button_lower": "lower", "menu": "menu", "trigger": "trigger", "grip": "grip",
}


func _anchors() -> ControllerAnchors:
	return ControllerAnchors.load_file()


func _valid_data() -> Dictionary:
	var json: JSON = JSON.new()
	json.parse(FileAccess.get_file_as_string(ControllerAnchors.DEFAULT_FILE))
	return json.data


## The first label whose leader does not end on `points` (right-hand points,
## mirrored for the left), or "".
func _leaders_off(model: ControllerModel, points: Dictionary) -> String:
	var labels: ControlLabelSet = model.label_set()
	var leaders: Dictionary = labels.leaders()
	if leaders.is_empty():
		return "%s hand has no leaders" % model.hand
	for control: Variant in leaders:
		var want: Vector3 = labels.mirror(ControlLabelSet.control_point(str(control), points))
		var got: Vector3 = (leaders[control] as Array)[1]
		if not got.is_equal_approx(want):
			return "%s %s leader ends at %s, want %s" % [model.hand, control, got, want]
	return ""


func test_data_file_loads_with_a_quest3_table() -> String:
	var anchors: ControllerAnchors = _anchors()
	if anchors.error != "":
		return anchors.error
	if anchors.runtime_default_profile != QUEST3:
		return "the default runtime profile should be the Quest 3's, got %s" % anchors.runtime_default_profile
	var points: Dictionary = anchors.table_points(QUEST3)
	for control: String in ControllerModel.CONTROL_POINTS:
		if not points.has(control):
			return "the Quest 3 table gives no point for %s" % control
	return ""


func test_rejects_a_profile_missing_a_component() -> String:
	var data: Dictionary = _valid_data()
	(data["profiles"][QUEST3] as Dictionary).erase("grip")
	var anchors: ControllerAnchors = ControllerAnchors.parse_data(data)
	if not anchors.error.contains("grip"):
		return "a table without grip should be rejected naming it, got \"%s\"" % anchors.error
	return ""


func test_rejects_missing_node_names_and_bad_numbers() -> String:
	var data: Dictionary = _valid_data()
	(data["node_names"] as Dictionary).erase("trigger")
	if not ControllerAnchors.parse_data(data).error.contains("trigger"):
		return "node_names without trigger should be rejected"
	data = _valid_data()
	data["profiles"][QUEST3]["menu"] = [0.0, "up", 0.0]
	if not ControllerAnchors.parse_data(data).error.contains("menu"):
		return "a menu point that is not three numbers should be rejected"
	if ControllerAnchors.parse_json("[]").error == "":
		return "a JSON array should be rejected"
	return ""


func test_unknown_profile_uses_the_quest3_table() -> String:
	var anchors: ControllerAnchors = _anchors()
	if anchors.table_points("/interaction_profiles/oculus/touch_controller") != anchors.table_points(QUEST3):
		return "an unknown or generic profile should use the Quest 3 table"
	return ""


func test_generic_shape_keeps_todays_points_on_both_hands() -> String:
	for hand: String in ["left", "right"]:
		var model: ControllerModel = ControllerModel.new(hand)
		model.build()
		model.set_labels(EVERY_LABEL)
		var message: String = _leaders_off(model, ControllerModel.CONTROL_POINTS)
		if message == "" and model.anchor_source() != ControllerAnchors.SOURCE_GENERIC:
			message = "%s source is %s with the generic shape" % [hand, model.anchor_source()]
		model.free()
		if message != "":
			return message
	return ""


func test_runtime_model_without_named_parts_uses_the_table_on_both_hands() -> String:
	var table: Dictionary = _anchors().table_points(QUEST3)
	for hand: String in ["left", "right"]:
		var model: ControllerModel = ControllerModel.new(hand)
		model.build()
		model.set_labels(EVERY_LABEL)
		model.on_vendor_model_loaded()
		var message: String = _leaders_off(model, table)
		if message == "" and model.anchor_source() != ControllerAnchors.SOURCE_TABLE:
			message = "%s source is %s, want table" % [hand, model.anchor_source()]
		model.free()
		if message != "":
			return message
	return ""


func test_removing_the_runtime_model_returns_to_generic_points() -> String:
	var model: ControllerModel = ControllerModel.new("right")
	model.build()
	model.set_labels(EVERY_LABEL)
	var ext_model: Node3D = Node3D.new()
	model.on_runtime_model_added(ext_model)
	var message: String = _leaders_off(model, _anchors().table_points(QUEST3))
	model.on_runtime_model_removed(ext_model)
	if message == "":
		message = _leaders_off(model, ControllerModel.CONTROL_POINTS)
	ext_model.free()
	model.free()
	return message


func test_named_nodes_win_over_the_table() -> String:
	var parts: Dictionary = {
		"b_thumbstick": Vector3(0.011, 0.02, 0.03), "b_button_y": Vector3(0.02, 0.01, 0.025),
		"b_button_x": Vector3(0.02, 0.0, 0.04), "b_trigger_front": Vector3(0.0, -0.03, 0.0),
	}
	for hand: String in ["left", "right"]:
		var model: ControllerModel = ControllerModel.new(hand)
		model.build()
		var manager: Node3D = model.runtime_models()
		var holder: Node3D = Node3D.new()
		holder.position = Vector3(0.0, 0.005, 0.0)
		manager.add_child(holder)
		for part: String in parts:
			var node: Node3D = Node3D.new()
			node.name = part
			node.position = parts[part]
			holder.add_child(node)
		model.on_runtime_model_added(holder)
		model.set_labels(EVERY_LABEL)
		var leaders: Dictionary = model.label_set().leaders()
		var lift: Vector3 = Vector3(0.0, 0.005, 0.0)
		var want: Dictionary = {
			"stick": parts["b_thumbstick"] + lift, "button_upper": parts["b_button_y"] + lift,
			"button_lower": parts["b_button_x"] + lift, "trigger": parts["b_trigger_front"] + lift,
			"grip": model.label_set().mirror(_anchors().table_points(QUEST3)["grip"]),
		}
		var message: String = ""
		for control: String in want:
			# The nodes sit where they are in the model's own space: on the
			# left hand that is already mirrored, so the leader ends on them.
			var got: Vector3 = (leaders[control] as Array)[1]
			if not got.is_equal_approx(want[control]):
				message = "%s %s leader ends at %s, want the part at %s" % [hand, control, got, want[control]]
				break
		if message == "" and model.anchor_source() != ControllerAnchors.SOURCE_NODES:
			message = "%s source is %s, want nodes" % [hand, model.anchor_source()]
		model.free()
		if message != "":
			return message
	return ""


func test_skeleton_bones_count_as_parts() -> String:
	var anchors: ControllerAnchors = _anchors()
	var root: Node3D = Node3D.new()
	var skeleton: Skeleton3D = Skeleton3D.new()
	skeleton.position = Vector3(0.0, 0.0, 0.01)
	root.add_child(skeleton)
	var bone: int = skeleton.add_bone("b_button_oculus")
	skeleton.set_bone_rest(bone, Transform3D(Basis.IDENTITY, Vector3(0.003, 0.002, 0.04)))
	skeleton.reset_bone_poses()
	var found: Dictionary = anchors.find_parts(root, root)
	root.free()
	if not found.has("menu"):
		return "the menu bone was not found: %s" % found
	if not (found["menu"] as Vector3).is_equal_approx(Vector3(0.003, 0.002, 0.05)):
		return "the menu bone sits at %s, want (0.003, 0.002, 0.05)" % found["menu"]
	return ""


func test_exact_names_win_over_contained_names() -> String:
	var anchors: ControllerAnchors = _anchors()
	var root: Node3D = Node3D.new()
	for part: String in ["b_trigger_grip", "b_trigger_front"]:
		var node: Node3D = Node3D.new()
		node.name = part
		node.position = Vector3(0.0, 0.0, 0.01) if part == "b_trigger_grip" else Vector3(0.0, 0.0, -0.01)
		root.add_child(node)
	var found: Dictionary = anchors.find_parts(root, root)
	root.free()
	if not (found.get("trigger", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.0, 0.0, -0.01)):
		return "the trigger should be b_trigger_front, got %s" % found.get("trigger")
	if not (found.get("grip", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.0, 0.0, 0.01)):
		return "the grip should be b_trigger_grip, got %s" % found.get("grip")
	return ""


func test_lines_follow_left_handed_and_paired_layouts() -> String:
	var table: Dictionary = _anchors().table_points(QUEST3)
	var layouts: Dictionary = {
		"default": ThumbstickMapping.default_layout(),
		"paired": ThumbstickMapping.from_file(ThumbstickMapping.PAIRED_LAYOUT_FILE).layout,
	}
	for layout_name: String in layouts:
		for left_handed: bool in [false, true]:
			var labels: Dictionary = ControlLabels.for_layout(layouts[layout_name], left_handed)
			for hand: String in ["left", "right"]:
				var model: ControllerModel = ControllerModel.new(hand)
				model.build()
				model.on_vendor_model_loaded()
				var own: Dictionary = ControlLabels.for_hand(labels, hand)
				model.set_labels(own)
				var message: String = _leaders_off(model, table)
				if message == "" and model.label_texts() != _known(own):
					message = "texts differ from the layout"
				model.free()
				if message != "":
					return "%s layout, left-handed %s: %s" % [layout_name, left_handed, message]
	return ""


func test_preset_on_x_and_down_on_y_in_left_handed_mode() -> String:
	# Decision record 0004 and #613: the preset sits on X (left lower) and down
	# on Y (left upper); left-handed mode moves both to A and B.
	var table: Dictionary = _anchors().table_points(QUEST3)
	for left_handed: bool in [false, true]:
		var labels: Dictionary = ControlLabels.for_layout(ThumbstickMapping.default_layout(), left_handed)
		var hand: String = "right" if left_handed else "left"
		var model: ControllerModel = ControllerModel.new(hand)
		model.build()
		model.on_vendor_model_loaded()
		model.set_labels(ControlLabels.for_hand(labels, hand))
		var lower: String = str(model.label_texts().get("button_lower", ""))
		var end: Vector3 = (model.label_set().leaders()["button_lower"] as Array)[1]
		var message: String = ""
		if not lower.contains(ControlLabels.PRESET_WORD):
			message = "%s button_lower reads \"%s\", want the preset" % [hand, lower]
		elif not end.is_equal_approx(model.label_set().mirror(table["button_lower"])):
			message = "%s preset leader ends at %s, not on the lower button" % [hand, end]
		model.free()
		if message != "":
			return message
	return ""


func _known(labels: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for control: String in labels:
		if ControlLabelSet.LABEL_POSITIONS.has(control):
			result[control] = labels[control]
	return result
