extends RefCounted

## A level's trapped miners (#938, SLV-3, GEN-3): `LevelDef` reads an optional
## `miners` list of positions and writes it back the same way, a level without
## the key has none, a miner outside the level is rejected, and the validator's
## `miners_reachable` check fails a miner the start cannot reach.

const BOXES: Array = [
	{"min": [-6, -4, -40], "max": [6, 4, 6]},
	{"min": [-6, -4, -80], "max": [6, 4, -38]},
]


func _text(miners: Variant, boxes: Array = BOXES) -> String:
	var data: Dictionary = {"boxes": boxes,
			"start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []}
	if miners != null:
		data["miners"] = miners
	return JSON.stringify(data)


func test_level_without_the_key_has_no_miners() -> String:
	var level: LevelDef = LevelDef.parse_json(_text(null))
	if level.error != "":
		return level.error
	if not level.miners.is_empty():
		return "%d miners without the key" % level.miners.size()
	return ""


func test_miners_are_read_in_millimetres_and_written_back() -> String:
	var level: LevelDef = LevelDef.parse_json(_text([[1.5, -2, -30], [0, 0.25, -60.001]]))
	if level.error != "":
		return level.error
	var expected: Array[Vector3i] = [Vector3i(1500, -2000, -30000), Vector3i(0, 250, -60001)]
	if level.miners != expected:
		return "read %s" % [level.miners]
	var written: Array = level.miners_json()
	var again: LevelDef = LevelDef.parse_json(_text(written))
	if again.error != "" or again.miners != expected:
		return "written %s read back as %s (%s)" % [written, again.miners, again.error]
	return ""


func test_bad_miners_are_rejected_naming_the_miner() -> String:
	var cases: Array = [
		["not a list", "miners"],
		[[[1, 2]], "miner 1"],
		[[[0, 0, -10], ["a", 0, 0]], "miner 2"],
		[[[0, 0, -10], [50, 0, 0]], "miner 2"],
	]
	for case: Array in cases:
		var level: LevelDef = LevelDef.parse_json(_text(case[0]))
		if level.error == "":
			return "%s accepted" % JSON.stringify(case[0])
		if not level.error.contains(case[1]):
			return "error \"%s\" does not name %s" % [level.error, case[1]]
	return ""


func test_miners_reachable_fails_a_miner_the_start_cannot_reach() -> String:
	var validator: LevelValidator = LevelValidator.new()
	var reached: LevelDef = LevelDef.parse_json(_text([[0, 0, -60]]))
	if reached.error != "":
		return reached.error
	for failure: String in validator.validate(reached, 1.0, false):
		if failure.begins_with(MinerChecks.CHECK):
			return "a reachable miner failed: %s" % failure
	# Built by hand: `parse_json` rejects a box not joined to box 0.
	var cut_off: LevelDef = LevelDef.parse_json(_text([]))
	var boxes: Array[BoxBounds] = cut_off.union.boxes.duplicate()
	boxes.append(BoxBounds.new(Vector3(100, -4, -10), Vector3(112, 4, 10)))
	cut_off.union = BoxUnion.new(boxes)
	cut_off.miners = [Vector3i(106000, 0, 0), Vector3i(0, 0, -500000)]
	var found: Array[String] = []
	for failure: String in validator.validate(cut_off, 1.0, false):
		if failure.begins_with(MinerChecks.CHECK):
			found.append(failure)
	if found.size() != 2 or not found[0].contains("miner 0 is in box 2") \
			or not found[1].contains("miner 1") or not found[1].contains("not inside any box"):
		return "expected the cut-off and the outside miner, got %s" % [found]
	if not LevelValidator.CHECKS.has(MinerChecks.CHECK):
		return "CHECKS does not list %s" % MinerChecks.CHECK
	return ""
