extends RefCounted

## The room reverb table (#1291, AUD-1, ARC-4): the shipped file is read; a
## small tunnel and the largest room sound different; the same position always
## gives the same setting; values come from the boxes, not from module names.

const MODULES_DIR: String = "res://data/modules"


## [module id, its boxes] for every shipped module file.
static func _modules() -> Array:
	var found: Array = []
	for file: String in DirAccess.get_files_at(MODULES_DIR):
		if not file.ends_with(".json"):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MODULES_DIR + "/" + file))
		var boxes: Array[BoxBounds] = []
		for row: Dictionary in data["boxes"]:
			var low: Array = row["min"]
			var high: Array = row["max"]
			boxes.append(BoxBounds.new(Vector3(low[0], low[1], low[2]), Vector3(high[0], high[1], high[2])))
		found.append([str(data["id"]), boxes])
	return found


static func _widest(boxes: Array[BoxBounds]) -> BoxBounds:
	var best: BoxBounds = boxes[0]
	for box: BoxBounds in boxes:
		if RoomReverbTable.span_of(box) > RoomReverbTable.span_of(best):
			best = box
	return best


func test_shipped_table_is_read() -> String:
	var table: RoomReverbTable = RoomReverbTable.load_file()
	if table.error != "":
		return table.error
	return "" if table.settings.size() >= 2 and table.blend_seconds > 0.0 else "no blend or fewer than two points"


func test_small_tunnel_and_largest_room_differ() -> String:
	var table: RoomReverbTable = RoomReverbTable.load_file()
	var tunnel: BoxBounds = null
	var room: BoxBounds = null
	for module: Array in _modules():
		var widest: BoxBounds = _widest(module[1])
		if module[0] == "straight_tunnel":
			tunnel = widest
		if room == null or RoomReverbTable.span_of(widest) > RoomReverbTable.span_of(room):
			room = widest
	if tunnel == null:
		return "no straight_tunnel module"
	var small: ReverbSetting = table.setting_for_span(RoomReverbTable.span_of(tunnel))
	var large: ReverbSetting = table.setting_for_span(RoomReverbTable.span_of(room))
	if not (large.room_size > small.room_size + 0.2):
		return "tunnel %s and largest room %s are too alike" % [small, large]
	return "" if large.damping < small.damping and large.wet > small.wet else \
		"the room %s should be less damped and wetter than the tunnel %s" % [large, small]


func test_same_position_same_setting() -> String:
	var table: RoomReverbTable = RoomReverbTable.load_file()
	var walls: BoxUnion = _tunnel_into_room()
	for point: Vector3 in [Vector3(0, 0, -10), Vector3(0, 0, -29), Vector3(0, 0, -40)]:
		var first: ReverbSetting = table.setting_at(walls, point)
		for again: int in 5:
			if not table.setting_at(_tunnel_into_room(), point).same_as(first):
				return "%s gave two settings" % point
	return ""


func test_overlap_hears_the_wider_box() -> String:
	var table: RoomReverbTable = RoomReverbTable.load_file()
	var walls: BoxUnion = _tunnel_into_room()
	# z = -29 is in both the tunnel and the room.
	var heard: ReverbSetting = table.setting_at(walls, Vector3(0, 0, -29))
	var room: ReverbSetting = table.setting_for_span(RoomReverbTable.span_of(walls.boxes[1]))
	return "" if heard.same_as(room) else "heard %s in the overlap, not the room's %s" % [heard, room]


func test_outside_every_box_is_null() -> String:
	var table: RoomReverbTable = RoomReverbTable.load_file()
	return "" if table.setting_at(_tunnel_into_room(), Vector3(100, 0, 0)) == null else "rock has a reverb"


func test_span_ignores_length() -> String:
	var short: BoxBounds = BoxBounds.new(Vector3(-5, -5, -10), Vector3(5, 5, 0))
	var long: BoxBounds = BoxBounds.new(Vector3(-5, -5, -100), Vector3(5, 5, 0))
	if not is_equal_approx(RoomReverbTable.span_of(short), RoomReverbTable.span_of(long)):
		return "a longer tunnel sounds wider"
	return "" if is_equal_approx(RoomReverbTable.span_of(short), 10.0) else "span %f" % RoomReverbTable.span_of(short)


func test_points_are_interpolated_and_clamped() -> String:
	var table: RoomReverbTable = RoomReverbTable.parse('{"blend_seconds": 1, "points": ['
		+ '{"span_m": 10, "room_size": 0.2, "damping": 0.8, "wet": 0.1},'
		+ '{"span_m": 20, "room_size": 0.6, "damping": 0.4, "wet": 0.3}]}')
	if table.error != "":
		return table.error
	if not table.setting_for_span(15).same_as(ReverbSetting.new(0.4, 0.6, 0.2)):
		return "midway gave %s" % table.setting_for_span(15)
	if not table.setting_for_span(2).same_as(table.settings[0]):
		return "below the first point gave %s" % table.setting_for_span(2)
	return "" if table.setting_for_span(90).same_as(table.settings[1]) else "past the last point moved"


func test_bad_files_are_rejected_naming_the_field() -> String:
	var cases: Dictionary = {
		"[]": "JSON object",
		'{"points": []}': "blend_seconds",
		'{"blend_seconds": 1, "points": []}': "points",
		'{"blend_seconds": 1, "points": [{"span_m": 1, "room_size": 0.1, "damping": 0.1}]}': "points[0].wet",
		'{"blend_seconds": 1, "points": [{"span_m": 1, "room_size": 2, "damping": 0.1, "wet": 0}]}': "room_size",
		'{"blend_seconds": 1, "points": [{"span_m": 5, "room_size": 0, "damping": 0, "wet": 0},'
			+ '{"span_m": 5, "room_size": 0, "damping": 0, "wet": 0}]}': "points[1].span_m",
	}
	for text: String in cases:
		var table: RoomReverbTable = RoomReverbTable.parse(text)
		if not table.error.contains(cases[text]):
			return "%s gave error '%s'" % [text, table.error]
		if not table.settings.is_empty():
			return "%s kept settings" % text
	return "" if RoomReverbTable.load_file("res://no_such.json").error.contains("no such file") else "missing file read"


## A 10 m tunnel along -z reaching 2 m into a 24 m room.
static func _tunnel_into_room() -> BoxUnion:
	return BoxUnion.new([
		BoxBounds.new(Vector3(-5, -5, -30), Vector3(5, 5, 0)),
		BoxBounds.new(Vector3(-12, -12, -52), Vector3(12, 12, -28)),
	] as Array[BoxBounds])
