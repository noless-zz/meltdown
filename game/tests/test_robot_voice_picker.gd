extends RefCounted

## Choosing robot voices (#1363, AUD-2, PRF-1): the nearest within range up
## to the cap, louder and higher as they near and speed up, muffled when no
## level box holds both robot and pilot, and gone once a robot is destroyed.

const TABLE: String = """{"max_voices": 2, "reference_m": 2, "far_cutoff_hz": 2000,
	"muffle_cutoff_hz": 600, "voices": {
	"drone": {"sound": "res://d.wav", "volume_db": -6, "pitch_min": 1.0, "pitch_max": 1.5,
		"range_m": 30, "muffle_db": -10},
	"hauler": {"sound": "res://h.wav", "volume_db": -3, "pitch_min": 0.9, "pitch_max": 1.1,
		"range_m": 50, "muffle_db": -8}}}"""


static func _robot(id: String, position: Vector3, max_speed: float = 8.0) -> RobotState:
	var def: RobotDef = RobotDef.new()
	def.id = id
	def.max_speed = max_speed
	return RobotState.new(def, position)


static func _robots(list: Array) -> Array[RobotState]:
	var typed: Array[RobotState] = []
	typed.assign(list)
	return typed


## Two rooms joined by a tunnel along x: room A x -20..0, tunnel x -2..22 (narrow), room B x 20..40.
static func _walls() -> BoxUnion:
	var boxes: Array[BoxBounds] = [
		BoxBounds.new(Vector3(-20, -10, -10), Vector3(0, 10, 10)),
		BoxBounds.new(Vector3(-2, -2, -2), Vector3(22, 2, 2)),
		BoxBounds.new(Vector3(20, -10, -10), Vector3(40, 10, 10)),
	]
	return BoxUnion.new(boxes)


func test_nearest_within_range_up_to_the_cap() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.parse(TABLE)
	var robots: Array[RobotState] = _robots([
		_robot("drone", Vector3(20, 0, 0)),
		_robot("drone", Vector3(5, 0, 0)),
		_robot("drone", Vector3(40, 0, 0)),  # past the drone's 30 m
		_robot("hauler", Vector3(0, 10, 0)),
		_robot("warden", Vector3(1, 0, 0)),  # no row: silent
	])
	var mixes: Array[RobotVoiceMix] = RobotVoicePicker.pick(table, robots, Vector3.ZERO, null)
	if mixes.size() != 2:
		return "%d voices; the cap is 2" % mixes.size()
	if mixes[0].robot_index != 1 or mixes[1].robot_index != 3:
		return "chose robots %d and %d, expected 1 and 3" % [mixes[0].robot_index, mixes[1].robot_index]
	return "" if mixes[1].type_id == "hauler" and mixes[0].sound == "res://d.wav" else "rows not matched"


func test_ties_go_to_the_lower_index() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.parse(TABLE)
	table.max_voices = 1
	var robots: Array[RobotState] = _robots([_robot("drone", Vector3(0, 5, 0)), _robot("drone", Vector3(5, 0, 0))])
	var mixes: Array[RobotVoiceMix] = RobotVoicePicker.pick(table, robots, Vector3.ZERO, null)
	return "" if mixes.size() == 1 and mixes[0].robot_index == 0 else "the tie did not go to robot 0"


func test_louder_as_it_nears_and_higher_as_it_speeds_up() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.parse(TABLE)
	var near: RobotState = _robot("drone", Vector3(3, 0, 0))
	var far: RobotState = _robot("drone", Vector3(12, 0, 0))
	far.velocity = Vector3(8, 0, 0)
	var mixes: Array[RobotVoiceMix] = RobotVoicePicker.pick(table, _robots([far, near]), Vector3.ZERO, null)
	if mixes[0].robot_index != 1 or mixes[0].heard_db <= mixes[1].heard_db:
		return "the near robot is not heard louder: %.1f vs %.1f" % [mixes[0].heard_db, mixes[1].heard_db]
	if not is_equal_approx(mixes[1].heard_db, -6.0 + RobotVoicePicker.falloff_db(12.0, 2.0)):
		return "far level %.2f" % mixes[1].heard_db
	if not is_equal_approx(mixes[0].pitch, 1.0) or not is_equal_approx(mixes[1].pitch, 1.5):
		return "pitches %.2f and %.2f" % [mixes[0].pitch, mixes[1].pitch]
	return "" if is_equal_approx(RobotVoicePicker.falloff_db(1.0, 2.0), 0.0) else "falloff inside reference_m"


func test_falloff_is_six_db_a_doubling() -> String:
	var at_four: float = RobotVoicePicker.falloff_db(4.0, 2.0)
	var at_eight: float = RobotVoicePicker.falloff_db(8.0, 2.0)
	return "" if absf(at_four + 6.02) < 0.01 and absf(at_eight - at_four + 6.02) < 0.01 \
		else "falloff %.2f, %.2f" % [at_four, at_eight]


func test_a_wall_muffles_and_quietens() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.parse(TABLE)
	var walls: BoxUnion = _walls()
	var listener: Vector3 = Vector3(-10, 5, 0)  # in room A, off the tunnel's line
	var in_room: RobotState = _robot("drone", Vector3(-10, -5, 0))
	var behind: RobotState = _robot("drone", Vector3(10, 0, 0))  # in the tunnel, round the room's wall
	var mixes: Array[RobotVoiceMix] = RobotVoicePicker.pick(table, _robots([in_room, behind]), listener, walls)
	if mixes.size() != 2:
		return "%d voices" % mixes.size()
	if mixes[0].muffled or not mixes[1].muffled:
		return "muffled flags %s, %s" % [mixes[0].muffled, mixes[1].muffled]
	if not is_equal_approx(mixes[1].player_db, -16.0) or not is_equal_approx(mixes[0].player_db, -6.0):
		return "volumes %.1f, %.1f" % [mixes[0].player_db, mixes[1].player_db]
	var open: float = -6.0 + RobotVoicePicker.falloff_db(mixes[1].distance, 2.0)
	if mixes[1].heard_db >= open:
		return "the muffled voice is not quieter than in the open"
	if RobotVoicePicker.muffled(walls, listener, Vector3(-1, 0, 0)):
		return "a robot in the same room is muffled"
	if not RobotVoicePicker.muffled(walls, listener, Vector3(30, 0, 0)):
		return "a robot in the far room is not muffled"
	return "" if not RobotVoicePicker.muffled(null, listener, Vector3(30, 0, 0)) else "no walls muffled"


func test_destroyed_robot_is_not_heard() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.parse(TABLE)
	var dead: RobotState = _robot("drone", Vector3(1, 0, 0))
	dead.hull = 0.0
	var alive: RobotState = _robot("drone", Vector3(6, 0, 0))
	var mixes: Array[RobotVoiceMix] = RobotVoicePicker.pick(table, _robots([dead, alive]), Vector3.ZERO, null)
	return "" if mixes.size() == 1 and mixes[0].robot_index == 1 else "%d voices with one robot destroyed" % mixes.size()


func test_picking_writes_nothing() -> String:
	var table: RobotVoiceTable = RobotVoiceTable.parse(TABLE)
	var robot: RobotState = _robot("hauler", Vector3(4, 0, 0))
	robot.velocity = Vector3(1, 2, 3)
	RobotVoicePicker.pick(table, _robots([robot]), Vector3.ZERO, _walls())
	return "" if robot.position == Vector3(4, 0, 0) and robot.velocity == Vector3(1, 2, 3) \
		and robot.hull == robot.def.hull else "picking changed the robot"
