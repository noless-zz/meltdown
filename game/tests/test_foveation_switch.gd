extends RefCounted

## `--foveation=<0..3>`, `--foveation-dynamic=on|off` and their intent extras
## (#738, part 2 of #734; PRF-1, PRF-2, GFX-1, DEV-6). The interface is a
## stand-in, so nothing here needs a headset.

const FakeRuntime: GDScript = preload("res://tests/fake_foveation_runtime.gd")
var NONE: PackedStringArray = PackedStringArray()


func test_each_level_parses_from_arguments_and_intent_extras() -> String:
	for value: int in range(FoveationSwitch.MAX_LEVEL + 1):
		var from_arg: FoveationSwitch = FoveationSwitch.parse(
			PackedStringArray(["--foveation=%d" % value]), "", "")
		var from_extra: FoveationSwitch = FoveationSwitch.parse(NONE, " %d " % value, "")
		for chosen: FoveationSwitch in [from_arg, from_extra]:
			if not chosen.has_level or chosen.level != value or chosen.has_dynamic:
				return "level %d: got has_level=%s level=%d has_dynamic=%s" % [
					value, chosen.has_level, chosen.level, chosen.has_dynamic]
	return ""


func test_both_dynamic_values_parse_from_arguments_and_intent_extras() -> String:
	for text: String in ["on", "off"]:
		var from_arg: FoveationSwitch = FoveationSwitch.parse(
			PackedStringArray(["--foveation-dynamic=" + text]), "", "")
		var from_extra: FoveationSwitch = FoveationSwitch.parse(NONE, "", text)
		for chosen: FoveationSwitch in [from_arg, from_extra]:
			if not chosen.has_dynamic or chosen.dynamic != (text == "on") or chosen.has_level:
				return "dynamic %s: got has_dynamic=%s dynamic=%s has_level=%s" % [
					text, chosen.has_dynamic, chosen.dynamic, chosen.has_level]
	return ""


func test_an_argument_wins_over_the_extra_and_the_last_argument_counts() -> String:
	var args: PackedStringArray = PackedStringArray(
		["--foveation=1", "--foveation=2", "--foveation-dynamic=on"])
	var chosen: FoveationSwitch = FoveationSwitch.parse(args, "3", "off")
	if chosen.level != 2 or not chosen.dynamic:
		return "got level %d dynamic %s, expected 2 and true" % [chosen.level, chosen.dynamic]
	return ""


func test_bad_values_are_ignored_with_a_warning_naming_them() -> String:
	var cases: Array[Array] = [
		[PackedStringArray(["--foveation=7"]), "", "", "\"7\""],
		[PackedStringArray(["--foveation=-1"]), "", "", "\"-1\""],
		[PackedStringArray(["--foveation=high"]), "", "", "\"high\""],
		[NONE, "12", "", "\"12\""],
		[PackedStringArray(["--foveation-dynamic=maybe"]), "", "", "\"maybe\""],
		[NONE, "", "true", "\"true\""],
	]
	for case: Array in cases:
		var chosen: FoveationSwitch = FoveationSwitch.parse(case[0], case[1], case[2])
		if chosen.is_switched():
			return "%s / \"%s\" / \"%s\" was accepted" % [case[0], case[1], case[2]]
		if chosen.warnings.size() != 1 or not chosen.warnings[0].contains(case[3]):
			return "%s: warnings %s do not name %s" % [case[0], chosen.warnings, case[3]]
		var runtime: RefCounted = FakeRuntime.new(0, false)
		chosen.begin(runtime)
		if not runtime.writes.is_empty():
			return "%s: the default was changed: %s" % [case[0], runtime.writes]
	return ""


func test_a_bad_value_leaves_the_other_switch_in_force() -> String:
	var args: PackedStringArray = PackedStringArray(["--foveation=7", "--foveation-dynamic=off"])
	var chosen: FoveationSwitch = FoveationSwitch.parse(args, "", "")
	if chosen.has_level or not chosen.has_dynamic or chosen.dynamic:
		return "expected only dynamic off, got has_level=%s has_dynamic=%s dynamic=%s" % [
			chosen.has_level, chosen.has_dynamic, chosen.dynamic]
	return ""


func test_nothing_is_applied_without_a_switch() -> String:
	var chosen: FoveationSwitch = FoveationSwitch.parse(PackedStringArray(["--level=g2"]), "", "")
	var runtime: RefCounted = FakeRuntime.new(0, false)
	chosen.begin(runtime)
	if not runtime.writes.is_empty():
		return "wrote %s without a switch" % [runtime.writes]
	var expected: String = 'MELTDOWN_FOVEATION {"level":0,"dynamic":false,"source":"default"}'
	if chosen.lines != PackedStringArray([expected]):
		return "start lines %s, expected [%s]" % [chosen.lines, expected]
	return ""


func test_the_seam_receives_the_chosen_values() -> String:
	var args: PackedStringArray = PackedStringArray(["--foveation=2", "--foveation-dynamic=on"])
	var chosen: FoveationSwitch = FoveationSwitch.parse(args, "", "")
	var runtime: RefCounted = FakeRuntime.new(0, false)
	chosen.begin(runtime)
	if str(runtime.writes) != str(["level=2", "dynamic=true"]):
		return "writes %s, expected level=2 then dynamic=true" % [runtime.writes]
	var expected: String = 'MELTDOWN_FOVEATION {"level":2,"dynamic":true,"source":"switch"}'
	if chosen.lines != PackedStringArray([expected]):
		return "start lines %s, expected [%s]" % [chosen.lines, expected]
	return ""


func test_the_change_line_is_printed_only_on_a_change() -> String:
	var chosen: FoveationSwitch = FoveationSwitch.parse(PackedStringArray(["--foveation=3"]), "", "")
	var runtime: RefCounted = FakeRuntime.new(0, true)
	chosen.advance(5.0)  # Before the session: nothing to read.
	if not chosen.lines.is_empty():
		return "printed before the session began: %s" % [chosen.lines]
	chosen.begin(runtime)
	for frame: int in 300:
		chosen.advance(1.0 / 72.0)
	if chosen.lines.size() != 1:
		return "printed %d lines with no change, expected 1" % chosen.lines.size()
	runtime.foveation_level = 1  # The runtime lowers the level on its own.
	chosen.advance(0.5)
	if chosen.lines.size() != 1:
		return "read back sooner than once a second"
	chosen.advance(0.5)
	var expected: String = 'MELTDOWN_FOVEATION {"level":1,"dynamic":true,"source":"switch"}'
	if chosen.lines.size() != 2 or chosen.lines[1] != expected:
		return "after the change got %s, expected a second line %s" % [chosen.lines, expected]
	for frame: int in 300:
		chosen.advance(1.0 / 72.0)
	if chosen.lines.size() != 2:
		return "printed again without a further change: %s" % [chosen.lines]
	return ""
