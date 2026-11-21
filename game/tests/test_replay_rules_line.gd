extends RefCounted

## The replay's run-level rule lines (#1028, version 18): a replay with
## component drops and miner rescue writes both lines and reads them back, a
## replay without them is written as version 17, and a bad line is refused
## with the problem named.

const HEADER: String = "meltdown-replay 18\nseed 3\nships 1\n"


func _rules_replay() -> Replay:
	var replay: Replay = Replay.new(3, 1)
	replay.component_rules = ComponentPickup.parse_json("{\"pickup_reach\": 1.25}")
	replay.rescue_rules = MinerRescue.parse_json("{\"rescue_reach\": 3.5, \"hold_seconds\": 0.75}")
	replay.miners = [Vector3i(1000, -2000, 30500), Vector3i(-7, 0, 9)]
	return replay


func test_the_lines_round_trip() -> String:
	var text: String = _rules_replay().to_text()
	if not text.begins_with("meltdown-replay 18\n"):
		return "written as %s" % text.get_slice("\n", 0)
	var read: Replay = Replay.from_text(text)
	if read.error != "":
		return read.error
	if read.component_rules.pickup_reach != 1.25 or read.rescue_rules.rescue_reach != 3.5 \
			or read.rescue_rules.hold_seconds != 0.75 or read.miners != _rules_replay().miners:
		return "read back %s" % text
	if read.to_text() != text:
		return "text changed in the round trip"
	var sim: Sim = read.run()
	if sim.component_rules == null or sim.rescue == null or sim.rescue.trapped != read.miners:
		return "the run did not install the rules"
	return ""


func test_a_replay_without_them_is_written_as_17() -> String:
	var replay: Replay = Replay.new(3, 1)
	if ReplayRulesLine.format_version(replay) != 17 or not replay.to_text().begins_with("meltdown-replay 17\n"):
		return "written as %s" % replay.to_text().get_slice("\n", 0)
	replay.rescue_rules = _rules_replay().rescue_rules
	return "" if ReplayRulesLine.format_version(replay) == 18 else "rescue alone stays 17"


func test_robot_lines_carry_drop_tables_only_with_components() -> String:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string("res://data/robots/drone.json"))
	var spawn: RobotSpawn = RobotSpawn.new(def, Vector3i(0, 0, -5000), Vector3i(0, 0, 1000))
	if def.components.is_empty():
		return "the drone has no drop table to test with"
	if ReplayLines.robot_text(spawn).contains("\"components\""):
		return "a robot line without drops carries the table"
	var replay: Replay = _rules_replay()
	replay.robots = [spawn]
	var read: Replay = Replay.from_text(replay.to_text())
	if read.error != "" or read.robots[0].def.values_hash(true) != def.values_hash(true):
		return "the drop table did not read back: %s" % read.error
	return ""


func test_bad_lines_are_refused() -> String:
	var cases: Dictionary[String, String] = {
		"meltdown-replay 17\nseed 3\nships 1\ncomponents {\"pickup_reach\": 2.5}\ninputs\n":
			"a components line needs format version 18",
		HEADER + "components {\"pickup_reach\": 2.5}\ncomponents {\"pickup_reach\": 2.5}\ninputs\n":
			"'components' appears twice",
		HEADER + "components {\"reach\": 2.5}\ninputs\n": "components: unknown key \"reach\"",
		HEADER + "rescue {\"rescue_reach\": 4, \"hold_seconds\": 2}\ninputs\n": "rescue: missing key \"miners\"",
		HEADER + "rescue {\"rescue_reach\": 4, \"hold_seconds\": 2, \"miners\": [[1, 2]]}\ninputs\n":
			"rescue: key \"miners\" must be a list",
		HEADER + "rescue {\"rescue_reach\": 4, \"hold_seconds\": 2, \"miners\": [[1, 2, 3.5]]}\ninputs\n":
			"rescue: key \"miners\" must be a list",
		HEADER + "rescue {\"rescue_reach\": 0, \"hold_seconds\": 2, \"miners\": []}\ninputs\n":
			"rescue: key \"rescue_reach\" is 0",
		HEADER + "rescue [1]\ninputs\n": "rescue: must be one JSON object",
	}
	for text: String in cases:
		var read: Replay = Replay.from_text(text)
		if not read.error.contains(cases[text]):
			return "%s gave '%s'" % [text.c_escape(), read.error]
	return ""
