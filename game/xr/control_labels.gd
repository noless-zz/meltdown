class_name ControlLabels
extends RefCounted

## Short words naming what each physical control does under a thumbstick
## layout (PLT-5), for the floating labels on the controller shapes. A new
## player learns the controls from them before the flight test (CMF-4).
##
## It only reads the layout: nothing here writes input or ship state (ARC-3).
## Labels follow the layout and left-handed mode, so remapping and swapping
## hands update them without code changes.

## Ship axis or button action -> [word for the negative direction, word for
## the positive direction]. Directions follow `ThumbstickMapping`: `strafe`
## + right, `lift` + up, `forward` + ahead, `pitch` + nose up, `yaw` + nose
## right, `roll` + right wing down. A button action has one word for both.
const WORDS: Dictionary = {
	"strafe": ["strafe left", "strafe right"],
	"lift": ["down", "up"],
	"forward": ["back", "forward"],
	"pitch": ["nose down", "nose up"],
	"yaw": ["yaw left", "yaw right"],
	"roll": ["roll left", "roll right"],
	"afterburner": ["boost", "boost"],
}
## Controls that report both directions (-1..1). Every other control reports
## 0..1, so only the sign of its weight picks the word.
const TWO_WAY_CONTROLS: Array[String] = [
	"left_stick_x", "left_stick_y", "right_stick_x", "right_stick_y",
]
## Joins the two directions of a stick axis, negative first: left before
## right, pulled back before pushed away.
const DIRECTION_SEPARATOR: String = " / "
## Joins the actions of a control bound to more than one.
const ACTION_SEPARATOR: String = ", "


## Physical control -> its label, for every control the layout binds with a
## non-zero weight. In left-handed mode each binding is shown on the other
## hand's control, where `ThumbstickMapping` reads it from. `invert_pitch`
## swaps the pitch words to match the mapping.
static func for_layout(layout: Dictionary, left_handed: bool = false,
		invert_pitch: bool = false) -> Dictionary:
	var actions: Dictionary = {}
	for action: Variant in layout:
		var bindings: Dictionary = layout[action]
		for control: Variant in bindings:
			var weight: float = float(bindings[control])
			if is_zero_approx(weight):
				continue
			if str(action) == "pitch" and invert_pitch:
				weight = -weight
			var physical: String = other_hand(str(control)) if left_handed else str(control)
			if not actions.has(physical):
				actions[physical] = []
			(actions[physical] as Array).append(_words_for(str(action), str(control), weight))
	var labels: Dictionary = {}
	for physical: String in actions:
		labels[physical] = ACTION_SEPARATOR.join(PackedStringArray(actions[physical]))
	return labels


## The labels for a mapping's current layout, hand and pitch settings.
static func for_mapping(mapping: ThumbstickMapping) -> Dictionary:
	return for_layout(mapping.layout, mapping.left_handed, mapping.invert_pitch)


## The labels of one hand (`"left"` or `"right"`), keyed by the control name
## without the hand prefix, for example `"trigger"` or `"stick_x"`.
static func for_hand(labels: Dictionary, hand: String) -> Dictionary:
	var prefix: String = hand + "_"
	var result: Dictionary = {}
	for control: String in labels:
		if control.begins_with(prefix):
			result[control.trim_prefix(prefix)] = labels[control]
	return result


## The same control on the other hand; names without a hand stay as they are.
static func other_hand(control: String) -> String:
	if control.begins_with("left_"):
		return "right_" + control.trim_prefix("left_")
	if control.begins_with("right_"):
		return "left_" + control.trim_prefix("right_")
	return control


static func _words_for(action: String, control: String, weight: float) -> String:
	var pair: Array = WORDS.get(action, [action, action])
	var negative: String = str(pair[0])
	var positive: String = str(pair[1])
	if weight < 0.0:
		var swap: String = negative
		negative = positive
		positive = swap
	if not TWO_WAY_CONTROLS.has(control):
		return positive
	if negative == positive:
		return positive
	return _join_directions(negative, positive)


## "yaw left" and "yaw right" become "yaw left / right", which fits a label.
static func _join_directions(first: String, second: String) -> String:
	var first_words: PackedStringArray = first.split(" ")
	var second_words: PackedStringArray = second.split(" ")
	if first_words.size() == 2 and second_words.size() == 2 and first_words[0] == second_words[0]:
		return first + DIRECTION_SEPARATOR + second_words[1]
	return first + DIRECTION_SEPARATOR + second
