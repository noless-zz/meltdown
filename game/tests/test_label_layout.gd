extends RefCounted

## Control label layout (issues #147 and #1316, PLT-5, CMF-4): text readable
## at arm's length, a short leader line from each label to its control, and no
## two labels overlapping with the controllers in a neutral pose.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
## Neutral pose, eye at the origin looking along -z: hands 30 cm apart,
## 40 cm ahead of the eye and 15 cm below it, grips level (identity basis).
const LEFT_HAND_AT: Vector3 = Vector3(-0.15, -0.15, -0.40)
const RIGHT_HAND_AT: Vector3 = Vector3(0.15, -0.15, -0.40)
## Hands as close as #1316 asks the labels to stay clear at, for the checks
## that the labels fit the cockpit window: since the column stands beside the
## controller's outline, at 30 cm apart the outer ends of the widest rows
## reach past preset 1's window edge.
const CLOSE_APART_M: float = 0.2
## The text height before #147 (32 px at 0.5 mm per pixel).
const OLD_EM_M: float = 0.016
## Distance the text size is judged at, and the size per pixel before #1316.
const ARM_M: float = 0.6
const BEFORE_1316_PIXEL_M: float = 0.00028
## Every control with a long, two-action text, to fill each column.
const EVERY_CONTROL: Dictionary = {
	"stick": "back, nose down\nstrafe left, yaw left  +  strafe right, yaw right\nforward, nose up",
	"stick_click": "click: map, hold: labels",
	"button_upper": "nose down / up",
	"button_lower": "strafe left / right",
	"menu": "tap: menu, hold: reset",
	"trigger": "up, boost",
	"grip": "roll left, roll right",
}


## The neutral pose, or with the hands `apart` metres apart instead.
func _rig_in_neutral_pose(apart: float = RIGHT_HAND_AT.x - LEFT_HAND_AT.x) -> Node:
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	(rig.get_node("LeftHand") as Node3D).position = Vector3(-0.5 * apart, LEFT_HAND_AT.y, LEFT_HAND_AT.z)
	(rig.get_node("RightHand") as Node3D).position = Vector3(0.5 * apart, RIGHT_HAND_AT.y, RIGHT_HAND_AT.z)
	rig.call("build")
	ControlLabelClearance.face_all(rig, Transform3D.IDENTITY)
	return rig


## Each shown label's rectangle as seen from an eye at the origin looking
## along -z, in tangent units, keyed "<hand> <control>" (`ControlLabelClearance`).
static func _view_rects(rig: Node) -> Dictionary:
	return ControlLabelClearance.view_rects(rig, Transform3D.IDENTITY)


static func _first_overlap(rects: Dictionary) -> String:
	return ControlLabelClearance.first_overlap(rects)


func test_text_is_smaller_than_before_and_readable_at_arm_length() -> String:
	var layout: Dictionary = ControlLabelLayout.load_file()
	var pixel: float = ControlLabelLayout.pixel_size(layout, ControlLabelSet.LABEL_FONT_SIZE)
	var em: float = ControlLabelSet.LABEL_FONT_SIZE * pixel
	if em >= OLD_EM_M:
		return "label text is %.1f mm, want smaller than %.1f mm" % [em * 1000.0, OLD_EM_M * 1000.0]
	# No smaller, at 0.6 m, than the 0.28 mm per pixel text the owner found too small to read (#1316).
	var angle: float = rad_to_deg(atan(em / ARM_M))
	var before: float = rad_to_deg(atan(ControlLabelSet.LABEL_FONT_SIZE * BEFORE_1316_PIXEL_M / ARM_M))
	if angle < before:
		return "letters are %.2f degrees at %.1f m, smaller than the %.2f before #1316" % [angle, ARM_M, before]
	var rig: Node = _rig_in_neutral_pose()
	var label: Label3D = (rig.call("model_for", "right") as ControllerModel).label_set().label_for("trigger")
	var message: String = ""
	if label == null:
		message = "no right trigger label"
	elif label.font_size != ControlLabelSet.LABEL_FONT_SIZE or not is_equal_approx(label.pixel_size, pixel):
		message = "label is not drawn at the stated size"
	elif label.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
		message = "label does not face the eye"
	rig.free()
	return message


func test_rows_are_further_apart_than_a_line_is_tall() -> String:
	var layout: Dictionary = ControlLabelLayout.load_file()
	var height: float = ControlLabelSet.text_size("Ay", ControlLabelLayout.pixel_size(layout,
		ControlLabelSet.LABEL_FONT_SIZE)).y
	var sizes: Dictionary = {}
	for control: String in ControlLabelLayout.CONTROLS:
		sizes[control] = Vector2(0.05, height)
	if float(layout["row_gap_m"]) <= 0.0:
		return "no gap between rows"
	var spots: Dictionary = ControlLabelLayout.place(layout, sizes, 1.0)
	for i: int in range(1, ControlLabelLayout.CONTROLS.size()):
		var above: Vector2 = spots[ControlLabelLayout.CONTROLS[i - 1]]
		var below: Vector2 = spots[ControlLabelLayout.CONTROLS[i]]
		if above.y - below.y <= height:
			return "rows %.1f mm apart but a line is %.1f mm tall" % [
				(above.y - below.y) * 1000.0, height * 1000.0]
		if not is_equal_approx(above.x, below.x):
			return "rows are not in one column"
	return ""


func test_default_labels_do_not_overlap_in_the_neutral_pose() -> String:
	var rig: Node = _rig_in_neutral_pose()
	var rects: Dictionary = _view_rects(rig)
	var message: String = _first_overlap(rects)
	if message == "" and rects.size() != 11:  # 11 since X lost its preset label (#1260).
		message = "want the 11 default labels, measured %d" % rects.size()
	rig.free()
	return message


func test_left_handed_labels_do_not_overlap() -> String:
	var rig: Node = _rig_in_neutral_pose()
	var mapping: ThumbstickMapping = rig.get("mapping") as ThumbstickMapping
	mapping.left_handed = true
	rig.call("refresh_labels")
	var message: String = _first_overlap(_view_rects(rig))
	rig.free()
	return message


func test_every_control_labelled_does_not_overlap() -> String:
	var rig: Node = _rig_in_neutral_pose()
	for hand: String in ["left", "right"]:
		(rig.call("model_for", hand) as ControllerModel).set_labels(EVERY_CONTROL)
	var rects: Dictionary = _view_rects(rig)
	var message: String = _first_overlap(rects)
	if message == "" and rects.size() != 2 * EVERY_CONTROL.size():
		message = "want %d labels, measured %d" % [2 * EVERY_CONTROL.size(), rects.size()]
	rig.free()
	return message


func test_each_label_has_a_short_leader_to_its_control() -> String:
	var rig: Node = _rig_in_neutral_pose()
	var layout: Dictionary = ControlLabelLayout.load_file()
	var message: String = ""
	for hand: String in ["left", "right"]:
		var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
		var labels: ControlLabelSet = model.label_set()
		var leaders: Dictionary = labels.leaders()
		var side: float = ControlLabelLayout.side_sign(layout, hand)
		for control: Variant in labels.texts():
			if not leaders.has(control):
				message = "%s %s has no leader line" % [hand, control]
				break
			var ends: Array = leaders[control]
			var label_end: Vector3 = ends[0]
			var control_end: Vector3 = ends[1]
			var point: Vector3 = labels.mirror(ControlLabelSet.control_point(str(control), ControllerModel.CONTROL_POINTS))
			var label: Label3D = labels.label_for(str(control))
			var leader: ControlLabelLeader = labels.leader_for(str(control))
			if not control_end.is_equal_approx(point):
				message = "%s %s leader ends at %s, not the control at %s" % [hand, control, control_end, point]
			elif side * (label.position.x - label_end.x) < ControlLabelSet.LEADER_GAP * 0.99:
				message = "%s %s leader crosses into its text" % [hand, control]
			elif label_end.distance_to(control_end) > float(layout["max_leader_m"]):
				message = "%s %s leader is %.0f mm long" % [hand, control, label_end.distance_to(control_end) * 1000.0]
			elif leader == null or leader.mesh.get_surface_count() != 1:
				message = "%s %s leader line is not drawn" % [hand, control]
			elif not is_equal_approx(leader.width, float(layout["leader_width_m"])):
				message = "%s %s leader is %.4f m wide, not the layout's" % [hand, control, leader.width]
			if message != "":
				break
		if message != "":
			break
	rig.free()
	return message


func test_text_runs_away_from_the_other_hand() -> String:
	var rig: Node = _rig_in_neutral_pose()
	var message: String = ""
	var want: Dictionary = {"left": HORIZONTAL_ALIGNMENT_RIGHT, "right": HORIZONTAL_ALIGNMENT_LEFT}
	for hand: String in want:
		var labels: ControlLabelSet = (rig.call("model_for", hand) as ControllerModel).label_set()
		var centre: Vector3 = labels.controller_centre()
		for control: Variant in labels.texts():
			var label: Label3D = labels.label_for(str(control))
			if ControlLabelSet.CENTRED.has(str(control)):
				# The cross's three lines stay centred on each other (#606).
				if label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
					message = "%s %s cross should be centred" % [hand, control]
			elif label.horizontal_alignment != want[hand]:
				message = "%s %s text should run outward" % [hand, control]
			if (label.position.x < centre.x) != (hand == "left"):
				message = "%s %s sits on the inner side" % [hand, control]
	rig.free()
	return message
