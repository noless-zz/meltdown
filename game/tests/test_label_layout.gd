extends RefCounted

## Control label layout (issue #147, PLT-5, CMF-4): smaller text, a short
## leader line from each label to its control, and no two labels overlapping
## with the controllers in a neutral pose.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
## Neutral pose, eye at the origin looking along -z: hands 30 cm apart,
## 40 cm ahead of the eye and 15 cm below it, grips level (identity basis).
const LEFT_HAND_AT: Vector3 = Vector3(-0.15, -0.15, -0.40)
const RIGHT_HAND_AT: Vector3 = Vector3(0.15, -0.15, -0.40)
## The text height before #147 (32 px at 0.5 mm per pixel).
const OLD_EM_M: float = 0.016
## Longest leader line that still counts as short.
const MAX_LEADER_M: float = 0.08
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


func _rig_in_neutral_pose() -> Node:
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	(rig.get_node("LeftHand") as Node3D).position = LEFT_HAND_AT
	(rig.get_node("RightHand") as Node3D).position = RIGHT_HAND_AT
	rig.call("build")
	return rig


## Each shown label's rectangle as seen from the eye, in tangent units
## (x / depth, y / depth), keyed "<hand> <control>". Labels are billboarded and
## the eye looks along -z, so each is an upright rectangle at its depth.
static func _view_rects(rig: Node) -> Dictionary:
	var rects: Dictionary = {}
	for hand: String in ["left", "right"]:
		var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
		var labels: ControlLabelSet = model.label_set()
		var hand_node: Node3D = model.get_parent() as Node3D
		var to_rig: Transform3D = hand_node.transform * model.transform * labels.transform
		for control: Variant in labels.texts():
			var label: Label3D = labels.label_for(str(control))
			var anchor: Vector3 = to_rig * label.position
			var size: Vector2 = ControlLabelSet.text_size(label.text)
			var outline: float = ControlLabelSet.LABEL_OUTLINE_SIZE * ControlLabelSet.LABEL_PIXEL_SIZE
			var left_x: float = anchor.x - outline
			if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
				left_x = anchor.x + outline - size.x
			elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
				# A centred label is moved by its offset, which turns with the billboard.
				left_x = anchor.x + label.offset.x * label.pixel_size - size.x * 0.5
			var depth: float = -anchor.z
			rects["%s %s" % [hand, control]] = Rect2(
				Vector2(left_x, anchor.y - size.y * 0.5) / depth, size / depth)
	return rects


static func _first_overlap(rects: Dictionary) -> String:
	var names: Array = rects.keys()
	names.sort()
	for i: int in names.size():
		for j: int in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			if a.intersects(b):
				return "'%s' %s overlaps '%s' %s" % [names[i], a, names[j], b]
	return ""


func test_text_is_smaller_than_before() -> String:
	var em: float = ControlLabelSet.LABEL_FONT_SIZE * ControlLabelSet.LABEL_PIXEL_SIZE
	if em >= OLD_EM_M:
		return "label text is %.1f mm, want smaller than %.1f mm" % [em * 1000.0, OLD_EM_M * 1000.0]
	var rig: Node = _rig_in_neutral_pose()
	var label: Label3D = (rig.call("model_for", "right") as ControllerModel).label_set().label_for("trigger")
	var message: String = ""
	if label == null:
		message = "no right trigger label"
	elif label.font_size != ControlLabelSet.LABEL_FONT_SIZE or not is_equal_approx(label.pixel_size, ControlLabelSet.LABEL_PIXEL_SIZE):
		message = "label is not drawn at the stated size"
	rig.free()
	return message


func test_rows_are_further_apart_than_a_line_is_tall() -> String:
	# Every part at one height, the worst case: the rows must still stack.
	var height: float = ControlLabelSet.text_size("Ay").y
	var heights: Dictionary = {}
	var points: Dictionary = {}
	for control: String in ControlLabelLayout.CONTROLS:
		heights[control] = height
		points[control] = Vector3.ZERO
	var layout: Dictionary = ControlLabelLayout.load_file()
	if float(layout["row_gap_m"]) <= 0.0:
		return "no gap between rows"
	var spots: Dictionary = ControlLabelLayout.place(layout, heights, points, [] as Array[String])
	for i: int in range(1, ControlLabelLayout.CONTROLS.size()):
		var above: Vector3 = spots[ControlLabelLayout.CONTROLS[i - 1]]
		var below: Vector3 = spots[ControlLabelLayout.CONTROLS[i]]
		if above.y - below.y <= height:
			return "rows %.1f mm apart but a line is %.1f mm tall" % [
				(above.y - below.y) * 1000.0, height * 1000.0]
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
	var message: String = ""
	for hand: String in ["left", "right"]:
		var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
		var labels: ControlLabelSet = model.label_set()
		var leaders: Dictionary = labels.leaders()
		for control: Variant in labels.texts():
			if not leaders.has(control):
				message = "%s %s has no leader line" % [hand, control]
				break
			var ends: Array = leaders[control]
			var label_end: Vector3 = ends[0]
			var control_end: Vector3 = ends[1]
			var point: Vector3 = labels.mirror(ControlLabelSet.control_point(str(control), ControllerModel.CONTROL_POINTS))
			var label: Label3D = labels.label_for(str(control))
			var anchor: Vector3 = label.position
			var start: Vector3 = labels.leader_start(str(control), anchor, ControlLabelSet.text_size(label.text).y)
			if not control_end.is_equal_approx(point):
				message = "%s %s leader ends at %s, not the control at %s" % [hand, control, control_end, point]
			elif not label_end.is_equal_approx(start):
				message = "%s %s leader starts at %s, not its label's edge %s" % [hand, control, label_end, start]
			elif not ControlLabelSet.CENTRED.has(str(control)) and absf(label_end.x) > absf(anchor.x):
				message = "%s %s leader crosses into its text" % [hand, control]
			elif label_end.distance_to(control_end) > MAX_LEADER_M:
				message = "%s %s leader is %.0f mm long" % [hand, control, label_end.distance_to(control_end) * 1000.0]
			elif labels.get_node_or_null(ControlLabelSet.LEADER_PREFIX + str(control)) == null:
				message = "%s %s leader line is not drawn" % [hand, control]
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
		for control: Variant in labels.texts():
			var label: Label3D = labels.label_for(str(control))
			if ControlLabelSet.CENTRED.has(str(control)):
				# The cross is centred over the stick (#1212).
				var stick: Vector3 = labels.mirror(ControlLabelSet.control_point(str(control),
					ControllerModel.CONTROL_POINTS))
				if label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER \
						or not is_equal_approx(label.position.x, stick.x) or label.position.y <= stick.y:
					message = "%s %s cross should be centred over the stick" % [hand, control]
			elif label.horizontal_alignment != want[hand]:
				message = "%s %s text should run outward" % [hand, control]
			elif (label.position.x < 0.0) != (hand == "left"):
				message = "%s %s sits on the inner side" % [hand, control]
	rig.free()
	return message
