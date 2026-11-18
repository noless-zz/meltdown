extends RefCounted

## The bot pilot's weave across the line of fire (#492).

const THREAT: Vector3 = Vector3(0.0, 0.0, -30.0)


func _walls(size: Vector3) -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(-size, size)]
	return BoxUnion.new(boxes)


## A ship at `position` facing -z, towards THREAT.
func _ship(position: Vector3 = Vector3.ZERO) -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.position = position
	return ship


func test_the_weave_is_across_the_line_of_fire_at_full_speed() -> String:
	var dodge: BotDodge = BotDodge.new(_walls(Vector3(20.0, 20.0, 50.0)))
	var ship: ShipState = _ship()
	var weave: Vector3 = dodge.velocity(ship, THREAT)
	if absf(weave.dot((THREAT - ship.position).normalized())) > 1e-4:
		return "weave %s runs along the line of fire" % weave
	if not is_equal_approx(weave.length(), BotDodge.SPEED):
		return "weave speed %f, expected %f" % [weave.length(), BotDodge.SPEED]
	return ""


## It keeps its sense while there is room, and turns about at a wall.
func test_the_weave_keeps_its_sense_and_turns_about_at_a_wall() -> String:
	var dodge: BotDodge = BotDodge.new(_walls(Vector3(10.0, 20.0, 50.0)))
	var ship: ShipState = _ship()
	var first: Vector3 = dodge.velocity(ship, THREAT)
	if first.normalized() != Vector3.RIGHT:
		return "set-up: the first weave is %s, expected along the ship's right" % first
	ship.position = Vector3(4.0, 0.0, 0.0)
	if dodge.velocity(ship, THREAT).normalized().x < 0.9:
		return "the weave turned about with room to spare"
	ship.position = Vector3(7.0, 0.0, 0.0)
	var back: Vector3 = dodge.velocity(ship, THREAT)
	if back.normalized().x > -0.9:
		return "at the wall the weave is %s, expected back to the left" % back
	return ""


## In a tube no wider than the ship's room to weave, there is nothing to do.
func test_no_weave_without_room() -> String:
	var dodge: BotDodge = BotDodge.new(_walls(Vector3(2.0, 2.0, 50.0)))
	var weave: Vector3 = dodge.velocity(_ship(), THREAT)
	if weave != Vector3.ZERO:
		return "weave %s in a tube with no room" % weave
	return ""


## The same calls give the same weave (ARC-2).
func test_the_weave_is_deterministic() -> String:
	var walls: BoxUnion = _walls(Vector3(10.0, 10.0, 50.0))
	var a: BotDodge = BotDodge.new(walls)
	var b: BotDodge = BotDodge.new(walls)
	var ship: ShipState = _ship(Vector3(3.0, -2.0, 1.0))
	for step: int in 5:
		ship.position.x += 1.5
		if a.velocity(ship, THREAT) != b.velocity(ship, THREAT):
			return "the weaves differ at step %d" % step
	return ""
