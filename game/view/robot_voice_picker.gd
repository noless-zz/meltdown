class_name RobotVoicePicker
extends RefCounted

## Chooses which robots are heard this tick and how (#1363, AUD-2, PRF-1).
## Every live robot whose type has a voice and which is within its range is a
## candidate; the nearest `max_voices` sound, ties to the lower index, so a
## full room does not overload the Quest.
##
## A wall between robot and pilot is read from the level boxes, not from a ray:
## every box is convex, so a box holding both points holds the line between
## them and nothing stands in the way. When no box holds both, the voice is
## muffled. That can call a robot round a shallow corner muffled when part of
## it might be seen, which errs towards the "hear it before you see it" the
## requirement asks for.
##
## Pure: it reads copies and writes nothing (ARC-1, MP-2).


## The voices for `robots` (session copies, in the simulation's order) heard at
## `listener` in `walls`, nearest first. A null `walls` muffles nothing.
static func pick(table: RobotVoiceTable, robots: Array[RobotState], listener: Vector3,
		walls: BoxUnion) -> Array[RobotVoiceMix]:
	var around: Array[BoxBounds] = boxes_holding(walls, listener)
	var candidates: Array[RobotVoiceMix] = []
	for index: int in robots.size():
		var robot: RobotState = robots[index]
		if robot == null or robot.def == null or robot.hull <= 0.0:
			continue
		var row: RobotVoiceRow = table.voice(robot.def.id)
		if row == null:
			continue
		var distance: float = robot.position.distance_to(listener)
		if distance > row.range_m:
			continue
		candidates.append(_mix(table, row, robot, index, distance, walls != null and not _shares_box(around, robot.position)))
	candidates.sort_custom(_nearer)
	if candidates.size() > table.max_voices:
		candidates.resize(table.max_voices)
	return candidates


## Whether a wall may stand between `a` and `b` in `walls`: no box holds both.
static func muffled(walls: BoxUnion, a: Vector3, b: Vector3) -> bool:
	if walls == null:
		return false
	return not _shares_box(boxes_holding(walls, a), b)


## The boxes of `walls` holding `point`.
static func boxes_holding(walls: BoxUnion, point: Vector3) -> Array[BoxBounds]:
	var holding: Array[BoxBounds] = []
	if walls == null:
		return holding
	for box: BoxBounds in walls.boxes:
		if box.holds(point, 0.0):
			holding.append(box)
	return holding


## The inverse-distance fall-off in dB at `distance` past `reference_m`: 0
## within it, -6 dB for each doubling beyond.
static func falloff_db(distance: float, reference_m: float) -> float:
	return -20.0 * log(maxf(distance, reference_m) / reference_m) / log(10.0)


static func _shares_box(boxes: Array[BoxBounds], point: Vector3) -> bool:
	for box: BoxBounds in boxes:
		if box.holds(point, 0.0):
			return true
	return false


static func _mix(table: RobotVoiceTable, row: RobotVoiceRow, robot: RobotState, index: int,
		distance: float, is_muffled: bool) -> RobotVoiceMix:
	var mix: RobotVoiceMix = RobotVoiceMix.new()
	mix.robot_index = index
	mix.type_id = row.id
	mix.sound = row.sound
	mix.position = robot.position
	mix.distance = distance
	mix.muffled = is_muffled
	mix.player_db = row.volume_db + (row.muffle_db if is_muffled else 0.0)
	mix.heard_db = mix.player_db + falloff_db(distance, table.reference_m)
	mix.pitch = row.pitch_for(robot.velocity.length(), robot.def.max_speed)
	return mix


static func _nearer(a: RobotVoiceMix, b: RobotVoiceMix) -> bool:
	if a.distance != b.distance:
		return a.distance < b.distance
	return a.robot_index < b.robot_index
