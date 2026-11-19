extends RefCounted

## `--seed=random` or `random` in the `meltdown_seed` intent extra flies a fresh
## seed (#533, DEV-6, G3). The picker is injected where the test needs a known
## value, so nothing here depends on what the unseeded generator returns.

const G2_FILE: String = "res://data/levels/g2_level.json"


func _picks(value: int) -> Callable:
	return func() -> int: return value


func _corners(boxes: Array[BoxBounds]) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for box: BoxBounds in boxes:
		corners.append_array([box.min_corner, box.max_corner])
	return corners


func test_random_argument_or_intent_gives_the_picked_seed() -> String:
	var none: PackedStringArray = PackedStringArray()
	var cases: Array[Array] = [
		[PackedStringArray(["--seed=random"]), "", 41, "seed:41"],
		[none, "random", 42, "seed:42"],
		[none, " random ", 43, "seed:43"],
		[PackedStringArray(["--seed=7", "--seed=random"]), "", 44, "seed:44"],
		[PackedStringArray(["--seed=random", "--seed=7"]), "", 45, "seed:7"],
		[PackedStringArray(["--seed=7"]), "random", 46, "seed:7"],
	]
	for case: Array in cases:
		var got: String = LevelSwitch.requested_source(case[0], "", case[1], _picks(case[2]))
		if got != case[3]:
			return "args %s, intent \"%s\", picker %d: got \"%s\", expected \"%s\"" % [
					case[0], case[1], case[2], got, case[3]]
	return ""


func test_two_random_launches_can_differ() -> String:
	var args: PackedStringArray = PackedStringArray(["--seed=random"])
	var first: String = LevelSwitch.requested_source(args, "", "", _picks(1))
	var second: String = LevelSwitch.requested_source(args, "", "", _picks(999999999))
	if first == second:
		return "two different picks both gave \"%s\"" % first
	return ""


func test_the_default_picker_stays_in_range() -> String:
	for attempt: int in 200:
		var picked: int = LevelSwitch.random_seed()
		if picked < LevelSwitch.RANDOM_SEED_MIN or picked > LevelSwitch.RANDOM_SEED_MAX:
			return "random_seed gave %d, outside %d..%d" % [picked, LevelSwitch.RANDOM_SEED_MIN,
					LevelSwitch.RANDOM_SEED_MAX]
	var source: String = LevelSwitch.requested_source(PackedStringArray(["--seed=random"]), "", "")
	var level_seed: int = LevelSwitch.seed_from(source.trim_prefix(LevelSwitch.SEED_PREFIX))
	if not source.begins_with(LevelSwitch.SEED_PREFIX) or level_seed < LevelSwitch.RANDOM_SEED_MIN \
			or level_seed > LevelSwitch.RANDOM_SEED_MAX:
		return "--seed=random without a picker gave \"%s\"" % source
	return ""


func test_other_words_are_still_rejected() -> String:
	for bad: String in ["Random", "RANDOM", "rand", "randomly", "random7", "random random", "-random"]:
		if LevelSwitch.requested_source(PackedStringArray(["--seed=" + bad]), "", "", _picks(5)) != "":
			return "--seed=%s was accepted" % bad
		if LevelSwitch.requested_source(PackedStringArray(), "", bad, _picks(5)) != "":
			return "intent seed %s was accepted" % bad
	return ""


func test_level_still_wins_over_random() -> String:
	var cases: Array[Array] = [
		[PackedStringArray(["--level=g2", "--seed=random"]), "", ""],
		[PackedStringArray(["--seed=random"]), "g2", ""],
		[PackedStringArray(), "g2", "random"],
	]
	for case: Array in cases:
		var got: String = LevelSwitch.requested_source(case[0], case[1], case[2], _picks(5))
		if got != G2_FILE:
			return "args %s, intents \"%s\"/\"%s\": got \"%s\"" % [case[0], case[1], case[2], got]
	return ""


## The main scene gets the same source for a picked seed as for `--seed=<n>`,
## so the session it builds (walls, start, replay seed) is the same too.
func test_a_picked_seed_flies_as_the_numbered_seed() -> String:
	var picked: String = LevelSwitch.requested_source(PackedStringArray(["--seed=random"]), "", "", _picks(7))
	var numbered: String = LevelSwitch.requested_source(PackedStringArray(["--seed=7"]), "", "")
	if picked != numbered:
		return "random picking 7 gave \"%s\", --seed=7 gives \"%s\"" % [picked, numbered]
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var by_pick: Node = scene.instantiate()
	var by_number: Node = scene.instantiate()
	var problem: String = ""
	if not by_pick.call("use_level", picked) or not by_number.call("use_level", numbered):
		problem = "use_level refused seed 7"
	else:
		var a: LocalSession = by_pick.get("session")
		var b: LocalSession = by_number.get("session")
		if _corners(a.sim.walls.boxes) != _corners(b.sim.walls.boxes):
			problem = "the picked seed built different walls"
		elif a.replay.run_seed != b.replay.run_seed:
			problem = "replay run_seed %d against %d" % [a.replay.run_seed, b.replay.run_seed]
		elif not a.current_ship().position.is_equal_approx(b.current_ship().position):
			problem = "the ship starts somewhere else"
	by_pick.free()
	by_number.free()
	return problem
