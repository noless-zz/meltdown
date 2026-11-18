class_name BotDodge
extends RefCounted

## Sideways weaving for the bot pilot while robots can shoot it (CMB-3, #492).
##
## Robots fire along their facing at where the ship is, not where it will be
## (`RobotState.fire_at`), so a ship that keeps moving across the line of fire
## is missed: at 20 m a needle takes about a tenth of a second to arrive and a
## slug a third, and the ship's radius is 1 m. Before this the bot flew mostly
## straight at its target and took nearly every shot; over seeds 1..300 with
## robots and debris every uncleared flight ended with the ship destroyed.
##
## The weave is a velocity across the line to the nearest robot that can hit
## the ship, added to whatever the bot wants along its route. It keeps its
## sense until the walls stop it, then turns about. Directions come from the
## ship's own axes in a fixed order, so the same flight gives the same inputs
## (ARC-1, ARC-2). Only reads the sim (MP-2).

## Speed across the line of fire the bot asks for, metres per second.
const SPEED: float = 15.0
## How far ahead the walls must leave room for the weave, metres, beyond the
## ship's radius.
const LOOK_AHEAD: float = 3.0

var _walls: BoxUnion = null
## The present weave direction, unit length; zero when not weaving.
var _direction: Vector3 = Vector3.ZERO


func _init(walls: BoxUnion) -> void:
	_walls = walls


## The velocity to add across the line from `ship` to `threat`, a robot's
## position; zero when there is no room to weave at all.
func velocity(ship: ShipState, threat: Vector3) -> Vector3:
	var line: Vector3 = threat - ship.position
	if line.length_squared() < 1e-6:
		return Vector3.ZERO
	line = line.normalized()
	var kept: Vector3 = _across(_direction, line)
	if kept != Vector3.ZERO and _room(ship, kept):
		_direction = kept
		return _direction * SPEED
	if kept != Vector3.ZERO and _room(ship, -kept):
		_direction = -kept
		return _direction * SPEED
	for axis: Vector3 in [ship.orientation.x, ship.orientation.y, ship.orientation.z]:
		var across: Vector3 = _across(axis, line)
		if across == Vector3.ZERO:
			continue
		for sense: float in [1.0, -1.0]:
			if _room(ship, across * sense):
				_direction = across * sense
				return _direction * SPEED
	_direction = Vector3.ZERO
	return Vector3.ZERO


## Stops weaving, so the next weave picks its direction afresh.
func reset() -> void:
	_direction = Vector3.ZERO


## `direction` with its part along `line` removed, unit length, or zero when
## little is left.
static func _across(direction: Vector3, line: Vector3) -> Vector3:
	var across: Vector3 = direction - line * direction.dot(line)
	if across.length_squared() < 0.09:
		return Vector3.ZERO
	return across.normalized()


func _room(ship: ShipState, direction: Vector3) -> bool:
	return _walls.holds(ship.position + direction * LOOK_AHEAD, ship.radius)
