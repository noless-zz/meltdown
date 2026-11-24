extends RefCounted

## Stick and stick-click labels (#606, PLT-5, SLV-1): each stick is a cross
## with each action at the end it is pushed to, each stick click names its
## gesture, and the slot click says "fly through to pick up" while the hold is
## empty and a part floats near (#600). Per layout file and per hand.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const PAIRED_FILE: String = "res://xr/layouts/thumbsticks_paired.json"
const LABEL_LAYOUT: GDScript = preload("res://tests/test_label_layout.gd")
const PRESET1_VIEW: GDScript = preload("res://tests/test_cockpit_preset1_view.gd")

## The flying stick's cross and the turning stick's cross, in every layout file.
const MOVE_CROSS: String = "forward\nleft  <  strafe  >  right\nback"
const TURN_CROSS: String = "nose up\nleft  <  yaw  >  right\nnose down"
const LABEL_CLICK: String = "click: map, hold: labels"
const SLOT_CLICK: String = "click: slot held part"


static func _layouts() -> Dictionary:
	return {
		"default": ThumbstickMapping.default_layout(),
		"paired": ThumbstickMapping.from_file(PAIRED_FILE).layout,
	}


func test_paired_file_loads() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(PAIRED_FILE)
	if mapping.error != "":
		return mapping.error
	return ""


func test_each_stick_is_one_cross_per_layout_and_hand() -> String:
	var layouts: Dictionary = _layouts()
	for name: String in layouts:
		for left_handed: bool in [false, true]:
			var labels: Dictionary = ControlLabels.for_layout(layouts[name], left_handed)
			var move_hand: String = "right" if left_handed else "left"
			var turn_hand: String = "left" if left_handed else "right"
			var what: String = "%s layout, left-handed %s" % [name, left_handed]
			if labels.get(move_hand + "_stick", "") != MOVE_CROSS:
				return "%s: %s stick reads '%s'" % [what, move_hand, labels.get(move_hand + "_stick", "")]
			if labels.get(turn_hand + "_stick", "") != TURN_CROSS:
				return "%s: %s stick reads '%s'" % [what, turn_hand, labels.get(turn_hand + "_stick", "")]
			for key: String in labels:
				if key.ends_with("_stick_x") or key.ends_with("_stick_y"):
					return "%s: an axis has its own label %s" % [what, key]
	return ""


func test_cross_puts_each_action_at_its_end() -> String:
	var text: String = ControlLabels.cross("up word", "down word", "a", "b")
	var lines: PackedStringArray = text.split("\n")
	if lines.size() != 3 or lines[0] != "up word" or lines[2] != "down word":
		return "cross lines are %s" % [lines]
	if not (lines[1].begins_with("a") and lines[1].ends_with("b")):
		return "left and right are not at the ends of '%s'" % lines[1]
	# Two different actions on one axis keep both full words at each end.
	var two: Dictionary = ControlLabels.for_layout({"yaw": {"right_stick_x": 1.0}, "strafe": {"right_stick_x": 1.0}})
	var middle: String = str(two.get("right_stick", "")).split("\n")[1]
	if not (middle.begins_with("yaw left, strafe left") and middle.ends_with("yaw right, strafe right")):
		return "two actions on one axis read '%s'" % middle
	return ""


func test_stick_clicks_name_their_gesture_per_layout_and_hand() -> String:
	var layouts: Dictionary = _layouts()
	for name: String in layouts:
		for left_handed: bool in [false, true]:
			var labels: Dictionary = ControlLabels.for_layout(layouts[name], left_handed)
			var toggle: String = "right_stick_click" if left_handed else "left_stick_click"
			var slot: String = ControlLabels.other_hand(toggle)
			if labels.get(toggle, "") != LABEL_CLICK or labels.get(slot, "") != SLOT_CLICK:
				return "%s layout, left-handed %s: clicks read '%s' and '%s'" % [
					name, left_handed, labels.get(toggle, ""), labels.get(slot, "")]
	return ""


func test_label_click_is_where_the_wiring_reads_it() -> String:
	for left_handed: bool in [false, true]:
		var mapping: ThumbstickMapping = ThumbstickMapping.new()
		mapping.left_handed = left_handed
		var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), mapping)
		var labels: Dictionary = ControlLabels.for_mapping(mapping)
		# The map's click shares it, so the toggle is the hold, named last (#914).
		if not str(labels.get(wiring.label_button(), "")).ends_with(ControlLabels.LABEL_HOLD_WORD):
			return "left-handed %s: the toggle %s is labelled '%s'" % [
				left_handed, wiring.label_button(), labels.get(wiring.label_button(), "")]
	return ""


func test_the_label_click_alone_is_labelled_when_the_map_moves() -> String:
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout.erase("show_map")
	var labels: Dictionary = ControlLabels.for_layout(layout)
	if labels.get("left_stick_click", "") != ControlLabels.LABEL_TOGGLE_WORD:
		return "without the map the left click reads '%s'" % labels.get("left_stick_click", "")
	return ""


func test_pickup_hint_replaces_the_slot_words_on_either_hand() -> String:
	for left_handed: bool in [false, true]:
		var mapping: ThumbstickMapping = ThumbstickMapping.new()
		mapping.left_handed = left_handed
		var slot: String = mapping.physical_controls("slot_part")[0]
		var hinted: Dictionary = ControlLabels.for_mapping(mapping, true)
		if hinted.get(slot, "") != ControlLabels.PICKUP_HINT_WORD:
			return "left-handed %s: hinted slot reads '%s'" % [left_handed, hinted.get(slot, "")]
		var plain: Dictionary = ControlLabels.for_mapping(mapping, false)
		for key: String in plain:
			if key != slot and plain[key] != hinted.get(key, ""):
				return "the hint changed %s" % key
	return ""


func test_hint_is_due_only_with_an_empty_hold_and_a_part_near() -> String:
	var hint: PickupHint = PickupHint.new()
	hint.distance_m = 10.0
	var ship: ShipState = ShipState.new()
	ship.position = Vector3(1.0, 2.0, 3.0)
	var near: Array[SalvageItem] = [SalvageItem.new("needle_gun", ship.position + Vector3(0.0, 0.0, -9.5))]
	var far: Array[SalvageItem] = [SalvageItem.new("needle_gun", ship.position + Vector3(0.0, 0.0, -10.5))]
	var none: Array[SalvageItem] = []
	if not hint.is_due(ship, near):
		return "a part 9.5 m away should hint"
	if hint.is_due(ship, far) or hint.is_due(ship, none):
		return "a part 10.5 m away, or none, should not hint"
	ship.hold.append("pulse_cannon")
	if hint.is_due(ship, near):
		return "a full hold should not hint"
	return ""


func test_hint_distance_file_is_read_and_checked() -> String:
	var shipped: PickupHint = PickupHint.load_file()
	if shipped.error != "":
		return shipped.error
	if shipped.distance_m < 2.5:
		return "hint distance %.1f m is inside the pickup reach" % shipped.distance_m
	if not is_equal_approx(PickupHint.parse_json("{\"distance_m\": 20}").distance_m, 20.0):
		return "distance 20 not read"
	for bad: String in ["{}", "{\"distance_m\": 0.5}", "{\"distance_m\": true}", "{\"distance_m\": 5, \"x\": 1}", "[", "[]"]:
		if PickupHint.parse_json(bad).error == "":
			return "'%s' was accepted" % bad
	if not "distance_m" in PickupHint.parse_json("{\"distance_m\": 500}").error:
		return "a range error does not name the key"
	if PickupHint.load_file("res://no_such_hint.json").error == "":
		return "a missing file was accepted"
	return ""


func test_rig_shows_the_hint_and_takes_it_back() -> String:
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	rig.call("build")
	var right: ControllerModel = rig.call("model_for", "right") as ControllerModel
	var message: String = ""
	rig.set("pickup_hint", true)
	if right.label_texts().get("stick_click", "") != ControlLabels.PICKUP_HINT_WORD:
		message = "hint not shown: %s" % right.label_texts().get("stick_click", "")
	rig.set("pickup_hint", false)
	if message == "" and right.label_texts().get("stick_click", "") != SLOT_CLICK:
		message = "hint not taken back: %s" % right.label_texts().get("stick_click", "")
	rig.free()
	return message


func test_hinted_labels_stay_inside_the_anchored_window() -> String:
	var spec: CockpitSpec = CockpitSpec.for_preset(ComfortPresetFiles.load_number(1))
	var layout: RefCounted = LABEL_LAYOUT.new()
	var rig: Node = layout.call("_rig_in_neutral_pose", LABEL_LAYOUT.CLOSE_APART_M)
	rig.set("pickup_hint", true)
	var rects: Dictionary = LABEL_LAYOUT._view_rects(rig)
	var overlap: String = LABEL_LAYOUT._first_overlap(rects)
	rig.free()
	if overlap != "":
		return overlap
	for key: Variant in rects:
		var rect: Rect2 = rects[key]
		for corner: Vector2 in [rect.position, rect.end]:
			var message: String = PRESET1_VIEW.outside_message(spec, Vector3(corner.x, corner.y, -1.0),
				"the corner of label '%s'" % key)
			if message != "":
				return message
	return ""


func test_main_scene_has_no_hint_without_salvage() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.call("advance_frame", 1.0 / 72.0)
	var hinted: bool = bool(main.get_node("XRRig").get("pickup_hint"))
	var due: bool = (main.get("pickup_hint") as PickupHint).is_due(
		(main.get("session") as LocalSession).current_ship(),
		(main.get("session") as LocalSession).current_salvage())
	main.free()
	if hinted != due:
		return "rig hint %s but due %s" % [hinted, due]
	return ""
