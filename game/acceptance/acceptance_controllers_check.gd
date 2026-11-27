class_name AcceptanceControllersCheck
extends RefCounted

## The `controllers_bound` acceptance check (#717, #153, DEV-6, PLT-5): both
## hands hold a tracked controller, and every control the flight layout uses
## has a binding, on that hand, in the interaction profile the runtime chose.
## The Monado smoke test binds poses only (decision record 0002), so without
## this nothing on the Quest confirms the Touch bindings before a replay is
## trusted. Kept out of `AcceptanceRunner` so that file stays short.
##
## Reading goes through two callables, as in `ControllerSampler`, so tests can
## stand in for a headset:
## - `tracked.call(hand: String) -> bool`, hand `"left"` or `"right"`
## - `profile.call(hand: String) -> String`, the interaction profile path
## `bindings` holds the action map as plain data: profile path -> Array of
## "action /user/hand/<hand>/..." pairs.
##
## In an unattended run (#1436) nobody wears the headset and the controllers
## sleep, so untracked hands are reported skipped, as a locked headset is; an
## attended run still fails. The device script says which it is with the
## intent extra `meltdown_unattended=1` (or `--acceptance-unattended`).

const HANDS: Array[String] = ["left", "right"]
const DEFAULT_ACTION_MAP: String = "res://openxr_action_map.tres"
const UNATTENDED_EXTRA: String = "meltdown_unattended"
const UNATTENDED_ARG: String = "--acceptance-unattended"
## A layout control's name after its hand -> the OpenXR action
## `ControllerSampler` reads it from.
const CONTROL_ACTIONS: Dictionary[String, String] = {
	"stick_x": "primary", "stick_y": "primary", "trigger": "trigger", "grip": "grip",
	"button_lower": "ax_button", "button_upper": "by_button", "stick_click": "primary_click",
}

var tracked: Callable
var profile: Callable
var bindings: Dictionary = {}
## The flight layout (`ThumbstickMapping.layout`): action -> {control: weight}.
var layout: Dictionary = {}
## Untracked hands are skipped, not failed: nobody is wearing the headset.
var unattended: bool = false


func _init(p_tracked: Callable, p_profile: Callable, p_bindings: Dictionary,
		p_layout: Dictionary = ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE).layout) -> void:
	tracked = p_tracked
	profile = p_profile
	bindings = p_bindings
	layout = p_layout


## A check that reads the runtime's hand trackers and the project's action map.
static func live() -> AcceptanceControllersCheck:
	var is_tracked: Callable = func(hand: String) -> bool:
		var tracker: XRPositionalTracker = _tracker(hand)
		if tracker == null or not tracker.has_pose(&"default"):
			return false
		return tracker.get_pose(&"default").has_tracking_data
	var hand_profile: Callable = func(hand: String) -> String:
		var tracker: XRPositionalTracker = _tracker(hand)
		return tracker.profile if tracker != null else ""
	var path: String = str(ProjectSettings.get_setting("xr/openxr/default_action_map", DEFAULT_ACTION_MAP))
	var check: AcceptanceControllersCheck = AcceptanceControllersCheck.new(is_tracked, hand_profile,
		map_bindings(load(path) as OpenXRActionMap))
	var runtime: Object = InstallerProbe.android_runtime()
	check.unattended = unattended_requested(OS.get_cmdline_user_args(),
		InstallerProbe.intent_extra(runtime, UNATTENDED_EXTRA) if runtime != null else "")
	return check


## Whether the run was started unattended, by switch or by intent extra.
static func unattended_requested(user_args: PackedStringArray, intent_value: String) -> bool:
	if user_args.has(UNATTENDED_ARG):
		return true
	return intent_value.strip_edges() in ["1", "true", "yes"]


## Every profile of `map` as "action path" pairs; empty when there is no map.
static func map_bindings(map: OpenXRActionMap) -> Dictionary:
	var result: Dictionary = {}
	if map == null:
		return result
	for ip: OpenXRInteractionProfile in map.interaction_profiles:
		var pairs: Array[String] = []
		for i: int in range(ip.get_binding_count()):
			var binding: OpenXRIPBinding = ip.get_binding(i)
			if binding.action != null:
				pairs.append("%s %s" % [binding.action.resource_name, binding.binding_path])
		result[ip.interaction_profile_path] = pairs
	return result


## Each control the layout binds with a non-zero weight, as
## [flight action, control, hand, OpenXR action], in layout order.
static func needed(p_layout: Dictionary) -> Array[Array]:
	var result: Array[Array] = []
	for action: Variant in p_layout:
		var controls: Dictionary = p_layout[action]
		for control: Variant in controls:
			if is_zero_approx(float(controls[control])):
				continue
			var name: String = str(control)
			var hand: String = name.get_slice("_", 0)
			result.append([str(action), name, hand, CONTROL_ACTIONS.get(name.substr(hand.length() + 1), "")])
	return result


## Whether both hands are tracked and report a profile, so the check can judge.
func settled() -> bool:
	for hand: String in HANDS:
		if not bool(tracked.call(hand)) or str(profile.call(hand)) == "":
			return false
	return true


## [result, message] for the check, adding the profiles and any unbound
## controls to `measurements`. Without an OpenXR runtime it is skipped, or
## fails when `required`.
func run(xr_available: bool, required: bool, measurements: Dictionary) -> Array:
	if not xr_available:
		return [AcceptanceReport.RESULT_FAIL if required else AcceptanceReport.RESULT_SKIPPED,
			"no OpenXR runtime"]
	return judge(measurements)


func judge(measurements: Dictionary) -> Array:
	var profiles: Dictionary = {}
	var untracked: Array[String] = []
	for hand: String in HANDS:
		profiles[hand] = str(profile.call(hand))
		if not bool(tracked.call(hand)):
			untracked.append(hand)
	measurements["controllers_profile"] = profiles
	var unbound: Array[String] = []
	for entry: Array in needed(layout):
		var pairs: Array = bindings.get(profiles[entry[2]], [])
		var prefix: String = "%s /user/hand/%s/" % [entry[3], entry[2]]
		if entry[3] == "" or not pairs.any(func(pair: String) -> bool: return pair.begins_with(prefix)):
			unbound.append("%s (%s)" % [entry[0], entry[1]])
	measurements["controllers_unbound"] = unbound
	var problems: PackedStringArray = PackedStringArray()
	for hand: String in untracked:
		problems.append("the %s controller is not tracked" % hand)
	if not unbound.is_empty():
		problems.append("unbound in %s: %s" % [_profile_names(profiles), ", ".join(unbound)])
	if not untracked.is_empty() and unattended:
		# Untracked hands give no profile, so the bindings cannot be judged either.
		return [AcceptanceReport.RESULT_SKIPPED, "%s: unattended run, the headset is not worn and the controllers are asleep"
			% "; ".join(problems.slice(0, untracked.size()))]
	if not problems.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "; ".join(problems)]
	return [AcceptanceReport.RESULT_PASS, "both hands tracked, every flight control bound in %s"
		% _profile_names(profiles)]


static func _profile_names(profiles: Dictionary) -> String:
	if profiles["left"] == profiles["right"]:
		return str(profiles["left"]) if profiles["left"] != "" else "no profile"
	return "left %s, right %s" % [profiles["left"], profiles["right"]]


static func _tracker(hand: String) -> XRPositionalTracker:
	return XRServer.get_tracker(&"left_hand" if hand == "left" else &"right_hand") as XRPositionalTracker
