extends RefCounted

## The seed sweep flies generated levels with their meltdown debris (#440,
## RUN-4, GEN-3): levels get `debris.json`'s entries, every entry runs through
## `DebrisRouteGuard` in fall order, and a level whose debris closes the last
## route from the reactor to the start fails under `debris_route`. The summary
## line gains the debris counts without renaming anything the nightly job reads.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 1000
const SHIP_RADIUS: float = 1.0
## Generated levels on which `debris_route` is compared with the flown meltdown.
const COMPARED_SEEDS: int = 200
## Two rooms joined by a 6 m tunnel: the start in the first, the reactor in the
## second, and one 4 m entry in the opening between the first room and the
## tunnel (routes only close at openings), falling a second into the meltdown.
## Let fall, it closes the only way out.
const BLOCKED_LEVEL: String = """{
	"boxes": [
		{"min": [-10.0, -10.0, -40.0], "max": [10.0, 10.0, 10.0]},
		{"min": [-3.0, -3.0, -70.0], "max": [3.0, 3.0, -30.0]},
		{"min": [-10.0, -10.0, -120.0], "max": [10.0, 10.0, -60.0]}
	],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [0, 0, -100], "radius": 2, "hull": 40, "meltdown_seconds": 60},
	"debris": [
		{"position": [0.0, 0.0, -35.0], "radius": 4.0, "after_seconds": 1.0}
	]
}"""


func _blocked_level() -> LevelDef:
	return LevelDef.parse_json(BLOCKED_LEVEL)


func test_the_debris_file_reads() -> String:
	var plan: DebrisPlan = SeedSweep.load_debris_plan()
	return "" if plan.error == "" else "debris.json: %s" % plan.error


func test_a_seed_with_debris_is_found_in_0_to_999_and_passes() -> String:
	for level_seed: int in SEEDS:
		var result: Dictionary = SeedSweep.run(level_seed, 1)
		if result["debris"] == 0:
			continue
		if result["failed"] != 0:
			return "seed %d: %s; %s" % [level_seed, SeedSweep.summary(result), result["failures"]]
		if not SeedSweep.summary(result).contains("debris %d," % result["debris"]):
			return "seed %d: the summary does not name its debris: %s" % [level_seed,
					SeedSweep.summary(result)]
		return ""
	return "no seed in 0..%d got debris" % (SEEDS - 1)


func test_the_sweep_counts_debris_route_failures() -> String:
	var result: Dictionary = SeedSweep.run(0, 5)
	if not result["by_check"].has(SeedSweep.DEBRIS_ROUTE):
		return "by_check has no %s: %s" % [SeedSweep.DEBRIS_ROUTE, result["by_check"]]
	if not result.has("debris") or not result.has("debris_held"):
		return "the result has no debris counts: %s" % SeedSweep.summary(result)
	if result["debris_held"] > result["debris"]:
		return "%d held of %d placed" % [result["debris_held"], result["debris"]]
	return "" if SeedSweep.summary(result).contains("%s 0" % SeedSweep.DEBRIS_ROUTE) \
			else "the summary does not list %s: %s" % [SeedSweep.DEBRIS_ROUTE, SeedSweep.summary(result)]


## The nightly job greps for the line's prefix; the old fields stay as they were
## and the new ones read back as whole numbers.
func test_the_summary_keys_parse() -> String:
	var result: Dictionary = {"seeds": 3, "passed": 2, "failed": 1, "short": 0, "ms": 12,
			"debris": 7, "debris_held": 2, "by_check": {"reactor": 0, "debris_route": 1}}
	var line: String = SeedSweep.summary(result)
	var prefix: String = "level validator: 3 seeds, 2 passed, 1 failed, 0 stopped short, 12 ms"
	if not line.begins_with(prefix):
		return "the old fields changed: \"%s\"" % line
	var counts: Dictionary[String, int] = {}
	for part: String in line.get_slice(";", 0).split(", "):
		var words: PackedStringArray = part.split(" ")
		if words.size() == 2 and words[1].is_valid_int():
			counts[words[0]] = words[1].to_int()
	if counts.get("debris", -1) != 7 or counts.get("debris_held", -1) != 2:
		return "debris counts read as %s from \"%s\"" % [counts, line]
	return "" if line.ends_with("; failing seeds by check: reactor 0, debris_route 1") \
			else "by-check part: \"%s\"" % line


func test_the_guard_keeps_the_hand_made_level_open() -> String:
	var level: LevelDef = _blocked_level()
	if level.error != "" or level.debris == null:
		return "the hand-made level did not parse: '%s'" % level.error
	var held: Array[int] = []
	var closed: String = SeedSweep.debris_route(level, SHIP_RADIUS, held)
	if closed != "":
		return "with the guard: %s" % closed
	return "" if held == [1] else "the guard held %s entries, expected 1" % [held]


func test_bypassing_the_guard_fails_the_level_under_debris_route() -> String:
	var held: Array[int] = []
	var closed: String = SeedSweep.debris_route(_blocked_level(), SHIP_RADIUS, held, false)
	if not closed.begins_with(SeedSweep.DEBRIS_ROUTE + ":"):
		return "without the guard the check gave \"%s\"" % closed
	if not closed.contains("60 ticks"):
		return "the message does not name the tick: %s" % closed
	return "" if held == [0] else "%s entries held without the guard" % [held]


## `debris_route` gives what flying the meltdown through the guard gives (#513):
## the same message and the same number held, on the hand-made level, on it
## with the tunnel gone (no route before anything falls), and over seeds
## 0..`COMPARED_SEEDS - 1`.
func test_debris_route_matches_the_flown_meltdown() -> String:
	var levels: Array[LevelDef] = [_blocked_level(), _blocked_level()]
	var boxes: Array[BoxBounds] = levels[1].union.boxes.duplicate()
	boxes.remove_at(1)
	levels[1].union = BoxUnion.new(boxes)
	var inputs: SeedLevel = SeedLevel.load_inputs()
	for level_seed: int in COMPARED_SEEDS:
		levels.append(inputs.level_of(inputs.generate(level_seed)))
	var radius: float = SeedSweep.ship_radius()
	var compared: int = 0
	var held_total: int = 0
	for index: int in levels.size():
		var level: LevelDef = levels[index]
		if level.reactor == null or level.debris == null:
			continue
		var each: float = SHIP_RADIUS if index < 2 else radius
		var fast: Array[int] = []
		var flown: Array[int] = []
		var message: String = SeedSweep.debris_route(level, each, fast)
		var expected: String = SeedSweep.debris_route_flown(level, each, flown)
		if message != expected or fast != flown:
			return "level %d: \"%s\" holding %s, flown \"%s\" holding %s" \
					% [index - 2, message, fast, expected, flown]
		if index == 1 and not message.contains("60 ticks"):
			return "no route from the start: \"%s\"" % message
		compared += 1
		held_total += flown[0]
	if compared <= COMPARED_SEEDS / 2:
		return "only %d levels compared" % compared
	return "" if held_total > 0 else "no entry held in any level: the comparison proves little"


func test_the_sweep_times_every_stage() -> String:
	var result: Dictionary = SeedSweep.run(0, 2)
	var stage_ms: Dictionary = result.get("stage_ms", {})
	var line: String = SeedSweep.timing(result)
	for stage: String in SeedSweep.STAGES:
		if not stage_ms.has(stage) or stage_ms[stage] < 0:
			return "no time for %s: %s" % [stage, stage_ms]
		if not line.contains("%s %d ms" % [stage, stage_ms[stage]]):
			return "%s missing from \"%s\"" % [stage, line]
	return "" if line.begins_with("sweep time: generate ") else line
