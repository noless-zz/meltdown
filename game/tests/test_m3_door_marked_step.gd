extends RefCounted

## The m3 suite's door-marked step (#899, MAP-2, RUN-4, DEV-6, decision record
## 0005). `bot_generated_door_escape`'s door falls in boxes the bot never
## explores, so the map rightly draws no cross there and `map_route`'s door rule
## was only shown on a hand-built G2 state. This step flies the lowest seed in
## 1..300 where the bot escapes and, before a door falls, has explored the boxes
## on both sides of an opening it closes, so the running game must draw the
## cross. Like the other generated steps the replay holds only inputs and the
## seed and hashes live only in `m3.json`.
##
## Re-recording this step only, from the repository root (`1` records every
## m3 step):
##
##     MELTDOWN_RECORD_M3=bot_generated_door_marked godot --headless --path game -s res://tests/run_tests.gd

const STEP_ID: String = "bot_generated_door_marked"
const REPLAY_PATH: String = "res://acceptance/replays/bot_generated_door_marked.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M3"
const RecordSwitch := preload("res://tests/record_switch.gd")
const SeedPick := preload("res://tests/m3_seed_pick.gd")
const M3Run := preload("res://tests/m3_suite_run.gd")
## What `map_route` must say of a door whose cross it saw drawn, and must not.
const MARKED: String = "of its marks drawn"
const UNMARKED: String = "outside the explored boxes"
const REPLAY_HEADER: String = """# The bot pilot's escape from the m3 suite's door-marked seed (#899): a door
# falls across an opening between boxes the bot has already explored, so the
# held map must draw its cross. Inputs only: the m3 suite builds the level from
# the seed in m3.json and the shipped data files. Re-record from the repository
# root; the recorder picks the seed and writes the seed and hashes into m3.json
# itself. Records this step only:
#     MELTDOWN_RECORD_M3=bot_generated_door_marked godot --headless --path game -s res://tests/run_tests.gd
"""


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	return SeedPick.record(STEP_ID, REPLAY_PATH, REPLAY_HEADER, SeedPick.NEED_DOOR_MARKED)


func test_the_step_names_its_seed_and_checks() -> String:
	var found: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if found == null:
		return "m3 has no step %s" % STEP_ID
	if found.level_seed == AcceptanceStep.NO_SEED or found.level != "" or found.replay_path != REPLAY_PATH:
		return "the step flies %s on seed %d, level '%s'" % [found.replay_path, found.level_seed, found.level]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_LEVEL_HASH,
			AcceptanceStep.CHECK_OUTCOME, AcceptanceStep.CHECK_MAP_ROUTE]:
		if not found.has_check(check):
			return "%s does not check %s: %s" % [STEP_ID, check, found.checks]
	if found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "%s expects outcome %d" % [STEP_ID, found.expected_outcome]
	if found.level_seed < SeedPick.SEARCH_FIRST or found.level_seed > SeedPick.SEARCH_LAST:
		return "%s flies seed %d, outside %d..%d" % [STEP_ID, found.level_seed, SeedPick.SEARCH_FIRST,
			SeedPick.SEARCH_LAST]
	# A separate step, so the door step keeps its own seed and hashes.
	var door: AcceptanceStep = SeedPick.find_step("bot_generated_door_escape")
	if door == null or door.level_seed != 26:
		return "bot_generated_door_escape no longer flies seed 26"
	return ""


## The level must come from the seed, as for the other generated steps.
func test_the_replay_holds_only_inputs() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if replay.box_mins_mm.size() > 0 or replay.reactor != null or not replay.robots.is_empty() \
			or replay.debris != null or replay.tuning != null or replay.loadout != null \
			or not replay.parts.is_empty() or not replay.start_positions_mm.is_empty():
		return "%s carries more than its inputs" % REPLAY_PATH
	var found: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if replay.ship_count != 1 or replay.frames.is_empty() or replay.expected_hash != found.expected_hash:
		return "%s: %d ships, %d ticks, hash %d" % [REPLAY_PATH, replay.ship_count,
			replay.frames.size(), replay.expected_hash]
	return ""


## The door-marked need counts only an escape with a marked door down.
func test_only_an_escape_with_a_marked_door_qualifies() -> String:
	var need: String = SeedPick.NEED_DOOR_MARKED
	var cases: Array = [
		[SeedPick.Flown.of(1, true, 2, 1, 0, 1), true],
		[SeedPick.Flown.of(2, true, 2, 1, 0, 0), false],
		[SeedPick.Flown.of(3, false, 2, 1, 0, 1), false],
		[SeedPick.Flown.of(4, true, 0, 0, 0, 0), false],
	]
	for case: Array in cases:
		var flown: SeedPick.Flown = case[0]
		if flown.qualifies(need) != case[1]:
			return "seed %d qualifies %s" % [flown.level_seed, flown.qualifies(need)]
	var results: Array[SeedPick.Flown] = [SeedPick.Flown.of(5, true, 1, 1, 0, 0),
			SeedPick.Flown.of(9, true, 1, 1, 0, 2), SeedPick.Flown.of(7, true, 1, 1, 0, 1)]
	var picked: Dictionary = SeedPick.pick(results, 1, 300, need)
	if picked.get("seed", -1) != 7:
		return "picked %s" % picked
	var none: Dictionary = SeedPick.pick([SeedPick.Flown.of(5, true, 1, 1)] as Array[SeedPick.Flown], 1,
			300, need)
	return "" if str(none.get("error", "")).contains("explored boxes") else "no seed gave %s" % none


## The step in the m3 suite, as the headset flies it (flown once for every
## m3 test, `m3_suite_run.gd`, #1139): every check passes, and
## `map_route` says the fallen door's marks were drawn, at least one of them.
func test_the_runner_passes_the_step_with_the_door_marked() -> String:
	var problem: String = M3Run.step_problem(STEP_ID)
	if problem == "":
		var step: Dictionary = M3Run.step(STEP_ID)
		var measured: Dictionary = step["measurements"]
		var message: String = str(step.get("message", ""))
		if measured.get("outcome") != "ESCAPED" or int(measured.get("map_route_door_marks", 0)) < 1:
			problem = "measured %s" % measured
		elif not message.contains(MARKED) or message.contains(UNMARKED):
			problem = "map_route said: %s" % message
		else:
			var marks: RegExMatch = RegEx.create_from_string("all (\\d+) of its marks drawn").search(message)
			if marks == null or int(marks.get_string(1)) < 1:
				problem = "no mark count in: %s" % message
	return problem
