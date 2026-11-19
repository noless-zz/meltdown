extends RefCounted

## Level walls as a union of boxes (FLT-3, GEN-5): open where boxes overlap,
## solid elsewhere, the same as `BoxBounds` for one box, deterministic.


## A room and a narrower tunnel leaving its far wall. They overlap for 5 m
## (z -20..-15); the tunnel is 4 m across, so a 1 m ship fits through.
func _room_and_tunnel() -> BoxUnion:
	var room: BoxBounds = BoxBounds.new(Vector3(-5.0, -5.0, -20.0), Vector3(5.0, 5.0, 0.0))
	var tunnel: BoxBounds = BoxBounds.new(Vector3(-2.0, -2.0, -60.0), Vector3(2.0, 2.0, -15.0))
	var list: Array[BoxBounds] = [room, tunnel]
	return BoxUnion.new(list)


## An L: a corridor along -z, and one along +x leaving its far end. They share
## the corner cube x -3..3, z -30..-24.
func _l_corner() -> BoxUnion:
	var down: BoxBounds = BoxBounds.new(Vector3(-3.0, -3.0, -30.0), Vector3(3.0, 3.0, 0.0))
	var across: BoxBounds = BoxBounds.new(Vector3(-3.0, -3.0, -30.0), Vector3(40.0, 3.0, -24.0))
	var list: Array[BoxBounds] = [down, across]
	return BoxUnion.new(list)


func _ship_at(position: Vector3, velocity: Vector3) -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.position = position
	ship.velocity = velocity
	return ship


## A scripted, varied input for `tick`: thrust and turn that sweep every axis.
func _thrust(tick: int) -> Vector3:
	return Vector3(sin(tick * 0.031), cos(tick * 0.017), -absf(sin(tick * 0.007)) - 0.2)


func _turn(tick: int) -> Vector3:
	return Vector3(sin(tick * 0.013), cos(tick * 0.011), sin(tick * 0.023)) * 0.8


func test_single_box_matches_box_bounds_over_a_scripted_flight() -> String:
	var box: BoxBounds = BoxBounds.new(Vector3(-5.0, -4.0, -40.0), Vector3(5.0, 4.0, 5.0))
	var list: Array[BoxBounds] = [box]
	var union: BoxUnion = BoxUnion.new(list)
	var alone: ShipState = _ship_at(Vector3.ZERO, Vector3.ZERO)
	var joined: ShipState = _ship_at(Vector3.ZERO, Vector3.ZERO)
	var hits: int = 0
	for tick: int in 900:
		alone.step(_thrust(tick), _turn(tick), tick % 200 < 60)
		joined.step(_thrust(tick), _turn(tick), tick % 200 < 60)
		var expected: Vector3 = box.contain_impact(alone)
		var got: Vector3 = union.contain_impact(joined)
		if got != expected:
			return "tick %d: impact %s, BoxBounds gave %s" % [tick, got, expected]
		if joined.state_hash() != alone.state_hash():
			return "tick %d: state differs from BoxBounds" % tick
		if expected != Vector3.ZERO:
			hits += 1
	if hits == 0:
		return "the scripted flight never hit a wall, so it proves nothing"
	return ""


func test_flying_through_the_shared_opening_does_not_bounce() -> String:
	var union: BoxUnion = _room_and_tunnel()
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, -10.0))
	for tick: int in 120:
		ship.step(Vector3(0.0, 0.0, -1.0), Vector3.ZERO)
		var impact: Vector3 = union.contain_impact(ship)
		if impact != Vector3.ZERO:
			return "tick %d: bounced at %s with impact %s" % [tick, ship.position, impact]
		if ship.velocity.z >= 0.0:
			return "tick %d: forward speed lost at %s" % [tick, ship.position]
	if ship.position.z > -30.0:
		return "ship only reached z %f, not deep into the tunnel" % ship.position.z
	if ship.hull != ship.max_hull or ship.shield != ship.max_shield:
		return "ship took damage passing through the opening"
	return ""


func test_room_wall_beside_the_opening_bounces() -> String:
	var union: BoxUnion = _room_and_tunnel()
	# x = 4 is in the room but outside the tunnel mouth (x -2..2).
	var ship: ShipState = _ship_at(Vector3(4.0, 0.0, -19.3), Vector3(0.0, 0.0, -15.0))
	var impact: Vector3 = union.contain_impact(ship)
	if not impact.is_equal_approx(Vector3(0.0, 0.0, -15.0)):
		return "impact %s, expected the full -15 into the room's far wall" % impact
	if ship.velocity.z <= 0.0:
		return "ship was not reflected: %s" % ship.velocity
	if not union.holds(ship.position, ship.radius):
		return "ship ended outside the union at %s" % ship.position
	return ""


func test_solid_wall_of_the_second_box_bounces() -> String:
	var union: BoxUnion = _room_and_tunnel()
	var side: ShipState = _ship_at(Vector3(0.9, 0.0, -40.0), Vector3(12.0, 0.0, -5.0))
	side.step(Vector3.ZERO, Vector3.ZERO)
	var side_impact: Vector3 = union.contain_impact(side)
	if side_impact.x <= 0.0 or side.velocity.x >= 0.0:
		return "tunnel side wall did not bounce: impact %s, velocity %s" % [side_impact, side.velocity]
	if side.velocity.z >= 0.0:
		return "tangential speed along the tunnel was reversed: %s" % side.velocity
	var end: ShipState = _ship_at(Vector3(0.0, 0.0, -59.3), Vector3(0.0, 0.0, -15.0))
	var end_impact: Vector3 = union.contain_impact(end)
	if end_impact.z >= 0.0 or end.velocity.z <= 0.0:
		return "tunnel end wall did not bounce: impact %s, velocity %s" % [end_impact, end.velocity]
	if not union.holds(side.position, side.radius) or not union.holds(end.position, end.radius):
		return "a bounced ship ended outside the union"
	return ""


func test_turning_the_corner_does_not_bounce() -> String:
	var union: BoxUnion = _l_corner()
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -27.0), Vector3(10.0, 0.0, 0.0))
	for tick: int in 90:
		ship.step(Vector3(1.0, 0.0, 0.0), Vector3.ZERO)
		var impact: Vector3 = union.contain_impact(ship)
		if impact != Vector3.ZERO:
			return "tick %d: bounced at %s with impact %s" % [tick, ship.position, impact]
	if ship.position.x < 20.0:
		return "ship only reached x %f along the second corridor" % ship.position.x
	return ""


func test_outer_corner_hit_bounces_on_both_walls() -> String:
	var union: BoxUnion = _l_corner()
	var ship: ShipState = _ship_at(Vector3(-2.3, 0.0, -29.4), Vector3(-9.0, 0.0, -12.0))
	var impact: Vector3 = union.contain_impact(ship)
	if not impact.is_equal_approx(Vector3(-9.0, 0.0, -12.0)):
		return "corner impact %s, expected both components" % impact
	if ship.velocity.x <= 0.0 or ship.velocity.z <= 0.0:
		return "not both walls reflected the ship: %s" % ship.velocity
	if not union.holds(ship.position, ship.radius):
		return "ship ended outside the union at %s" % ship.position
	return ""


func test_inner_corner_overshoot_ends_inside() -> String:
	var union: BoxUnion = _l_corner()
	# Past the inner corner edge (x 3, z -24): held by neither corridor.
	var ship: ShipState = _ship_at(Vector3(3.5, 0.0, -23.2), Vector3(6.0, 0.0, 6.0))
	if union.holds(ship.position, ship.radius):
		return "test set-up: the ship should start outside both corridors"
	var impact: Vector3 = union.contain_impact(ship)
	if impact == Vector3.ZERO:
		return "an overshoot past the inner corner reported no hit"
	if not union.holds(ship.position, ship.radius):
		return "ship ended outside the union at %s" % ship.position
	return ""


func test_box_for_prefers_the_lowest_index_holder() -> String:
	var union: BoxUnion = _room_and_tunnel()
	# Inside the overlap, so both boxes hold it.
	if union.box_for(Vector3(0.0, 0.0, -17.5), 1.0) != union.boxes[0]:
		return "a point in the overlap did not pick box 0"
	if union.box_for(Vector3(0.0, 0.0, -30.0), 1.0) != union.boxes[1]:
		return "a point only in the tunnel did not pick box 1"
	return ""


func test_box_for_ties_go_to_the_lower_index() -> String:
	var a: BoxBounds = BoxBounds.new(Vector3(-10.0, -1.0, -1.0), Vector3(-2.0, 1.0, 1.0))
	var b: BoxBounds = BoxBounds.new(Vector3(2.0, -1.0, -1.0), Vector3(10.0, 1.0, 1.0))
	var forward: Array[BoxBounds] = [a, b]
	var reverse: Array[BoxBounds] = [b, a]
	# x = 0 is 3 m from both shrunk interiors.
	if BoxUnion.new(forward).box_for(Vector3.ZERO, 1.0) != a:
		return "tie did not go to box 0 (a)"
	if BoxUnion.new(reverse).box_for(Vector3.ZERO, 1.0) != b:
		return "tie did not go to box 0 (b) with the order reversed"
	if BoxUnion.new(forward).box_for(Vector3(0.5, 0.0, 0.0), 1.0) != b:
		return "the nearer box lost to the lower index"
	return ""


func test_nearest_uses_the_interior_shrunk_by_radius() -> String:
	# For a 2 m sphere at the point, the solid box's wall is nearer (1 m vs
	# 1.5 m), but the thin slab's shrunk interior (its centre line, y = 2) is
	# nearer than the solid box's (z <= 7, 3 m away).
	var solid: BoxBounds = BoxBounds.new(Vector3(-10.0, -10.0, -20.0), Vector3(10.0, 10.0, 9.0))
	var slab: BoxBounds = BoxBounds.new(Vector3(-10.0, 1.5, -20.0), Vector3(10.0, 2.5, 40.0))
	var list: Array[BoxBounds] = [solid, slab]
	var union: BoxUnion = BoxUnion.new(list)
	var point: Vector3 = Vector3(0.0, 0.0, 10.0)
	if union.holds(point, 2.0):
		return "test set-up: the point should not be held"
	if union.box_for(point, 2.0) != slab:
		return "did not pick the box whose shrunk interior is nearest"
	return ""


func test_holds_any_box() -> String:
	var union: BoxUnion = _room_and_tunnel()
	if not union.holds(Vector3(4.0, 4.0, -2.0), 1.0):
		return "a point in the room was not held"
	if not union.holds(Vector3(0.0, 0.0, -50.0), 1.0):
		return "a point in the tunnel was not held"
	if union.holds(Vector3(4.0, 0.0, -30.0), 1.0):
		return "a point in solid rock beside the tunnel was held"
	if union.holds(Vector3(0.0, 0.0, -25.0), 3.0):
		return "a sphere wider than the tunnel was held in it"
	return ""


func test_empty_union_contains_nothing() -> String:
	var union: BoxUnion = BoxUnion.new()
	var ship: ShipState = _ship_at(Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0))
	if union.box_for(ship.position, ship.radius) != null:
		return "an empty union returned a box"
	if union.holds(ship.position, ship.radius):
		return "an empty union held a point"
	if union.contain_impact(ship) != Vector3.ZERO or ship.position != Vector3(1.0, 2.0, 3.0):
		return "an empty union moved the ship"
	return ""


func _flight_hashes(union: BoxUnion) -> Array[int]:
	var hashes: Array[int] = []
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -2.0), Vector3.ZERO)
	for tick: int in 900:
		ship.step(_thrust(tick), _turn(tick), tick % 150 < 40)
		union.contain_impact(ship)
		hashes.append(ship.state_hash())
	return hashes


func test_deterministic_over_two_runs() -> String:
	var first: Array[int] = _flight_hashes(_l_corner())
	var second: Array[int] = _flight_hashes(_l_corner())
	for tick: int in first.size():
		if first[tick] != second[tick]:
			return "runs differ from tick %d" % tick
	var union: BoxUnion = _l_corner()
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -2.0), Vector3.ZERO)
	for tick: int in 900:
		ship.step(_thrust(tick), _turn(tick), tick % 150 < 40)
		union.contain_impact(ship)
		if not union.holds(ship.position, ship.radius):
			return "tick %d: ship left the union at %s" % [tick, ship.position]
	return ""
