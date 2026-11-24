extends RefCounted

## Control labels readable at a glance (#1316, PLT-5, CMF-8, ARC-3, ARC-4):
## with every shipped scheme, in both handednesses, on the generic shape and
## the Quest 3 model, at the resting grip and with the hands 20 cm apart, no
## label box overlaps another or either controller; the check fails on a forced
## overlap; the column faces the eye however the hand is turned; and every key
## of the layout file moves something.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const LABEL_LAYOUT: GDScript = preload("res://tests/test_label_layout.gd")
## Text sizes long enough to fill a column, as `test_label_layout.gd` uses.
const EVERY_CONTROL: Dictionary = LABEL_LAYOUT.EVERY_CONTROL
## Keys that place the labels, and a changed value for each.
const LAYOUT_CHANGES: Dictionary = {
	"controller_centre_m": Vector3(0.0, 0.0, 0.0),
	"controller_radius_m": 0.09,
	"gap_m": 0.02,
	"row_height_m": 0.03,
	"row_gap_m": 0.01,
	"column_side": "inner",
	"column_rise_m": -0.03,
	"leader_width_m": 0.003,
	"text_deg": 1.4,
	"arm_length_m": 0.8,
}


static func _schemes() -> Array[String]:
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(ThumbstickMapping.LAYOUTS_DIR):
		if file.ends_with(".json"):
			files.append(ThumbstickMapping.LAYOUTS_DIR + "/" + file)
	files.sort()
	return files


## The rig with `scheme`'s labels, on the Quest 3 model when `quest3`.
static func _rig(scheme: String, left_handed: bool, quest3: bool) -> Node:
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	rig.call("build")
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(scheme)
	mapping.left_handed = left_handed
	rig.set("mapping", mapping)
	rig.call("refresh_labels")
	if quest3:
		for hand: String in ["left", "right"]:
			(rig.call("model_for", hand) as ControllerModel).on_vendor_model_loaded()
	return rig


static func _label_set(hand: String, labels: Dictionary, layout: Dictionary) -> ControlLabelSet:
	var set: ControlLabelSet = ControlLabelSet.new(hand)
	set.layout = layout
	set.set_labels(labels, ControllerModel.CONTROL_POINTS)
	return set


## Everything a layout key can change: each label's place and size, each leader.
static func _signature(set: ControlLabelSet) -> String:
	var parts: PackedStringArray = []
	for control: Variant in set.texts():
		var label: Label3D = set.label_for(str(control))
		parts.append("%s %s %s %s" % [control, label.position, label.pixel_size, label.horizontal_alignment])
		var leader: ControlLabelLeader = set.leader_for(str(control))
		if leader != null:
			parts.append("%s %s %s" % [leader.start, leader.end, leader.width])
	return " | ".join(parts)


func test_shipped_schemes_are_clear_at_both_poses() -> String:
	if _schemes().size() < 3:
		return "found only %s" % [_schemes()]
	for scheme: String in _schemes():
		for left_handed: bool in [false, true]:
			for quest3: bool in [false, true]:
				var rig: Node = _rig(scheme, left_handed, quest3)
				var labels: int = (rig.call("model_for", "right") as ControllerModel).label_texts().size()
				var message: String = ControlLabelClearance.check(rig)
				rig.free()
				if labels == 0:
					message = "no labels"
				if message != "":
					return "%s, left-handed %s, Quest 3 %s: %s" % [scheme.get_file(), left_handed, quest3, message]
	return ""


func test_every_control_labelled_is_clear_at_both_poses() -> String:
	var rig: Node = _rig(ThumbstickMapping.DEFAULT_LAYOUT_FILE, false, true)
	for hand: String in ["left", "right"]:
		(rig.call("model_for", hand) as ControllerModel).set_labels(EVERY_CONTROL)
	var message: String = ControlLabelClearance.check(rig)
	rig.free()
	return message


func test_labels_stay_clear_however_the_hand_is_turned() -> String:
	var layout: Dictionary = ControlLabelLayout.load_file()
	var rig: Node = _rig(ThumbstickMapping.DEFAULT_LAYOUT_FILE, false, true)
	var message: String = ""
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		for degrees: float in [-60.0, -30.0, 30.0, 60.0]:
			ControlLabelClearance.place_hands(rig, layout, ControlLabelClearance.POSE_CLOSE)
			for hand: String in ["left", "right"]:
				var node: Node3D = rig.get_node("LeftHand" if hand == "left" else "RightHand") as Node3D
				var turn: float = deg_to_rad(degrees) * (-1.0 if hand == "left" and axis != Vector3.RIGHT else 1.0)
				node.basis = Basis(axis, turn) * node.basis
			ControlLabelClearance.face_all(rig, Transform3D.IDENTITY)
			message = ControlLabelClearance.first_problem(rig, Transform3D.IDENTITY, layout)
			if message != "":
				message = "turned %s degrees about %s: %s" % [degrees, axis, message]
				break
		if message != "":
			break
	rig.free()
	return message


func test_a_forced_overlap_fails_the_check() -> String:
	var shipped: Dictionary = ControlLabelLayout.load_file()
	var inner: Dictionary = shipped.duplicate()
	inner["column_side"] = "inner"
	inner["close_apart_m"] = 0.1
	var cases: Dictionary = {"columns between the hands": inner}
	var hugging: Dictionary = shipped.duplicate()
	hugging["controller_radius_m"] = 0.02
	hugging["gap_m"] = 0.0
	cases["rows on the controller"] = hugging
	var cramped: Dictionary = shipped.duplicate()
	cramped["max_leader_m"] = 0.02
	cases["a long leader"] = cramped
	for name: String in cases:
		var rig: Node = _rig(ThumbstickMapping.DEFAULT_LAYOUT_FILE, false, true)
		for hand: String in ["left", "right"]:
			(rig.call("model_for", hand) as ControllerModel).label_set().layout = cases[name]
		rig.call("refresh_labels")
		# Judged against the shipped controller, as a headset would show it.
		var judged: Dictionary = (cases[name] as Dictionary).duplicate()
		judged["controller_radius_m"] = shipped["controller_radius_m"]
		var message: String = ControlLabelClearance.check(rig, judged)
		rig.free()
		if message == "":
			return "%s passed" % name
	var overlapping: Dictionary = {"a": Rect2(0, 0, 1, 1), "b": Rect2(0.5, 0.5, 1, 1)}
	return "" if ControlLabelClearance.first_overlap(overlapping) != "" else "two overlapping boxes passed"


func test_the_column_is_square_to_the_eye() -> String:
	var set: ControlLabelSet = _label_set("right", EVERY_CONTROL, ControlLabelLayout.load_file())
	var message: String = ""
	var eyes: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.4)),
		Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, -0.4), Vector3(-0.2, 0.1, 0.3)),
		Transform3D(Basis(Vector3.FORWARD, 0.6), Vector3(0.3, -0.2, 0.4)),
	]
	for eye: Transform3D in eyes:
		set.face(eye)
		if not set.view_basis().is_equal_approx(eye.basis):
			message = "eye %s: the column lies in %s" % [eye, set.view_basis()]
		var depth: float = (eye.affine_inverse() * set.label_for("trigger").position).z
		for control: Variant in set.texts():
			var label: Label3D = set.label_for(str(control))
			if label.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
				message = "%s does not face the eye" % control
			elif absf((eye.affine_inverse() * label.position).z - depth) > 0.0001:
				message = "eye %s: %s is not at the column's depth" % [eye, control]
		if message != "":
			break
	set.free()
	return message


func test_the_column_clears_the_outline_off_the_middle_of_the_view() -> String:
	# A sphere seen 45 degrees off the middle is drawn wider than its radius.
	var radius: float = 0.065
	var centre: Vector3 = Vector3(0.3, 0.0, -0.3)
	var reach: float = ControlLabelLayout.outline_extent(centre, radius, 1.0)
	if reach <= radius * 1.2:
		return "the outline reaches %.0f mm, want past %.0f" % [reach * 1000.0, radius * 1200.0]
	var edge: Vector2 = Vector2(centre.x + reach, centre.y) / -centre.z
	var ray: Vector3 = Vector3(edge.x, edge.y, -1.0).normalized()
	var miss: float = (centre - ray * centre.dot(ray)).length()
	if not is_equal_approx(snappedf(miss, 0.0001), snappedf(radius, 0.0001)):
		return "the outline's edge is %.1f mm from the centre, not the radius" % (miss * 1000.0)
	var middle: float = ControlLabelLayout.outline_extent(Vector3(0.0, 0.0, -0.4), radius, -1.0)
	return "" if middle >= radius and middle < radius * 1.05 else "straight ahead it reaches %.1f mm" % (middle * 1000.0)


func test_left_handed_mode_mirrors_the_column() -> String:
	var layout: Dictionary = ControlLabelLayout.load_file()
	var right: ControlLabelSet = _label_set("right", EVERY_CONTROL, layout)
	var left: ControlLabelSet = _label_set("left", EVERY_CONTROL, layout)
	var message: String = ""
	for control: Variant in right.texts():
		var a: Vector3 = right.label_for(str(control)).position
		var b: Vector3 = left.label_for(str(control)).position
		if not Vector3(-a.x, a.y, a.z).is_equal_approx(b):
			message = "%s: right %s, left %s" % [control, a, b]
			break
	right.free()
	left.free()
	return message


func test_each_layout_key_changes_the_layout() -> String:
	var shipped: Dictionary = ControlLabelLayout.load_file()
	var base: ControlLabelSet = _label_set("right", EVERY_CONTROL, shipped)
	var before: String = _signature(base)
	base.free()
	for key: String in LAYOUT_CHANGES:
		var layout: Dictionary = shipped.duplicate()
		layout[key] = LAYOUT_CHANGES[key]
		var set: ControlLabelSet = _label_set("right", EVERY_CONTROL, layout)
		var after: String = _signature(set)
		set.free()
		if after == before:
			return "changing \"%s\" moved nothing" % key
	return ""


func test_the_shipped_scheme_rows_follow_decision_0011() -> String:
	var labels: Dictionary = ControlLabels.for_mapping(ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE))
	if labels.has("left_button_lower"):
		return "X still has a label: %s" % labels["left_button_lower"]
	if not str(labels.get("right_trigger", "")).contains("both"):
		return "the right trigger reads '%s', not firing both primaries" % labels.get("right_trigger", "")
	if labels.get("left_menu", "") != "tap: menu, hold: reset":
		return "the left menu reads '%s'" % labels.get("left_menu", "")
	return ""
