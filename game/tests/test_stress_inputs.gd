extends RefCounted

## `StressInputs` (#1288): a ship's scripted input in the stress scene flies its
## segments in order, loops from `loop_from`, and a bad entry names its field.


static func _parse(text: String) -> StressInputs:
	return StressInputs.parse(JSON.parse_string(text), "inputs[0]")


func test_segments_fly_in_order_then_loop_from_the_named_one() -> String:
	var script: StressInputs = _parse('{"loop_from": 1, "segments": [{"ticks": 2, "thrust": [0, 0, -1], "fire": true}, {"ticks": 3, "turn": [0, 0.5, 0]}, {"ticks": 1}]}')
	if script.error != "":
		return script.error
	var expected: Array[String] = ["a", "a", "b", "b", "b", "c", "b", "b", "b", "c", "b"]
	for tick: int in expected.size():
		var input: ShipInput = script.input_at(tick)
		var got: String = "a" if input.fire_primary and input.thrust_q.z == -1000 \
			else ("b" if input.turn_q.y == 500 and not input.fire_primary else ("c" if input.turn_q == Vector3i.ZERO else "?"))
		if got != expected[tick]:
			return "tick %d flew segment %s, not %s" % [tick, got, expected[tick]]
	return ""


func test_the_same_tick_gives_the_same_input() -> String:
	var script: StressInputs = _parse('{"segments": [{"ticks": 4, "thrust": [0.3333, 0, 0], "fire": true}]}')
	var a: ShipInput = script.input_at(1001)
	var b: ShipInput = script.input_at(1001)
	if a == b:
		return "the script hands out its own input object, which a caller could change"
	if a.thrust_q != b.thrust_q or a.thrust_q.x != 333 or a.fire_primary != b.fire_primary:
		return "inputs differ: %s %s" % [a.thrust_q, b.thrust_q]
	return ""


func test_bad_entries_name_their_field() -> String:
	var cases: Dictionary[String, String] = {
		'[]': "inputs[0]: must be a JSON object",
		'{"segments": []}': "inputs[0].segments: must be a non-empty list",
		'{"segments": [{"ticks": 0}]}': "inputs[0].segments[0]: ticks: must be a whole number from 1 up",
		'{"segments": [{"ticks": 2, "thrust": [2, 0, 0]}]}': "inputs[0].segments[0]: thrust: each axis must be -1.0 to 1.0",
		'{"segments": [{"ticks": 2, "turn": [0, 0]}]}': "inputs[0].segments[0]: turn: must be a list of three numbers",
		'{"segments": [{"ticks": 2, "fire": 1}]}': "inputs[0].segments[0]: fire: must be true or false",
		'{"segments": [{"ticks": 2, "boost": true}]}': "inputs[0].segments[0]: unknown key \"boost\"",
		'{"loop_from": 1, "segments": [{"ticks": 2}]}': "inputs[0].loop_from: must name one of the 1 segments",
	}
	for text: String in cases:
		var error: String = _parse(text).error
		if error != cases[text]:
			return "%s gave \"%s\", not \"%s\"" % [text, error, cases[text]]
	return ""


func test_a_bad_scene_file_is_rejected_with_its_field() -> String:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(StressScene.SCENE_FILE))
	var broken: Dictionary = good.duplicate(true)
	(broken["lights"] as Array)[2]["range"] = 0
	if StressScene.parse_json(JSON.stringify(broken)).error != "lights[2]: range: must be a number above zero":
		return "a zero light range gave: %s" % StressScene.parse_json(JSON.stringify(broken)).error
	broken = good.duplicate(true)
	(broken["ships"] as Array).pop_back()
	if StressScene.parse_json(JSON.stringify(broken)).error != "ships: must list the 3 ships after ship 0":
		return "two extra ships gave: %s" % StressScene.parse_json(JSON.stringify(broken)).error
	broken = good.duplicate(true)
	broken["level"] = "../stress"
	if not StressScene.parse_json(JSON.stringify(broken)).error.begins_with("level:"):
		return "a path as a level name was accepted"
	broken = good.duplicate(true)
	broken["ship"] = "user://ship.json"
	if not StressScene.parse_json(JSON.stringify(broken)).error.begins_with("ship:"):
		return "a ship file outside res://data/ was accepted"
	return ""
