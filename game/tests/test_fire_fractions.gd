extends RefCounted

## Generated fire lights at a fraction of the level's own meltdown countdown
## (#620, RUN-4, RUN-5, ARC-4): a short and a long hand-built level, whose
## countdowns scale with their escape paths, get their fire at the same stated
## fractions of their own countdowns, so the long level's fire lights later in
## seconds and neither lights after the escape is long over.

## A straight tunnel from the start to a reactor `%s` metres away, with the
## generated levels' countdown scaling (`data/gen/reactor.json`).
const TUNNEL: String = """{
	"boxes": [{"min": [-5.0, -5.0, -%s], "max": [5.0, 5.0, 5.0]}],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [0, 0, -%s], "radius": 2, "hull": 40, "meltdown_seconds": 90,
		"meltdown_base_seconds": 30, "meltdown_seconds_per_metre": 0.2,
		"meltdown_min_seconds": 45, "meltdown_max_seconds": 180}
}"""
const SHORT_M: int = 100
const LONG_M: int = 600


static func _level(metres: int) -> LevelDef:
	return LevelDef.parse_json(TUNNEL % [str(metres + 5), str(metres)])


static func _plan(fraction: Array) -> DebrisPlan:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gen/debris.json"))
	data[DebrisPlan.FIRES_KEY]["after_fraction"] = fraction
	return DebrisPlan.parse_json(JSON.stringify(data))


func test_the_two_levels_have_their_own_countdowns() -> String:
	var short: LevelDef = _level(SHORT_M)
	var long: LevelDef = _level(LONG_M)
	if short.error != "" or long.error != "":
		return "levels: %s %s" % [short.error, long.error]
	# 30 s + 0.2 s/m: 50 s and 150 s, both inside 45..180 s.
	var short_ticks: int = DebrisPlan.countdown_ticks(short)
	var long_ticks: int = DebrisPlan.countdown_ticks(long)
	if short_ticks != 50 * 60 or long_ticks != 150 * 60:
		return "countdowns %d and %d ticks, want 3000 and 9000" % [short_ticks, long_ticks]
	return ""


func test_each_level_gets_fire_at_the_stated_fraction_of_its_countdown() -> String:
	for fraction: float in [0.05, 0.1, 0.25, 0.5]:
		var plan: DebrisPlan = _plan([fraction, fraction])
		if plan.error != "":
			return "after_fraction %s: %s" % [fraction, plan.error]
		var fires: DebrisFires = plan.fires
		if fires.min_after_permille != fires.max_after_permille:
			return "a one-value range read as %d..%d" % [fires.min_after_permille, fires.max_after_permille]
		for metres: int in [SHORT_M, LONG_M]:
			var level: LevelDef = _level(metres)
			var countdown: int = DebrisPlan.countdown_ticks(level)
			var ticks: int = DebrisFires.after_ticks(fires.min_after_permille, countdown,
					plan.fall_limit_ticks(level))
			if ticks != floori(countdown * fraction + 0.0001):
				return "%d m level, fraction %s: fire at tick %d of %d" % [metres, fraction, ticks, countdown]
	# The same fraction is three times as many seconds on the level whose countdown is three times as long.
	var tenth: DebrisPlan = _plan([0.1, 0.1])
	var short_ticks: int = DebrisFires.after_ticks(tenth.fires.min_after_permille,
			DebrisPlan.countdown_ticks(_level(SHORT_M)), tenth.fall_limit_ticks(_level(SHORT_M)))
	var long_ticks: int = DebrisFires.after_ticks(tenth.fires.min_after_permille,
			DebrisPlan.countdown_ticks(_level(LONG_M)), tenth.fall_limit_ticks(_level(LONG_M)))
	return "" if short_ticks == 300 and long_ticks == 900 else "a tenth lit at %d and %d ticks" % [
			short_ticks, long_ticks]


## A fraction past `latest_fall_fraction` still lights by the latest fall tick,
## as every meltdown debris entry does, and a fire never lights before tick 1.
func test_a_late_fraction_is_capped_at_the_fall_limit() -> String:
	var plan: DebrisPlan = _plan([1.0, 1.0])
	var level: LevelDef = _level(SHORT_M)
	var limit: int = plan.fall_limit_ticks(level)
	var ticks: int = DebrisFires.after_ticks(plan.fires.max_after_permille, DebrisPlan.countdown_ticks(level), limit)
	if ticks != limit or limit >= DebrisPlan.countdown_ticks(level):
		return "fraction 1 lit at %d, limit %d" % [ticks, limit]
	if DebrisFires.after_ticks(1, 10, 5) != 1:
		return "a fire lit before tick 1"
	return ""
