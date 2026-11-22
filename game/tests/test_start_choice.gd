extends RefCounted

## Where a start of the game lands (#1171, CRW-2, PLT-2, RUN-8): a normal start
## opens the hub; `--run`, `--level`, `--seed`, `--acceptance`, their intent
## extras and the first launch's flight test go straight into flight. The
## start-up hub's run takes a fresh seed; a start that flies keeps its source.


func _check(args: Array[String], extras: Dictionary, done: bool, want: String) -> String:
	var got: String = StartChoice.choose(PackedStringArray(args), extras, done)
	return "" if got == want else "args %s, extras %s, test done %s: %s, expected %s" % [args, extras, done, got, want]


func test_a_normal_start_opens_the_hub() -> String:
	return _check([], {}, true, StartChoice.HUB)


func test_switches_that_change_no_level_still_open_the_hub() -> String:
	for arg: String in ["--comfort=2", "--controls=gripped", "--foveation=off", "--xr-smoke-frames=90"]:
		var failed: String = _check([arg], {}, true, StartChoice.HUB)
		if failed != "":
			return failed
	return ""


func test_blank_intent_extras_open_the_hub() -> String:
	return _check([], {LevelSwitch.INTENT_EXTRA: "", LevelSwitch.SEED_INTENT_EXTRA: "  ",
		LevelSwitch.RUN_INTENT_EXTRA: "", AcceptanceRunner.INTENT_EXTRA: ""}, true, StartChoice.HUB)


func test_each_launch_switch_flies_at_once() -> String:
	var switches: Array[String] = ["--run=12345", "--run=random", "--level=g2", "--seed=31", "--seed=random",
		"--acceptance=m4"]
	for arg: String in switches:
		var failed: String = _check([arg], {}, true, StartChoice.FLIGHT)
		if failed != "":
			return failed
	return ""


func test_a_switch_with_a_bad_value_still_flies() -> String:
	# Today it flies the tunnel and prints the value; the hub must not hide the typo.
	for arg: String in ["--level=G2!", "--seed=abc", "--run="]:
		var failed: String = _check([arg], {}, true, StartChoice.FLIGHT)
		if failed != "":
			return failed
	return ""


func test_each_intent_extra_flies_at_once() -> String:
	var extras: Dictionary = {LevelSwitch.INTENT_EXTRA: "g2", LevelSwitch.SEED_INTENT_EXTRA: "31",
		LevelSwitch.RUN_INTENT_EXTRA: "12345", AcceptanceRunner.INTENT_EXTRA: "m4"}
	for extra: String in extras:
		var failed: String = _check([], {extra: extras[extra]}, true, StartChoice.FLIGHT)
		if failed != "":
			return failed
	return ""


func test_the_first_launch_flight_test_flies_at_once() -> String:
	return _check([], {}, false, StartChoice.FLIGHT)


func test_from_launch_reads_the_saved_flight_test_flag() -> String:
	var path: String = "user://t1171_comfort.json"
	var choice: ComfortChoice = ComfortChoice.new()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var first: String = StartChoice.from_launch(path)
	choice.finish_test(2)
	choice.save_to(path)
	var later: String = StartChoice.from_launch(path)
	DirAccess.remove_absolute(path)
	# The test runner is started with no user arguments and no intent extras.
	if first != StartChoice.FLIGHT or later != StartChoice.HUB:
		return "no file: %s, test done: %s" % [first, later]
	return ""


func test_a_scene_outside_the_tree_never_opens_the_hub() -> String:
	var host: Node = Node.new()
	var opens: bool = StartChoice.opens_hub(host)
	host.free()
	return "a unit test's scene opened the hub" if opens else ""


func test_a_start_that_flies_keeps_its_source() -> String:
	for requested: String in ["", "seed:31", "run:12345", "res://data/levels/g2_level.json"]:
		var got: String = StartChoice.source(false, requested, func() -> int: return 7)
		if got != requested:
			return "%s became %s" % [requested, got]
	return ""


func test_the_start_up_hub_takes_a_new_run_with_a_picked_seed() -> String:
	var got: String = StartChoice.source(true, "", func() -> int: return 424242)
	if got != LevelSwitch.RUN_PREFIX + "424242":
		return "the hub's run is %s" % got
	var level_start: LevelStart = LevelStart.new()
	var profile_path: String = "user://t1171_profile.json"
	var run: RunWiring = level_start.choose(StartChoice.source(true, ""), ProfileStore.new(profile_path))
	for each: String in [profile_path, SafeFileWrite.temp_path(profile_path)]:
		if FileAccess.file_exists(each):
			DirAccess.remove_absolute(each)
	if run == null or not run.active() or run.state.plan.run_seed < LevelSwitch.RANDOM_SEED_MIN:
		return "a random pick did not start a run"
	return ""
