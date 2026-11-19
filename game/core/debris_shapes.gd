class_name DebrisShapes
extends RefCounted

## The shape tests behind `MeltdownDebris` (RUN-4): spheres for falling rocks and
## axis-aligned boxes for blast doors and cave-ins. Each is a solid wall to ships
## (FLT-3) and a stop to shots. Kept apart so the debris list stays small.
##
## A push-out moves the ship and turns its velocity; the caller adds up the
## returned impacts and applies the wall damage once, as `BoxBounds` does.


## Where the segment `from`..`to` first enters the sphere, as a fraction 0..1,
## or -1.0. A start inside is an entry at 0.
static func sphere_entry(from: Vector3, to: Vector3, centre: Vector3, radius: float) -> float:
	return Projectile.segment_entry(from, to, centre, radius)


## Where the segment `from`..`to` first enters the box around `centre` with
## half sizes `half`, as a fraction 0..1, or -1.0. A start inside or on the
## surface is an entry at 0, as for a sphere.
static func box_entry(from: Vector3, to: Vector3, centre: Vector3, half: Vector3) -> float:
	var low: Vector3 = centre - half
	var high: Vector3 = centre + half
	var enter: float = 0.0
	var leave: float = 1.0
	for axis: int in 3:
		var start: float = from[axis]
		var path: float = to[axis] - start
		if path == 0.0:
			if start < low[axis] or start > high[axis]:
				return -1.0
			continue
		var near: float = (low[axis] - start) / path
		var far: float = (high[axis] - start) / path
		if near > far:
			var swap: float = near
			near = far
			far = swap
		enter = maxf(enter, near)
		leave = minf(leave, far)
		if enter > leave:
			return -1.0
	return enter


## Pushes `ship` out of the sphere as a wall would: the overshoot along the line
## between centres is mirrored back out and the velocity into the sphere is
## reflected, scaled by `bounce`. Returns the velocity carried in, or zero.
static func push_out_of_sphere(ship: ShipState, centre: Vector3, radius: float,
		bounce: float) -> Vector3:
	var offset: Vector3 = ship.position - centre
	var reach: float = ship.radius + radius
	var distance: float = offset.length()
	if distance >= reach:
		return Vector3.ZERO
	# A ship exactly at the centre has no line out; up is as good as any and
	# the same on every device.
	var normal: Vector3 = Vector3.UP if distance == 0.0 else offset / distance
	ship.position = centre + normal * (reach + (reach - distance) * bounce)
	return _reflect(ship, normal, bounce)


## Pushes `ship` out of the box around `centre` with half sizes `half`. Outside
## the box the line out runs from the nearest point on the box, so a face hit
## matches a wall and an edge or corner hit matches a sphere. With its centre
## inside, the ship leaves through the nearest face (the lowest axis on a tie,
## the positive side at the exact centre), the overshoot measured from where
## its surface would touch that face.
static func push_out_of_box(ship: ShipState, centre: Vector3, half: Vector3,
		bounce: float) -> Vector3:
	var local: Vector3 = ship.position - centre
	var nearest: Vector3 = local.clamp(-half, half)
	if nearest != local:
		var offset: Vector3 = local - nearest
		var distance: float = offset.length()
		if distance >= ship.radius:
			return Vector3.ZERO
		var normal: Vector3 = offset / distance
		ship.position = centre + nearest + normal * (ship.radius + (ship.radius - distance) * bounce)
		return _reflect(ship, normal, bounce)
	var axis: int = 0
	for other: int in [1, 2]:
		if half[other] - absf(local[other]) < half[axis] - absf(local[axis]):
			axis = other
	var side: float = -1.0 if local[axis] < 0.0 else 1.0
	var overshoot: float = ship.radius + half[axis] - absf(local[axis])
	var face_normal: Vector3 = Vector3.ZERO
	face_normal[axis] = side
	ship.position[axis] = centre[axis] + side * (half[axis] + ship.radius + overshoot * bounce)
	return _reflect(ship, face_normal, bounce)


static func _reflect(ship: ShipState, normal: Vector3, bounce: float) -> Vector3:
	var into: float = ship.velocity.dot(normal)
	if into >= 0.0:
		return Vector3.ZERO
	ship.velocity -= normal * into * (1.0 + bounce)
	return normal * into
