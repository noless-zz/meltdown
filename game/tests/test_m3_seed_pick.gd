extends RefCounted

## The m3 seed step's seed choice (#494, DEV-6, GEN-2, RUN-4): a pure function
## over sweep results, checked on hand-made lists, and the suite rewrite that
## stores the choice, checked on hand-made text. Nothing is flown here.

const SeedPick := preload("res://tests/m3_seed_pick.gd")
const SUITE: String = """{
	"name": "m3",
	"steps": [
		{
			"id": "other",
			"seed": 7,
			"replay": "res://a.replay",
			"expected_hash": 11,
			"expected_level_hash": 12
		},
		{
			"id": "bot_generated_escape",
			"seed": 40,
			"replay": "res://b.replay",
			"expected_hash": 1116790880,
			"expected_level_hash": 986809221,
			"expected_outcome": "ESCAPED"
		}
	]
}
"""


func _results(rows: Array) -> Array[SeedPick.Flown]:
	var list: Array[SeedPick.Flown] = []
	for row: Array in rows:
		list.append(SeedPick.Flown.of(row[0], row[1], row[2]))
	return list


func test_the_lowest_qualifying_seed_is_picked() -> String:
	# Out of order on purpose; 3 escapes with nothing down, 5 falls but is lost.
	var results: Array[SeedPick.Flown] = _results([[12, true, 2], [3, true, 0], [9, true, 1],
		[5, false, 3], [30, true, 1]])
	var picked: Dictionary = SeedPick.pick(results)
	if picked.get("seed") != 9:
		return "picked %s, expected seed 9" % picked
	return ""


func test_no_qualifying_seed_is_an_error_naming_the_range() -> String:
	var results: Array[SeedPick.Flown] = _results([[1, true, 0], [2, false, 1], [3, false, 0]])
	var picked: Dictionary = SeedPick.pick(results, 1, 300)
	if picked.has("seed") or not str(picked.get("error", "")).contains("1..300"):
		return "gave %s" % picked
	if not SeedPick.pick(_results([])).has("error"):
		return "an empty sweep picked a seed"
	return ""


func test_the_suite_rewrite_touches_only_the_step() -> String:
	var text: String = SeedPick.rewrite_step(SUITE, "bot_generated_escape", 17, 42, 4242)
	var expected: String = SUITE.replace("\"seed\": 40", "\"seed\": 17") \
		.replace("\"expected_hash\": 1116790880", "\"expected_hash\": 42") \
		.replace("\"expected_level_hash\": 986809221", "\"expected_level_hash\": 4242")
	if text != expected:
		return "rewrote to:\n%s" % text
	return ""


func test_the_suite_rewrite_refuses_a_missing_step_or_field() -> String:
	if SeedPick.rewrite_step(SUITE, "missing", 1, 2, 3) != "":
		return "rewrote a missing step"
	var no_level_hash: String = SUITE.replace("\"expected_level_hash\": 986809221,", "")
	if SeedPick.rewrite_step(no_level_hash, "bot_generated_escape", 1, 2, 3) != "":
		return "rewrote a step without a level hash"
	return ""


## The shipped suite can be rewritten in place, and keeps its hashes when
## written back with them.
func test_the_shipped_suite_round_trips() -> String:
	var step: AcceptanceStep = load("res://tests/test_m3_seed_step.gd").step()
	if step == null:
		return "m3 has no bot_generated_escape step"
	var text: String = SeedLevel.read_text("res://acceptance/suites/m3.json")
	var again: String = SeedPick.rewrite_step(text, step.id, step.level_seed, step.expected_hash,
		step.expected_level_hash)
	if again != text:
		return "rewriting m3.json with its own values changed it"
	return ""


## The door step (#516) also needs a blast door down: seed 9 escapes with a
## rock down but no door, so 30 is picked; without the door rule 9 still is.
func test_the_door_step_needs_a_door_down() -> String:
	var results: Array[SeedPick.Flown] = [SeedPick.Flown.of(9, true, 1, 0),
		SeedPick.Flown.of(30, true, 2, 1), SeedPick.Flown.of(4, false, 2, 1)]
	var picked: Dictionary = SeedPick.pick(results, 1, 300, SeedPick.NEED_DOOR)
	if picked.get("seed") != 30:
		return "picked %s, expected seed 30" % picked
	if SeedPick.pick(results).get("seed") != 9:
		return "without the door rule picked %s" % SeedPick.pick(results)
	var rock_only: Array[SeedPick.Flown] = [SeedPick.Flown.of(9, true, 1, 0)]
	var none: Dictionary = SeedPick.pick(rock_only, 1, 300, SeedPick.NEED_DOOR)
	if not str(none.get("error", "")).contains("blast door"):
		return "no door gave %s" % none
	return ""


## The fire step (#517) needs the bot to escape having been burnt: seed 9
## escapes unburnt, 12 is burnt but lost, so 20 is picked; a burn alone is
## enough, with no meltdown entry counted as fallen.
func test_the_fire_step_needs_a_burn() -> String:
	var results: Array[SeedPick.Flown] = [SeedPick.Flown.of(9, true, 1, 1, 0),
		SeedPick.Flown.of(12, false, 2, 0, 30), SeedPick.Flown.of(20, true, 0, 0, 4)]
	var picked: Dictionary = SeedPick.pick(results, 1, 300, SeedPick.NEED_BURN)
	if picked.get("seed") != 20:
		return "picked %s, expected seed 20" % picked
	var unburnt: Array[SeedPick.Flown] = [SeedPick.Flown.of(9, true, 1, 1, 0)]
	var none: Dictionary = SeedPick.pick(unburnt, 1, 300, SeedPick.NEED_BURN)
	if not str(none.get("error", "")).contains("burnt by fire"):
		return "no burn gave %s" % none
	return ""
