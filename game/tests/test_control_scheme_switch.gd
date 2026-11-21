extends RefCounted

## `--controls=thumbsticks|gripped` and the `meltdown_controls` intent extra
## (#739, PLT-5): parsing, the default, bad values, the start line, and which
## mapping flies each kind of sampled values.

var NONE: PackedStringArray = PackedStringArray()


func test_the_default_is_thumbsticks() -> String:
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(NONE, "")
	if chosen.scheme != ControlSchemeSwitch.THUMBSTICKS or chosen.is_gripped() \
			or not chosen.warnings.is_empty():
		return "default: %s, warnings %s" % [chosen.scheme, chosen.warnings]
	return ""


func test_arguments_and_intent_extras_choose_the_scheme() -> String:
	var cases: Array = [
		[PackedStringArray(["--controls=gripped"]), "", "gripped"],
		[NONE, " gripped ", "gripped"],
		[PackedStringArray(["--controls=thumbsticks"]), "gripped", "thumbsticks"],
		[PackedStringArray(["--controls=gripped", "--controls=thumbsticks"]), "", "thumbsticks"],
		[PackedStringArray(["--level=x", "--controls=gripped"]), "thumbsticks", "gripped"],
	]
	for case: Array in cases:
		var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(case[0], case[1])
		if chosen.scheme != case[2] or not chosen.warnings.is_empty():
			return "%s / \"%s\": got %s, warnings %s" % [case[0], case[1], chosen.scheme, chosen.warnings]
	return ""


func test_a_bad_value_is_ignored_with_a_warning_naming_it() -> String:
	for chosen: ControlSchemeSwitch in [
			ControlSchemeSwitch.parse(PackedStringArray(["--controls=joystick"]), ""),
			ControlSchemeSwitch.parse(NONE, "joystick")]:
		if chosen.scheme != ControlSchemeSwitch.THUMBSTICKS:
			return "a bad value chose %s" % chosen.scheme
		if chosen.warnings.size() != 1 or not chosen.warnings[0].contains("\"joystick\""):
			return "warnings %s do not name the bad value" % chosen.warnings
	return ""


func test_the_scheme_is_printed_once_with_the_hand_setting() -> String:
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(
		PackedStringArray(["--controls=gripped"]), "")
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.left_handed = true
	chosen.map_values(mapping, ControllerSampler.idle_values())
	chosen.map_values(mapping, ControllerSampler.idle_values())
	var expected: String = 'MELTDOWN_CONTROLS {"scheme":"gripped","left_handed":true,"invert_pitch":false}'
	if chosen.lines != PackedStringArray([expected]):
		return "lines %s, expected one %s" % [chosen.lines, expected]
	return ""


func test_values_without_poses_fly_the_thumbsticks() -> String:
	# The keyboard gives no poses, so flat play flies whatever the switch says.
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.parse(
		PackedStringArray(["--controls=gripped"]), "")
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_stick"] = Vector2(0.0, 1.0)
	var input: ShipInput = chosen.map_values(mapping, values)
	if input.thrust_q != ControllerSampler.map_values(mapping, values).thrust_q \
			or input.thrust_q == Vector3i.ZERO:
		return "keyboard-like values under gripped gave %s" % input.thrust_q
	return ""


func test_each_scheme_reads_its_own_controls() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_stick"] = Vector2(0.0, 1.0)
	values["left_grip"] = 1.0
	values[ControllerSampler.POSES] = {"left": Transform3D.IDENTITY, "right": Transform3D.IDENTITY}
	var thumbs: ControlSchemeSwitch = ControlSchemeSwitch.parse(NONE, "")
	var gripped: ControlSchemeSwitch = ControlSchemeSwitch.parse(NONE, "gripped")
	if thumbs.map_values(mapping, values).thrust_q == Vector3i.ZERO:
		return "the thumbsticks scheme ignored the left stick"
	if gripped.map_values(mapping, values).thrust_q != Vector3i.ZERO:
		return "the gripped scheme read the left stick"
	if not gripped.gripped.holds("left"):
		return "the gripped scheme did not grab with the left grip"
	return ""


func test_the_sampler_reports_poses_only_with_a_pose_reader() -> String:
	var tracking: Callable = func(_hand: String) -> bool: return true
	var read: Callable = func(_hand: String, _action: String) -> Variant: return null
	var pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.1, 1.0, -0.2))
	var with_pose: ControllerSampler = ControllerSampler.new(tracking, read,
		func(_hand: String) -> Transform3D: return pose)
	var without: ControllerSampler = ControllerSampler.new(tracking, read)
	var poses: Dictionary = with_pose.sample().get(ControllerSampler.POSES, {})
	if poses.get("left") != pose or poses.get("right") != pose:
		return "poses %s" % poses
	if without.sample().has(ControllerSampler.POSES):
		return "a sampler without a pose reader reported poses"
	return ""
