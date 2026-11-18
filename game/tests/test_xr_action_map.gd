extends RefCounted

## The OpenXR action map ships to the headset, so the simple-controller profile
## added for the CI smoke test (issue #571, PLT-2) must not disturb the Touch
## bindings the Quest uses (PLT-5).

const MAP_PATH: String = "res://openxr_action_map.tres"
const SIMPLE: String = "/interaction_profiles/khr/simple_controller"
const TOUCH: String = "/interaction_profiles/oculus/touch_controller"

## The pose the rig's XRController3D nodes follow (their `pose` is `default`,
## which Godot reads from the `default_pose` action).
const RIG_POSE_ACTIONS: Array[String] = ["default_pose"]

## Touch bindings as on `main` before issue #571, one "action path" pair each.
const TOUCH_BINDINGS: Array[String] = [
	"default_pose /user/hand/left/input/aim/pose",
	"default_pose /user/hand/right/input/aim/pose",
	"aim_pose /user/hand/left/input/aim/pose",
	"aim_pose /user/hand/right/input/aim/pose",
	"grip_pose /user/hand/left/input/grip/pose",
	"grip_pose /user/hand/right/input/grip/pose",
	"palm_pose /user/hand/left/input/grip_surface/pose",
	"palm_pose /user/hand/right/input/grip_surface/pose",
	"menu_button /user/hand/left/input/menu/click",
	"menu_button /user/hand/right/input/system/click",
	"ax_button /user/hand/left/input/x/click",
	"ax_button /user/hand/right/input/a/click",
	"ax_touch /user/hand/left/input/x/touch",
	"ax_touch /user/hand/right/input/a/touch",
	"by_button /user/hand/left/input/y/click",
	"by_button /user/hand/right/input/b/click",
	"by_touch /user/hand/left/input/y/touch",
	"by_touch /user/hand/right/input/b/touch",
	"trigger /user/hand/left/input/trigger/value",
	"trigger /user/hand/right/input/trigger/value",
	"trigger_click /user/hand/left/input/trigger/value",
	"trigger_click /user/hand/right/input/trigger/value",
	"trigger_touch /user/hand/left/input/trigger/touch",
	"trigger_touch /user/hand/right/input/trigger/touch",
	"grip /user/hand/left/input/squeeze/value",
	"grip /user/hand/right/input/squeeze/value",
	"grip_click /user/hand/left/input/squeeze/value",
	"grip_click /user/hand/right/input/squeeze/value",
	"primary /user/hand/left/input/thumbstick",
	"primary /user/hand/right/input/thumbstick",
	"primary_click /user/hand/left/input/thumbstick/click",
	"primary_click /user/hand/right/input/thumbstick/click",
	"primary_touch /user/hand/left/input/thumbstick/touch",
	"primary_touch /user/hand/right/input/thumbstick/touch",
	"haptic /user/hand/left/output/haptic",
	"haptic /user/hand/right/output/haptic",
]


## Every "action path" pair of one profile, sorted; null when the profile is
## missing or the map does not load.
static func _bindings(profile_path: String) -> Variant:
	var map: OpenXRActionMap = load(MAP_PATH) as OpenXRActionMap
	if map == null:
		return null
	for profile: OpenXRInteractionProfile in map.interaction_profiles:
		if profile.interaction_profile_path != profile_path:
			continue
		var pairs: Array[String] = []
		for i: int in range(profile.get_binding_count()):
			var binding: OpenXRIPBinding = profile.get_binding(i)
			pairs.append("%s %s" % [binding.action.resource_name, binding.binding_path])
		pairs.sort()
		return pairs
	return null


func test_simple_controller_binds_rig_pose_on_both_hands() -> String:
	var pairs: Variant = _bindings(SIMPLE)
	if pairs == null:
		return "action map has no %s profile" % SIMPLE
	for action: String in RIG_POSE_ACTIONS:
		for hand: String in ["left", "right"]:
			var prefix: String = "%s /user/hand/%s/input/" % [action, hand]
			var found: bool = false
			for pair: String in pairs:
				if pair.begins_with(prefix) and pair.ends_with("/pose"):
					found = true
			if not found:
				return "simple controller does not bind %s on the %s hand" % [action, hand]
	return ""


func test_simple_controller_binds_aim_and_grip_poses() -> String:
	var pairs: Variant = _bindings(SIMPLE)
	if pairs == null:
		return "action map has no %s profile" % SIMPLE
	for expected: String in [
		"aim_pose /user/hand/left/input/aim/pose",
		"aim_pose /user/hand/right/input/aim/pose",
		"grip_pose /user/hand/left/input/grip/pose",
		"grip_pose /user/hand/right/input/grip/pose",
	]:
		if not (pairs as Array).has(expected):
			return "simple controller lacks binding %s" % expected
	return ""


func test_touch_bindings_are_unchanged() -> String:
	var pairs: Variant = _bindings(TOUCH)
	if pairs == null:
		return "action map has no %s profile" % TOUCH
	var expected: Array[String] = TOUCH_BINDINGS.duplicate()
	expected.sort()
	if pairs != expected:
		var missing: Array[String] = []
		for pair: String in expected:
			if not (pairs as Array).has(pair):
				missing.append(pair)
		var extra: Array[String] = []
		for pair: String in pairs:
			if not expected.has(pair):
				extra.append(pair)
		return "Touch bindings changed: missing %s, extra %s" % [str(missing), str(extra)]
	return ""
