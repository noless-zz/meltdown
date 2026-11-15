class_name BoxBounds
extends RefCounted

## The inside of an axis-aligned box that ships fly in: the test tunnel, until
## mine modules arrive (M3). Walls bounce ships back with minor damage (FLT-3).
##
## Geometry only. How hard a ship bounces and how much it is hurt are ship
## values (`ShipState.radius`, `wall_restitution`, ...), so that a later ship
## or part data file can set them (ARC-4).

## Corners in metres. Every component of `min_corner` is below `max_corner`.
var min_corner: Vector3 = Vector3.ZERO
var max_corner: Vector3 = Vector3.ZERO


func _init(p_min_corner: Vector3 = Vector3.ZERO, p_max_corner: Vector3 = Vector3.ZERO) -> void:
	min_corner = p_min_corner
	max_corner = p_max_corner


## Keeps `ship` inside the box at the end of a tick. On each axis where the
## ship's sphere crossed a wall, the overshoot is mirrored back inside, the
## velocity component into that wall is reflected and scaled by the ship's
## restitution, and the tangential components are kept. A hit on two or three
## walls in the same tick (a corner) is one impact, whose speed is the length
## of the into-wall components together.
## Returns that impact speed in metres per second, or 0.0 when nothing was hit.
func contain(ship: ShipState) -> float:
	return contain_impact(ship).length()


## Same as `contain`, but returns the velocity the ship carried into the walls
## it hit this tick (only the into-wall components, before the bounce), or
## Vector3.ZERO when nothing was hit. Its length is the impact speed and its
## reverse is the wall normal, which `Sim` reports as a wall impact event.
func contain_impact(ship: ShipState) -> Vector3:
	var impact: Vector3 = Vector3.ZERO
	var bounce: float = ship.bounce_factor()
	for axis: int in 3:
		var low: float = min_corner[axis] + ship.radius
		var high: float = max_corner[axis] - ship.radius
		if low > high:
			# Box narrower than the ship on this axis: hold it on the centre line.
			low = (min_corner[axis] + max_corner[axis]) * 0.5
			high = low
		var place: float = ship.position[axis]
		var speed: float = ship.velocity[axis]
		if place < low:
			ship.position[axis] = minf(low + (low - place) * bounce, high)
			if speed < 0.0:
				impact[axis] = speed
				ship.velocity[axis] = -speed * bounce
		elif place > high:
			ship.position[axis] = maxf(high - (place - high) * bounce, low)
			if speed > 0.0:
				impact[axis] = speed
				ship.velocity[axis] = -speed * bounce
	var impact_speed: float = impact.length()
	if impact_speed > 0.0:
		ship.take_wall_hit(impact_speed)
	return impact


## True if a sphere of `radius` at `point` lies wholly inside the box.
func holds(point: Vector3, radius: float) -> bool:
	for axis: int in 3:
		if point[axis] < min_corner[axis] + radius or point[axis] > max_corner[axis] - radius:
			return false
	return true
