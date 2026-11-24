class_name ControlLabelClearance
extends RefCounted

## Whether the control labels can be read at a glance (PLT-5, #1316): seen
## from the eye, no label box overlaps another, either hand's, or the sphere
## round either controller (`ControlLabelLayout`), and no leader is longer than
## `max_leader_m`. Measured with the hands in the layout's resting grip and in
## the same grip `close_apart_m` apart, so the check the owner asked for runs in
## the unit tests and in the m6 acceptance step `control_labels_clear`.
##
## Views are in tangent units of the eye's frame (x / depth, y / depth, eye
## looking along -z). The labels are billboarded, so each is an upright box.
## Only the labels' own nodes and the hands' transforms are touched; the hands
## are put back afterwards (ARC-3: no simulation state).

const HANDS: Array[String] = ["left", "right"]
const POSE_HELD: String = "resting grip"
const POSE_CLOSE: String = "hands close"
const MIN_DEPTH_M: float = 0.01


## The first problem with both hands at both poses, or "" when the labels are
## clear. `rig` is an `XRRig` with `LeftHand` and `RightHand`; the eye is at
## the rig's origin looking along -z.
static func check(rig: Node, layout: Dictionary = ControlLabelLayout.load_file()) -> String:
	var saved: Dictionary = {}
	for hand: String in HANDS:
		saved[hand] = _hand_node(rig, hand).transform
	var message: String = ""
	for pose: String in [POSE_HELD, POSE_CLOSE]:
		place_hands(rig, layout, pose)
		face_all(rig, Transform3D.IDENTITY)
		message = first_problem(rig, Transform3D.IDENTITY, layout)
		if message != "":
			message = "%s: %s" % [pose, message]
			break
	for hand: String in HANDS:
		_hand_node(rig, hand).transform = saved[hand]
	face_all(rig, Transform3D.IDENTITY)
	return message


## Puts both hands in `pose`: the layout's resting grip, or that grip with the
## hands `close_apart_m` apart.
static func place_hands(rig: Node, layout: Dictionary, pose: String) -> void:
	var held: Vector3 = layout["held_hand_m"]
	if pose == POSE_CLOSE:
		held.x = 0.5 * float(layout["close_apart_m"])
	var tilt: Basis = Basis(Vector3.RIGHT, deg_to_rad(float(layout["held_pitch_deg"])))
	_hand_node(rig, "left").transform = Transform3D(tilt, Vector3(-held.x, held.y, held.z))
	_hand_node(rig, "right").transform = Transform3D(tilt, held)


## Turns both hands' columns to an eye at `eye` (rig frame).
static func face_all(rig: Node, eye: Transform3D) -> void:
	for hand: String in HANDS:
		_labels(rig, hand).face(_to_rig(rig, hand).affine_inverse() * eye)


## "<hand> <control>" -> each shown label's box as the eye at `eye` sees it.
static func view_rects(rig: Node, eye: Transform3D) -> Dictionary:
	var rects: Dictionary = {}
	for hand: String in HANDS:
		var labels: ControlLabelSet = _labels(rig, hand)
		var to_eye: Transform3D = eye.affine_inverse() * _to_rig(rig, hand)
		for control: Variant in labels.texts():
			var label: Label3D = labels.label_for(str(control))
			var anchor: Vector3 = to_eye * label.position
			var size: Vector2 = ControlLabelSet.text_size(label.text, label.pixel_size)
			var outline: float = ControlLabelSet.LABEL_OUTLINE_SIZE * label.pixel_size
			var left_x: float = anchor.x - outline
			if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
				left_x = anchor.x + outline - size.x
			elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
				left_x = anchor.x - size.x * 0.5
			var depth: float = -anchor.z
			if depth <= MIN_DEPTH_M:
				continue  # Behind the eye: not seen, so it covers nothing.
			rects["%s %s" % [hand, control]] = Rect2(
				Vector2(left_x, anchor.y - size.y * 0.5) / depth, size / depth)
	return rects


## The first overlap of two boxes, of a box and a controller's sphere, or a
## leader longer than `max_leader_m`; "" when there is none.
static func first_problem(rig: Node, eye: Transform3D, layout: Dictionary) -> String:
	var rects: Dictionary = view_rects(rig, eye)
	var message: String = first_overlap(rects)
	if message != "":
		return message
	var radius: float = float(layout["controller_radius_m"])
	for hand: String in HANDS:
		var centre: Vector3 = eye.affine_inverse() * _to_rig(rig, hand) * _labels(rig, hand).controller_centre()
		for key: Variant in rects:
			if box_meets_sphere(rects[key], centre, radius):
				return "'%s' %s covers the %s controller" % [key, rects[key], hand]
	var longest: float = float(layout["max_leader_m"])
	for hand: String in HANDS:
		var leaders: Dictionary = _labels(rig, hand).leaders()
		for control: Variant in leaders:
			var length: float = ((leaders[control] as Array)[0] as Vector3).distance_to((leaders[control] as Array)[1])
			if length > longest:
				return "%s %s leader is %.0f mm, over %.0f" % [hand, control, length * 1000.0, longest * 1000.0]
	return ""


## The first two boxes that overlap, by name; "" when none do.
static func first_overlap(rects: Dictionary) -> String:
	var names: Array = rects.keys()
	names.sort()
	for i: int in names.size():
		for j: int in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			if a.intersects(b):
				return "'%s' %s overlaps '%s' %s" % [names[i], a, names[j], b]
	return ""


## True when the view ray through the point of `box` nearest the sphere's
## centre passes within `radius` of it (`centre` in the eye's frame).
static func box_meets_sphere(box: Rect2, centre: Vector3, radius: float) -> bool:
	if centre.z >= 0.0:
		return false
	var seen: Vector2 = Vector2(centre.x, centre.y) / -centre.z
	var nearest: Vector2 = seen.clamp(box.position, box.end)
	var ray: Vector3 = Vector3(nearest.x, nearest.y, -1.0).normalized()
	return (centre - ray * centre.dot(ray)).length() < radius


static func _hand_node(rig: Node, hand: String) -> Node3D:
	return rig.get_node("LeftHand" if hand == "left" else "RightHand") as Node3D


static func _labels(rig: Node, hand: String) -> ControlLabelSet:
	return (rig.call("model_for", hand) as ControllerModel).label_set()


static func _to_rig(rig: Node, hand: String) -> Transform3D:
	var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
	return _hand_node(rig, hand).transform * model.transform * model.label_set().transform
