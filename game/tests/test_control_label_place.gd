extends RefCounted

## Control labels over the Quest 3 controller (#1212, #1316, PLT-5, PLT-2,
## ARC-3, ARC-4): every part lies inside the layout's controller sphere, each
## leader ends on its part and is no longer than the layout file allows, and
## with the hands where a seated
## pilot holds them no label covers the status panel in any corner. CI has no
## runtime, so the Quest 3 model is the anchor table, as the headset uses it
## when the model names no parts (`test_controller_anchors.gd`).

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const LABEL_LAYOUT: GDScript = preload("res://tests/test_label_layout.gd")
## Half the status panel's width and height: its rows and bars are about
## 0.26 m across (`StatusPanel.ROW_PITCH`, as `test_dev_menu_place.gd` measures it).
const PANEL_HALF: Vector2 = Vector2(0.14, 0.11)


## The rig with both hands at the layout's held pose (eye at the origin) on
## the Quest 3 model, in right- or left-handed mode, with `labels` on both
## hands when given (else the layout's own).
func _rig(left_handed: bool, labels: Dictionary = {}) -> Node:
	var held: Vector3 = ControlLabelLayout.load_file()["held_hand_m"]
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	(rig.get_node("LeftHand") as Node3D).position = Vector3(-held.x, held.y, held.z)
	(rig.get_node("RightHand") as Node3D).position = held
	rig.call("build")
	(rig.get("mapping") as ThumbstickMapping).left_handed = left_handed
	rig.call("refresh_labels")
	for hand: String in ["left", "right"]:
		var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
		if not labels.is_empty():
			model.set_labels(labels)
		model.on_vendor_model_loaded()
	ControlLabelClearance.face_all(rig, Transform3D.IDENTITY)
	return rig


func _cases() -> Array:
	return [[false, {}], [true, {}], [false, LABEL_LAYOUT.EVERY_CONTROL]]


func test_the_shipped_layout_is_accepted_and_matches_the_fallback() -> String:
	var layout: Dictionary = ControlLabelLayout.parse(FileAccess.get_file_as_string(ControlLabelLayout.DEFAULT_FILE))
	if layout.has("error"):
		return "shipped layout rejected: %s" % layout["error"]
	for key: String in ControlLabelLayout.FALLBACK:
		if str(layout[key]) != str(ControlLabelLayout.FALLBACK[key]):
			return "\"%s\" is %s in the file but %s in FALLBACK" % [key, layout[key], ControlLabelLayout.FALLBACK[key]]
	return ""


func test_a_bad_layout_is_rejected_naming_the_key() -> String:
	var json: JSON = JSON.new()
	json.parse(FileAccess.get_file_as_string(ControlLabelLayout.DEFAULT_FILE))
	var good: Dictionary = json.data
	var cases: Dictionary = {
		"gap_m": {"gap_m": 0.5},
		"row_gap_m": {"row_gap_m": true},
		"column_side": {"column_side": "above"},
		"controller_centre_m": {"controller_centre_m": [0.0, 0.5, 0.0]},
		"held_hand_m": {"held_hand_m": [0.1, 0.2]},
		"spin": {"spin": 1},
	}
	for key: String in cases:
		var data: Dictionary = good.duplicate(true)
		data.merge(cases[key], true)
		var layout: Dictionary = ControlLabelLayout.parse(JSON.stringify(data))
		if not layout.has("error") or not str(layout["error"]).contains(key):
			return "a bad \"%s\" gave %s" % [key, layout]
	return ""


func test_every_leader_is_short_and_ends_on_its_part() -> String:
	var limit: float = float(ControlLabelLayout.load_file()["max_leader_m"])
	var table: Dictionary = ControllerAnchors.load_file().table_points("")
	for case: Array in _cases():
		var rig: Node = _rig(case[0], case[1])
		var message: String = ""
		for hand: String in ["left", "right"]:
			var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
			var labels: ControlLabelSet = model.label_set()
			var leaders: Dictionary = labels.leaders()
			if model.anchor_source() != ControllerAnchors.SOURCE_TABLE or labels.texts().is_empty():
				message = "%s hand: source %s, %d labels" % [hand, model.anchor_source(), labels.texts().size()]
			for control: Variant in labels.texts():
				if message != "":
					break
				var point: Vector3 = labels.mirror(ControlLabelSet.control_point(str(control), table))
				if not leaders.has(control) or not ((leaders[control] as Array)[1] as Vector3).is_equal_approx(point):
					message = "%s %s leader does not end on its part at %s" % [hand, control, point]
					break
				var length: float = ((leaders[control] as Array)[0] as Vector3).distance_to(point)
				if length > limit:
					message = "%s %s leader is %.0f mm, limit %.0f" % [hand, control, length * 1000.0, limit * 1000.0]
		rig.free()
		if message != "":
			return "left-handed %s: %s" % [case[0], message]
	return ""


func test_every_quest3_anchor_is_inside_the_controller_sphere() -> String:
	var layout: Dictionary = ControlLabelLayout.load_file()
	var table: Dictionary = ControllerAnchors.load_file().table_points("")
	for part: Variant in table:
		var distance: float = (table[part] as Vector3).distance_to(layout["controller_centre_m"])
		if distance > float(layout["controller_radius_m"]):
			return "%s is %.0f mm from the sphere's centre, outside its %.0f mm" % [part, distance * 1000.0,
				float(layout["controller_radius_m"]) * 1000.0]
	return ""


func test_labels_beside_the_quest3_model_do_not_overlap_each_other() -> String:
	for case: Array in _cases():
		var rig: Node = _rig(case[0], case[1])
		var message: String = LABEL_LAYOUT._first_overlap(LABEL_LAYOUT._view_rects(rig))
		rig.free()
		if message != "":
			return "left-handed %s: %s" % [case[0], message]
	return ""


func test_no_label_covers_the_status_panel_in_any_corner() -> String:
	var saved: String = PanelCorner.current
	var message: String = ""
	for corner: String in PanelCorner.names():
		PanelCorner.current = corner
		var panel: Rect2 = _panel_rect(StatusPanel.rig_transform(Transform3D.IDENTITY))
		for case: Array in _cases():
			var rig: Node = _rig(case[0], case[1])
			var rects: Dictionary = LABEL_LAYOUT._view_rects(rig)
			rig.free()
			for key: Variant in rects:
				if (rects[key] as Rect2).intersects(panel):
					message = "%s: label '%s' %s covers the panel %s" % [corner, key, rects[key], panel]
					break
			if message != "":
				break
		if message != "":
			break
	PanelCorner.current = saved
	return message


func test_the_panel_check_can_fail() -> String:
	# A panel just outside the held right hand must be found under its labels.
	var held: Vector3 = ControlLabelLayout.load_file()["held_hand_m"]
	var panel: Rect2 = _panel_rect(Transform3D(Basis.IDENTITY, held + Vector3(0.14, 0.0, -0.05)))
	var rig: Node = _rig(false)
	var rects: Dictionary = LABEL_LAYOUT._view_rects(rig)
	rig.free()
	for key: Variant in rects:
		if (rects[key] as Rect2).intersects(panel):
			return ""
	return "no label found over a panel placed right behind the hand"


## The panel at `placement` (eye at the origin) as a view rectangle in the
## units of `_view_rects`: x and y over depth.
static func _panel_rect(placement: Transform3D) -> Rect2:
	var box: Rect2 = Rect2()
	var first: bool = true
	for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		var point: Vector3 = placement * Vector3(PANEL_HALF.x * corner.x, PANEL_HALF.y * corner.y, 0.0)
		var seen: Vector2 = Vector2(point.x, point.y) / -point.z
		box = Rect2(seen, Vector2.ZERO) if first else box.expand(seen)
		first = false
	return box
