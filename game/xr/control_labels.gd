class_name ControlLabels
extends RefCounted

## Short words naming what each physical control does under a thumbstick
## layout (PLT-5), for the floating labels on the controller shapes. A new
## player learns the controls from them before the flight test (CMF-4).
##
## It only reads the layout: nothing here writes input or ship state (ARC-3).
## Labels follow the layout and left-handed mode, so remapping and swapping
## hands update them without code changes.
##
## Each stick gets one label drawn as a cross, with each action at the end the
## stick is pushed to: pushed away at the top, pulled back at the bottom, left
## and right on the middle line (#606). One text line per axis did not say
## which way acted. A stick click names its gesture: "click: labels, hold: map".

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
	"fire_primary": ["fire", "fire"],
	"slot_part": ["click: slot held part", "click: slot held part"],
	"show_map": ["hold: map", "hold: map"],
}
## Controls labelled in every layout, because what they do is not part of a
## layout. The reset hold (#162) stays on the left menu button in left-handed
## mode too (see `ResetHold.BUTTON`), so these never swap hands.
const FIXED_LABELS: Dictionary = {
	ResetHold.BUTTON: "reset (hold)",
}
## The label of the comfort preset button (`ThumbstickMapping.PRESET_BUTTON`),
## which no layout binds but which swaps hands with the rest (#613).
const PRESET_WORD: String = "comfort preset"
## The label of the control-label toggle (`ThumbstickMapping.LABEL_BUTTON`),
## also read outside the layout. It comes first on its control, before the
## map's hold, because the click is the shorter gesture.
const LABEL_TOGGLE_WORD: String = "click: labels"
## Replaces the slot words while the hold is empty and a part floats near
## (#600): the owner read the click as "pick up", but flying through picks up.
const PICKUP_HINT_WORD: String = "fly through to pick up"
## Controls that report both directions (-1..1). Every other control reports
## 0..1, so only the sign of its weight picks the word.
const TWO_WAY_CONTROLS: Array[String] = [
	"left_stick_x", "left_stick_y", "right_stick_x", "right_stick_y",
]
## The key of a stick's cross label, after the hand prefix.
const STICK: String = "stick"
## Between the left and right ends of a cross's middle line: the stick itself.
const CROSS_CENTRE: String = "  +  "
## The middle line when both sides share their action: left end, action,
## right end. The angle brackets point the way each end is pushed.
const SHARED_CENTRE: String = "%s  <  %s  >  %s"
## Joins the actions of a control, or of a stick end, bound to more than one.
const ACTION_SEPARATOR: String = ", "


## Physical control -> its label, for every control the layout binds with a
## non-zero weight, plus `FIXED_LABELS`, the comfort preset button and the
## label toggle. Both axes of a stick share one cross label under
## `<hand>_stick`. In left-handed mode each binding, and the two buttons, are
## shown on the other hand's control, where `ThumbstickMapping` reads them.
## `invert_pitch` swaps the pitch words to match the mapping. With
## `pickup_hint` the slot control reads `PICKUP_HINT_WORD` instead.
static func for_layout(layout: Dictionary, left_handed: bool = false,
		invert_pitch: bool = false, pickup_hint: bool = false) -> Dictionary:
	var actions: Dictionary = {}
	# Stick axis -> [words at its negative end, words at its positive end].
	var ends: Dictionary = {}
	for action: Variant in layout:
		var bindings: Dictionary = layout[action]
		for control: Variant in bindings:
			var weight: float = float(bindings[control])
			if is_zero_approx(weight):
				continue
			if str(action) == "pitch" and invert_pitch:
				weight = -weight
			var physical: String = other_hand(str(control)) if left_handed else str(control)
			var pair: Array[String] = _words_for(str(action), weight, pickup_hint)
			if TWO_WAY_CONTROLS.has(str(control)):
				if not ends.has(physical):
					ends[physical] = [[], []]
				(ends[physical][0] as Array).append(pair[0])
				(ends[physical][1] as Array).append(pair[1])
			else:
				_add(actions, physical, pair[1])
	_add(actions, _for_hand_mode(ThumbstickMapping.PRESET_BUTTON, left_handed), PRESET_WORD)
	var toggle: String = _for_hand_mode(ThumbstickMapping.LABEL_BUTTON, left_handed)
	_add(actions, toggle, LABEL_TOGGLE_WORD)
	(actions[toggle] as Array).push_front((actions[toggle] as Array).pop_back())
	var labels: Dictionary = FIXED_LABELS.duplicate()
	for physical: String in actions:
		labels[physical] = _joined(actions[physical])
	for hand: String in ["left", "right"]:
		if not ends.has(hand + "_stick_x") and not ends.has(hand + "_stick_y"):
			continue
		var x: Array = ends.get(hand + "_stick_x", [[], []])
		var y: Array = ends.get(hand + "_stick_y", [[], []])
		labels[hand + "_" + STICK] = cross(_joined(y[1]), _joined(y[0]), _joined(x[0]), _joined(x[1]))
	return labels


## The labels for a mapping's current layout, hand and pitch settings.
static func for_mapping(mapping: ThumbstickMapping, pickup_hint: bool = false) -> Dictionary:
	return for_layout(mapping.layout, mapping.left_handed, mapping.invert_pitch, pickup_hint)


## The three lines of a stick's cross: `up` (pushed away) on top, `down`
## (pulled back) at the bottom, `left` and `right` either side of the centre.
## When both sides name one action ("yaw left", "yaw right") it sits in the
## centre between them, "left  <  yaw  >  right", which keeps the cross narrow
## enough to stay inside the cockpit window.
static func cross(up: String, down: String, left: String, right: String) -> String:
	var left_words: PackedStringArray = left.split(" ")
	var right_words: PackedStringArray = right.split(" ")
	var middle: String = left + CROSS_CENTRE + right
	if left_words.size() == 2 and right_words.size() == 2 and left_words[0] == right_words[0]:
		middle = SHARED_CENTRE % [left_words[1], left_words[0], right_words[1]]
	return "%s\n%s\n%s" % [up, middle, down]


## The labels of one hand (`"left"` or `"right"`), keyed by the control name
## without the hand prefix, for example `"trigger"` or `"stick"`.
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


static func _for_hand_mode(control: String, left_handed: bool) -> String:
	return other_hand(control) if left_handed else control


static func _add(actions: Dictionary, physical: String, words: String) -> void:
	if not actions.has(physical):
		actions[physical] = []
	(actions[physical] as Array).append(words)


## [words at the control's negative end, words at its positive end].
static func _words_for(action: String, weight: float, pickup_hint: bool) -> Array[String]:
	var pair: Array = WORDS.get(action, [action, action])
	if action == "slot_part" and pickup_hint:
		pair = [PICKUP_HINT_WORD, PICKUP_HINT_WORD]
	if weight < 0.0:
		return [str(pair[1]), str(pair[0])]
	return [str(pair[0]), str(pair[1])]


static func _joined(words: Array) -> String:
	return ACTION_SEPARATOR.join(PackedStringArray(words))
