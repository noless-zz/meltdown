extends RefCounted

## Floating control labels (issue #80, PLT-5, CMF-4, ARC-3): the words read
## from the thumbstick layout, left-handed mode, remapping, the off switch and
## the rig scene that shows them, all without a headset.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"

## Every control the default right-handed layout binds, and its label.
const DEFAULT_LABELS: Dictionary = {
	"left_stick_x": "strafe left / right",
	"left_stick_y": "back / forward",
	"right_stick_x": "yaw left / right",
	"right_stick_y": "nose down / up",
	"left_grip": "roll left",
	"right_grip": "roll right",
	"left_trigger": "down",
	"right_trigger": "up",
	"left_stick_click": "boost",
}


func _compare(got: Dictionary, want: Dictionary, what: String) -> String:
	if got.size() != want.size():
		return "%s: got %d labels %s, want %d %s" % [what, got.size(), got, want.size(), want]
	for key: Variant in want:
		if str(got.get(key, "<none>")) != str(want[key]):
			return "%s: %s is '%s', want '%s'" % [what, key, got.get(key, "<none>"), want[key]]
	return ""


func _rig() -> Node:
	var scene: PackedScene = load(RIG_SCENE) as PackedScene
	if scene == null:
		return null
	var rig: Node = scene.instantiate()
	rig.call("build")
	return rig


func test_default_layout_labels_every_bound_control() -> String:
	var got: Dictionary = ControlLabels.for_layout(ThumbstickMapping.default_layout())
	return _compare(got, DEFAULT_LABELS, "default layout")


func test_unbound_controls_get_no_label() -> String:
	var got: Dictionary = ControlLabels.for_layout(ThumbstickMapping.default_layout())
	for control: String in ["left_button_lower", "left_button_upper",
			"right_button_lower", "right_button_upper", "right_stick_click"]:
		if got.has(control):
			return "%s is unbound but labelled '%s'" % [control, got[control]]
	var zero: Dictionary = ControlLabels.for_layout({"lift": {"right_trigger": 0.0}})
	if not zero.is_empty():
		return "a zero weight should give no label, got %s" % zero
	return ""


func test_left_handed_moves_labels_to_the_other_hand() -> String:
	var got: Dictionary = ControlLabels.for_layout(ThumbstickMapping.default_layout(), true)
	var want: Dictionary = {}
	for control: String in DEFAULT_LABELS:
		want[ControlLabels.other_hand(control)] = DEFAULT_LABELS[control]
	var message: String = _compare(got, want, "left-handed")
	if message != "":
		return message
	if got.get("right_stick_click", "") != "boost":
		return "left-handed boost should be on the right stick click"
	return ""


func test_remapping_one_axis_changes_its_label() -> String:
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout["lift"] = {"right_button_upper": 1.0, "right_button_lower": -1.0}
	var got: Dictionary = ControlLabels.for_layout(layout)
	if got.has("right_trigger") or got.has("left_trigger"):
		return "triggers still labelled after lift moved to the buttons: %s" % got
	if got.get("right_button_upper", "") != "up" or got.get("right_button_lower", "") != "down":
		return "buttons should read up and down, got %s" % got
	if got.get("right_stick_x", "") != DEFAULT_LABELS["right_stick_x"]:
		return "an untouched axis changed its label"
	return ""


func test_negative_stick_weight_reverses_the_words() -> String:
	var got: Dictionary = ControlLabels.for_layout({"yaw": {"right_stick_x": -1.0}})
	if got.get("right_stick_x", "") != "yaw right / left":
		return "a reversed yaw stick should read 'yaw right / left', got '%s'" % got.get("right_stick_x", "")
	return ""


func test_invert_pitch_reverses_the_pitch_words() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.invert_pitch = true
	var got: Dictionary = ControlLabels.for_mapping(mapping)
	if got.get("right_stick_y", "") != "nose up / down":
		return "inverted pitch should read 'nose up / down', got '%s'" % got.get("right_stick_y", "")
	return ""


func test_two_actions_on_one_control_are_both_named() -> String:
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout["afterburner"] = {"right_trigger": 1.0}
	var got: Dictionary = ControlLabels.for_layout(layout)
	var text: String = str(got.get("right_trigger", ""))
	if not ("up" in text and "boost" in text):
		return "right trigger should name up and boost, got '%s'" % text
	return ""


func test_labels_split_by_hand() -> String:
	var labels: Dictionary = ControlLabels.for_layout(ThumbstickMapping.default_layout())
	var left: Dictionary = ControlLabels.for_hand(labels, "left")
	var right: Dictionary = ControlLabels.for_hand(labels, "right")
	if left.size() + right.size() != labels.size():
		return "hands should share all %d labels, got %d + %d" % [labels.size(), left.size(), right.size()]
	if left.get("trigger", "") != "down" or right.get("trigger", "") != "up":
		return "trigger labels per hand wrong: %s / %s" % [left, right]
	return ""


func test_every_bindable_control_has_a_label_position() -> String:
	for control: String in ThumbstickMapping.CONTROLS:
		var part: String = control.trim_prefix("left_").trim_prefix("right_")
		if not ControllerModel.LABEL_POSITIONS.has(part):
			return "no label position for %s" % part
	return ""


func test_rig_scene_shows_default_labels() -> String:
	var rig: Node = _rig()
	if rig == null:
		return "%s did not load" % RIG_SCENE
	var left: ControllerModel = rig.call("model_for", "left") as ControllerModel
	var right: ControllerModel = rig.call("model_for", "right") as ControllerModel
	var message: String = ""
	if left == null or right == null:
		message = "rig has no controller model on each hand"
	else:
		var shown: Dictionary = {}
		for part: Variant in left.label_texts():
			shown["left_" + str(part)] = left.label_texts()[part]
		for part: Variant in right.label_texts():
			shown["right_" + str(part)] = right.label_texts()[part]
		message = _compare(shown, DEFAULT_LABELS, "rig labels")
		if message == "" and (left.get_node_or_null("Handle") == null or right.get_node_or_null("Stick") == null):
			message = "controller shape parts are missing"
	rig.free()
	return message


func test_rig_rebuilds_labels_on_remap_and_left_handed() -> String:
	var rig: Node = _rig()
	if rig == null:
		return "%s did not load" % RIG_SCENE
	var mapping: ThumbstickMapping = rig.get("mapping") as ThumbstickMapping
	var message: String = ""
	# A remap made in place, as a settings menu would, is picked up per frame.
	mapping.layout["lift"] = {"right_button_upper": 1.0}
	rig.call("_process", 0.0)
	var right: ControllerModel = rig.call("model_for", "right") as ControllerModel
	if right.label_texts().get("button_upper", "") != "up" or right.label_texts().has("trigger"):
		message = "remap not shown: %s" % right.label_texts()
	if message == "":
		mapping.left_handed = true
		rig.call("_process", 0.0)
		var left: ControllerModel = rig.call("model_for", "left") as ControllerModel
		if left.label_texts().get("button_upper", "") != "up":
			message = "left-handed not shown: %s" % left.label_texts()
		elif left.label_texts().get("stick_click", "") != "" or right.label_texts().get("stick_click", "") != "boost":
			message = "boost should move to the right stick click: %s / %s" % [left.label_texts(), right.label_texts()]
	rig.free()
	return message


func test_show_labels_false_hides_them() -> String:
	var rig: Node = _rig()
	if rig == null:
		return "%s did not load" % RIG_SCENE
	var message: String = ""
	var left: ControllerModel = rig.call("model_for", "left") as ControllerModel
	var right: ControllerModel = rig.call("model_for", "right") as ControllerModel
	if not (left.labels_visible() and right.labels_visible()):
		message = "labels should be on by default"
	rig.set("show_labels", false)
	if message == "" and (left.labels_visible() or right.labels_visible()):
		message = "show_labels = false left labels visible"
	if message == "" and not left.visible:
		message = "hiding labels should not hide the controller"
	rig.set("show_labels", true)
	if message == "" and not (left.labels_visible() and right.labels_visible()):
		message = "show_labels = true did not bring them back"
	rig.free()
	return message


func test_labels_do_not_change_the_mapping() -> String:
	var rig: Node = _rig()
	if rig == null:
		return "%s did not load" % RIG_SCENE
	var mapping: ThumbstickMapping = rig.get("mapping") as ThumbstickMapping
	var before: String = var_to_str(mapping.layout)
	rig.call("refresh_labels")
	rig.set("show_labels", false)
	var after: String = var_to_str(mapping.layout)
	var handed: bool = mapping.left_handed
	rig.free()
	if before != after or handed:
		return "building labels changed the mapping"
	return ""
