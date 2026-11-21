extends RefCounted

## The chosen shaft's `risk.robot_count` builds the run's next level busier
## (#1011, RUN-1, GEN-2, ARC-2): `RunWiring` names the level
## `seed:<n>:robots=<scale>`, `LevelSwitch.load_level` builds that source with
## `SeedLevel`'s scale, and `seed:<n>` alone still means 1.0, so a level flown
## with `--seed` and a run's first level are unchanged.

const RUN_SEED: int = 12345
## Two shafts, both always offered, so the tests can take either.
const SHAFTS: String = "{\"offer_min\": 2, \"offer_max\": 2, \"seed_salt\": 2246822519, \"shafts\": [" \
	+ "{\"kind\": \"steady\", \"label\": \"Steady\", \"risk\": {\"robot_count\": 1.0, \"alarm\": 1.0}, " \
	+ "\"reward\": {\"tier_weights\": [6, 3, 1]}}, " \
	+ "{\"kind\": \"deep\", \"label\": \"Deep\", \"risk\": {\"robot_count\": 1.3, \"alarm\": 1.1}, " \
	+ "\"reward\": {\"tier_weights\": [3, 4, 3]}}]}"
const DEEP_SCALE: float = 1.3


func _wiring() -> RunWiring:
	return RunWiring.new(RUN_SEED, null, func() -> int: return 77, "", true, SHAFTS)


## The run moved past level 1 with shaft `kind` taken; null when it would not.
func _through(kind: String) -> RunWiring:
	var run: RunWiring = _wiring()
	if run.shafts == null or run.escape_for_choice({}).is_empty() or not run.choose(kind):
		return null
	return run


static func _robots(level: LevelDef) -> String:
	var parts: Array[String] = []
	for spawn: RobotSpawn in level.robots.spawns:
		parts.append("%s %s %s" % [spawn.id, spawn.position_mm, spawn.facing_mm])
	return "|".join(parts)


func test_a_source_without_a_scale_is_unscaled() -> String:
	if LevelSwitch.source_robot_scale("seed:42") != 1.0 or LevelSwitch.source_seed("seed:42") != 42:
		return "seed:42 reads as seed %d scale %s" % [LevelSwitch.source_seed("seed:42"),
			LevelSwitch.source_robot_scale("seed:42")]
	if LevelSwitch.seed_source(42) != "seed:42" or LevelSwitch.seed_source(42, 1.0) != "seed:42":
		return "an unscaled seed is written %s" % LevelSwitch.seed_source(42, 1.0)
	var picked: String = LevelSwitch.requested_source(PackedStringArray(["--seed=42"]), "", "")
	if picked != "seed:42" or LevelSwitch.source_robot_scale(picked) != 1.0:
		return "--seed=42 flies %s" % picked
	return ""


func test_a_scaled_source_round_trips() -> String:
	var source: String = LevelSwitch.seed_source(42, DEEP_SCALE)
	if source != "seed:42:robots=1.3":
		return "scaled source is %s" % source
	if LevelSwitch.source_seed(source) != 42 or LevelSwitch.source_robot_scale(source) != DEEP_SCALE:
		return "%s reads as seed %d scale %s" % [source, LevelSwitch.source_seed(source),
			LevelSwitch.source_robot_scale(source)]
	if LevelStart.shown_level(source) != PackedStringArray(["42", ""]):
		return "the status panel names %s as %s" % [source, LevelStart.shown_level(source)]
	return ""


func test_a_bad_scale_is_not_flown() -> String:
	for source: String in ["seed:42:robots=", "seed:42:robots=0", "seed:42:robots=-1.3", "seed:42:robots=x"]:
		if LevelSwitch.source_robot_scale(source) > 0.0:
			return "%s reads as scale %s" % [source, LevelSwitch.source_robot_scale(source)]
		if LevelSwitch.load_level(source) != null:
			return "%s built a level" % source
	if LevelSwitch.source_seed("seed:x:robots=1.3") != -1:
		return "a source without a seed read as one"
	return ""


func test_the_first_level_is_unscaled() -> String:
	var run: RunWiring = _wiring()
	if run.level_robot_scale() != 1.0:
		return "level 1 scale %s" % run.level_robot_scale()
	if run.level_source() != LevelSwitch.SEED_PREFIX + str(run.state.current_level_seed()):
		return "level 1 flies %s" % run.level_source()
	return ""


func test_the_deep_shaft_builds_the_scaled_level() -> String:
	var run: RunWiring = _through("deep")
	if run == null:
		return "the run did not take the deep shaft"
	var level_seed: int = run.state.current_level_seed()
	if run.level_robot_scale() != DEEP_SCALE:
		return "after deep the scale is %s" % run.level_robot_scale()
	if run.level_source() != LevelSwitch.seed_source(level_seed, DEEP_SCALE):
		return "after deep the run flies %s" % run.level_source()
	var flown: LevelDef = LevelSwitch.load_level(run.level_source())
	var expected: LevelDef = SeedLevel.load_level(level_seed, LevelSwitch.DEFAULTS_FILE, "", {}, DEEP_SCALE)
	var plain: LevelDef = SeedLevel.load_level(level_seed)
	if flown == null or expected == null or plain == null:
		return "seed %d: a level was rejected" % level_seed
	if _robots(flown) != _robots(expected):
		return "seed %d: the flown level's robots differ from SeedLevel at %s" % [level_seed, DEEP_SCALE]
	if flown.robots.spawns.size() < plain.robots.spawns.size():
		return "seed %d: %d robots scaled, %d unscaled" % [level_seed, flown.robots.spawns.size(),
			plain.robots.spawns.size()]
	return ""


func test_the_steady_shaft_builds_the_unscaled_level() -> String:
	var run: RunWiring = _through("steady")
	if run == null:
		return "the run did not take the steady shaft"
	var level_seed: int = run.state.current_level_seed()
	if run.level_source() != LevelSwitch.SEED_PREFIX + str(level_seed):
		return "after steady the run flies %s" % run.level_source()
	var flown: LevelDef = LevelSwitch.load_level(run.level_source())
	var plain: LevelDef = SeedLevel.load_level(level_seed)
	if flown == null or plain == null or _robots(flown) != _robots(plain):
		return "seed %d: the steady level is not the unscaled one" % level_seed
	return ""


func test_the_scaled_level_gets_the_run_rules() -> String:
	var run: RunWiring = _through("deep")
	if run == null:
		return "the run did not take the deep shaft"
	var start: LevelStart = LevelStart.new()
	start.run = run
	if start.run_rules(run.level_source()) == null:
		return "the scaled run level %s got no run rules" % run.level_source()
	if start.run_rules(LevelSwitch.SEED_PREFIX + str(run.state.current_level_seed())) != null:
		return "the same seed unscaled counted as the run's level"
	return ""
