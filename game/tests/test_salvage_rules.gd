extends RefCounted

## The salvage data file and its replay line (#600, SLV-1, ARC-4, ARC-2).

const SHIPPED: String = "res://data/salvage.json"
const SHIP_FILE: String = "res://data/ships/default_ship.json"


func _text(values: Dictionary) -> String:
	return JSON.stringify(values)


func _valid() -> Dictionary:
	return {"pickup_reach": 2.0, "pull_reach": 6.0, "pull_speed": 5.0, "swap_drop_distance": 3.0}


func test_shipped_file_parses_and_reaches_at_least_three_metres() -> String:
	var rules: SalvageRules = SalvageRules.parse_json(FileAccess.get_file_as_string(SHIPPED))
	if rules.error != "":
		return rules.error
	var ship: ShipTuning = ShipTuning.parse_json(FileAccess.get_file_as_string(SHIP_FILE))
	var pickup: float = ship.radius + rules.pickup_reach
	if pickup < 3.0:
		return "the shipped ship takes a part within %.2f m, the issue asks for at least 3 m" % pickup
	if not rules.pulls():
		return "the shipped rules pull nothing"
	if rules.swap_drop_distance <= pickup:
		return "a swapped weapon lands %.1f m behind, inside the %.1f m pickup radius" % [
			rules.swap_drop_distance, pickup]
	return ""


func test_defaults_are_the_rules_before_the_file() -> String:
	var rules: SalvageRules = SalvageRules.new()
	if rules.pickup_reach != 1.5 or rules.pulls() or rules.swap_drop_distance != 0.0:
		return "defaults %s" % rules.to_json()
	return ""


func test_bad_files_are_rejected_naming_the_key() -> String:
	var cases: Dictionary = {
		"[]": "top level must be a JSON object",
		"{": "invalid JSON",
	}
	var missing: Dictionary = _valid()
	missing.erase("pull_speed")
	cases[_text(missing)] = "missing key \"pull_speed\""
	var unknown: Dictionary = _valid()
	unknown["pickup_radius"] = 3.0
	cases[_text(unknown)] = "unknown key \"pickup_radius\""
	var boolean: Dictionary = _valid()
	boolean["pull_speed"] = true
	cases[_text(boolean)] = "key \"pull_speed\" must be a number"
	var short_pull: Dictionary = _valid()
	short_pull["pull_reach"] = 1.0
	cases[_text(short_pull)] = "key \"pull_reach\" is 1"
	var far: Dictionary = _valid()
	far["swap_drop_distance"] = 50.0
	cases[_text(far)] = "key \"swap_drop_distance\" is 50"
	var failures: PackedStringArray = PackedStringArray()
	for text: String in cases:
		var rules: SalvageRules = SalvageRules.parse_json(text)
		if not rules.error.begins_with(cases[text]):
			failures.append("%s: got '%s'" % [text, rules.error])
		elif rules.values_hash() != SalvageRules.new().values_hash():
			failures.append("%s: rejected rules kept parsed values" % text)
	return "\n".join(failures)


func test_sim_takes_rules_only_before_the_first_tick() -> String:
	var sim: Sim = Sim.new(0, 1)
	var rules: SalvageRules = SalvageRules.parse_json(_text(_valid()))
	if sim.set_salvage_rules(SalvageRules.parse_json("[]")) == "":
		return "rejected rules were accepted"
	if sim.set_salvage_rules(rules) != "" or sim.salvage_rules != rules:
		return "valid rules were refused"
	var inputs: Array[ShipInput] = [ShipInput.new()]
	sim.step(inputs)
	if sim.set_salvage_rules(SalvageRules.new()) == "" or sim.salvage_rules != rules:
		return "the rules changed after the first tick"
	return ""


func test_replay_round_trips_the_salvage_line() -> String:
	var replay: Replay = Replay.new(3, 1)
	replay.salvage_rules = SalvageRules.parse_json(_text({"pickup_reach": 2.123456789,
		"pull_reach": 7.0, "pull_speed": 4.5, "swap_drop_distance": 3.25}))
	replay.add_tick([ShipInput.new()] as Array[ShipInput])
	var text: String = replay.to_text()
	if not text.contains("\nsalvage {"):
		return "no salvage line in:\n%s" % text
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return loaded.error
	if loaded.salvage_rules == null \
			or loaded.salvage_rules.values_hash() != replay.salvage_rules.values_hash():
		return "the rules read back differ"
	if loaded.to_text() != text:
		return "round trip changed the text"
	if loaded.run().salvage_rules.values_hash() != replay.salvage_rules.values_hash():
		return "running the replay did not apply its rules"
	return ""


func test_salvage_line_is_refused_before_version_16_and_twice() -> String:
	var line: String = "salvage " + SalvageRules.new().to_json() + "\n"
	var old: Replay = Replay.from_text("meltdown-replay 15\nseed 1\nships 1\n" + line + "inputs\n")
	if old.error != "line 4: a salvage line needs format version 16 or later":
		return "version 15: '%s'" % old.error
	var twice: Replay = Replay.from_text("meltdown-replay 16\nseed 1\nships 1\n" + line + line
		+ "inputs\n")
	if twice.error != "line 5: 'salvage' appears twice":
		return "twice: '%s'" % twice.error
	var bad: Replay = Replay.from_text("meltdown-replay 16\nseed 1\nships 1\nsalvage {}\ninputs\n")
	if not bad.error.begins_with("line 4: salvage: missing key"):
		return "bad: '%s'" % bad.error
	return ""


## A replay without a salvage line flies the defaults, as every replay
## recorded before #600 did.
func test_replay_without_the_line_flies_the_defaults() -> String:
	var replay: Replay = Replay.from_text("meltdown-replay 15\nseed 1\nships 1\ninputs\n")
	if replay.error != "" or replay.salvage_rules != null:
		return "read as '%s' with rules %s" % [replay.error, replay.salvage_rules]
	if replay.run().salvage_rules.values_hash() != SalvageRules.new().values_hash():
		return "the run did not keep the default rules"
	return ""


func test_level_sessions_load_the_shipped_rules() -> String:
	var level: LevelDef = LevelSwitch.load_level(LevelSwitch.path_for("g2"))
	var session: LocalSession = LocalSession.for_level(level)
	var shipped: SalvageRules = SpawnLoader.load_salvage_rules()
	if session.sim.salvage_rules.values_hash() != shipped.values_hash():
		return "the level session flies other rules"
	if session.replay.salvage_rules == null:
		return "the level session's replay records no rules"
	if SpawnLoader.load_salvage_rules("res://data/no_such_file.json") != null:
		return "a missing file gave rules"
	return ""
