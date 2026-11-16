extends RefCounted

## The simulation's part catalogue and its replay lines (#267, SLV-1, CMB-1,
## ARC-2, ARC-4): set before tick 0, part of the hash only while non-empty,
## and recorded so a replay sets the same catalogue.

const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const TICKS: int = 90
const HEADER: String = "meltdown-replay 10\nseed 1\nships 1\n"


func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


func _catalogue() -> Dictionary[String, WeaponDef]:
	var odd: WeaponDef = _cannon()
	odd.damage = 3.123456789012  # Not round: lost precision would show.
	return {"pulse_cannon": _cannon(), "odd_cannon": odd}


func _input(tick: int) -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, -400), Vector3i(0, 100 if tick < 30 else 0, 0))


## Flies `TICKS` ticks with `parts` set and records them; returns [sim, replay].
func _record(parts: Dictionary[String, WeaponDef]) -> Array:
	var sim: Sim = Sim.new(5, 1)
	var problem: String = sim.set_parts(parts)
	if problem != "":
		return [null, problem]
	var replay: Replay = Replay.new(5, 1)
	replay.parts = parts
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = [_input(tick)]
		sim.step(inputs)
		replay.add_tick(inputs)
	return [sim, replay]


func test_a_catalogue_set_and_replayed_gives_the_live_hash() -> String:
	var recorded: Array = _record(_catalogue())
	if recorded[0] == null:
		return "set_parts refused: %s" % recorded[1]
	var live: Sim = recorded[0]
	var text: String = (recorded[1] as Replay).to_text()
	if text.count("\npart ") != 2:
		return "expected two part lines in:\n%s" % text
	if text.find("\npart odd_cannon ") > text.find("\npart pulse_cannon "):
		return "part lines are not sorted by id"
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return reread.error
	if reread.parts["odd_cannon"].damage != 3.123456789012:
		return "the part read back as %s damage" % reread.parts["odd_cannon"].damage
	var replayed: Sim = reread.run()
	if replayed == null:
		return reread.run_error
	if replayed.state_hash() != live.state_hash():
		return "the replay ends on %d, the live run on %d" % [replayed.state_hash(), live.state_hash()]
	if replayed.part_ids() != ["odd_cannon", "pulse_cannon"]:
		return "the replayed catalogue holds %s" % str(replayed.part_ids())
	# The catalogue must be in the hash, values included, or the test proves nothing.
	reread.parts["odd_cannon"].damage = 3.0
	if reread.run().state_hash() == live.state_hash():
		return "changing a part's damage does not change the hash"
	reread.parts = {}
	if reread.run().state_hash() == live.state_hash():
		return "dropping the catalogue does not change the hash"
	return ""


func test_an_empty_catalogue_hashes_as_before() -> String:
	var plain: Sim = Sim.new(5, 1)
	var empty: Sim = Sim.new(5, 1)
	if empty.set_parts({}) != "":
		return "an empty catalogue was refused"
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = [_input(tick)]
		plain.step(inputs)
		empty.step(inputs)
	if empty.state_hash() != plain.state_hash():
		return "an empty catalogue changed the hash"
	var recorded: Array = _record({})
	if (recorded[1] as Replay).to_text().contains("\npart "):
		return "an empty catalogue wrote a part line"
	if (recorded[0] as Sim).state_hash() != plain.state_hash():
		return "a recorded run with no parts ends on another hash"
	return ""


func test_older_pinned_replays_still_match_their_hash() -> String:
	var failures: PackedStringArray = PackedStringArray()
	for path: String in ["res://tests/replays/basic_flight.replay",
			"res://tests/replays/wall_hit.replay"]:
		var replay: Replay = Replay.load_file(path)
		if replay.error != "":
			failures.append("%s: %s" % [path, replay.error])
			continue
		var sim: Sim = replay.run()
		if sim == null or sim.state_hash() != replay.expected_hash:
			failures.append("%s no longer ends on its pinned hash" % path)
	return "\n".join(failures)


func test_the_catalogue_is_set_only_before_the_first_tick() -> String:
	var sim: Sim = Sim.new(1, 1)
	var inputs: Array[ShipInput] = [ShipInput.new()]
	sim.step(inputs)
	if sim.set_parts(_catalogue()) == "":
		return "set_parts was accepted after the first tick"
	if not sim.part_ids().is_empty():
		return "a refused catalogue was kept"
	return ""


func test_the_catalogue_cannot_be_changed_through_the_given_dictionary() -> String:
	var sim: Sim = Sim.new(1, 1)
	var parts: Dictionary[String, WeaponDef] = _catalogue()
	sim.set_parts(parts)
	parts.erase("pulse_cannon")
	parts["extra"] = _cannon()
	if sim.part_ids() != ["odd_cannon", "pulse_cannon"]:
		return "the catalogue followed the caller's dictionary: %s" % str(sim.part_ids())
	if sim.part("odd_cannon") == null or sim.part("missing") != null:
		return "part() does not look up by id"
	return ""


func test_set_parts_refuses_bad_entries_and_keeps_nothing() -> String:
	var failed: WeaponDef = WeaponDef.parse_json("{}")
	var cases: Array = [
		[{"Bad Id": _cannon()}, "Bad Id"],
		[{"": _cannon()}, "part id"],
		[{"cannon": "not a weapon"}, "cannon"],
		[{"cannon": failed}, "cannon"],
		[{7: _cannon()}, "7"],
	]
	var failures: PackedStringArray = PackedStringArray()
	for entry: Array in cases:
		var sim: Sim = Sim.new(1, 1)
		var problem: String = sim.set_parts(entry[0])
		if problem == "" or not problem.contains(entry[1]):
			failures.append("%s: got '%s'" % [str(entry[0]), problem])
		elif not sim.part_ids().is_empty():
			failures.append("%s: kept a part" % str(entry[0]))
	return "\n".join(failures)


func test_duplicate_or_malformed_part_lines_name_the_line() -> String:
	var cannon: String = JSON.stringify(ReplayLines.weapon_data(_cannon()), "", false, true)
	var cases: Dictionary = {
		HEADER + "part a %s\npart a %s\ninputs\n" % [cannon, cannon]:
			"line 5: 'part a' appears twice",
		HEADER + "part a\ninputs\n": "line 4: part needs an id and the part's data",
		HEADER + "part A! %s\ninputs\n" % cannon: "line 4: \"part id\" is \"A!\"",
		HEADER + "part a {\"damage\":1}\ninputs\n": "line 4: part a: missing key",
		HEADER + "part a {\ninputs\n": "line 4: part a: invalid JSON",
		"meltdown-replay 9\nseed 1\nships 1\npart a %s\ninputs\n" % cannon:
			"line 4: a part line needs format version 10 or later",
	}
	var failures: PackedStringArray = PackedStringArray()
	for text: String in cases:
		var replay: Replay = Replay.from_text(text)
		if not replay.error.begins_with(cases[text]):
			failures.append("%s: got '%s'" % [text.c_escape(), replay.error])
	return "\n".join(failures)
