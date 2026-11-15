extends RefCounted

## Wall bounces inside a box (FLT-3): reflection, damage and determinism.

const TICKS: int = 600


## A box 10 m wide and high whose far wall is 40 m ahead of the start point.
func _box() -> BoxBounds:
	return BoxBounds.new(Vector3(-5.0, -5.0, -40.0), Vector3(5.0, 5.0, 5.0))


func _ship_at(position: Vector3, velocity: Vector3) -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.position = position
	ship.velocity = velocity
	return ship


func _full_thrust() -> ShipInput:
	return ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO)


func test_head_on_hit_reverses_and_loses_some_speed() -> String:
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -39.2), Vector3(0.0, 0.0, -18.0))
	var impact: float = _box().contain(ship)
	if not is_equal_approx(impact, 18.0):
		return "impact speed %f, expected 18" % impact
	if ship.velocity.z <= 0.0:
		return "velocity into the wall was not reversed: %s" % ship.velocity
	var speed: float = ship.velocity.length()
	if speed >= 18.0 or speed <= 0.0:
		return "speed after a head-on hit is %f, expected between 0 and 18" % speed
	if not _box().holds(ship.position, ship.radius):
		return "ship ended outside the box at %s" % ship.position
	return ""


func test_glancing_hit_keeps_most_tangential_speed() -> String:
	var ship: ShipState = _ship_at(Vector3(-4.1, 0.0, -10.0), Vector3(-3.0, 0.0, -18.0))
	_box().contain(ship)
	if ship.velocity.z != -18.0:
		return "tangential speed changed from -18 to %f" % ship.velocity.z
	if ship.velocity.x <= 0.0:
		return "the component into the wall was not reflected: %s" % ship.velocity
	if ship.velocity.length() < 0.9 * Vector3(-3.0, 0.0, -18.0).length():
		return "a glancing hit lost too much speed: %f" % ship.velocity.length()
	return ""


func test_corner_hit_ends_inside_the_box() -> String:
	var box: BoxBounds = _box()
	var ship: ShipState = _ship_at(Vector3(-4.5, -4.6, -39.5), Vector3(-10.0, -12.0, -15.0))
	var impact: float = box.contain(ship)
	if not box.holds(ship.position, ship.radius):
		return "ship ended outside the box at %s" % ship.position
	if ship.velocity.x <= 0.0 or ship.velocity.y <= 0.0 or ship.velocity.z <= 0.0:
		return "not every wall reflected the ship: %s" % ship.velocity
	if not is_equal_approx(impact, Vector3(10.0, 12.0, 15.0).length()):
		return "corner impact %f is not the length of the into-wall components" % impact
	return ""


func test_far_overshoot_still_ends_inside() -> String:
	# A ship much faster than the box is wide must not be pushed out the other side.
	var box: BoxBounds = BoxBounds.new(Vector3(-2.0, -2.0, -2.0), Vector3(2.0, 2.0, 2.0))
	var ship: ShipState = _ship_at(Vector3(9.0, 0.0, 0.0), Vector3(300.0, 0.0, 0.0))
	ship.wall_restitution = 1.0
	box.contain(ship)
	if not box.holds(ship.position, ship.radius):
		return "ship ended outside the box at %s" % ship.position
	return ""


func test_slow_touch_deals_no_damage() -> String:
	var ship: ShipState = _ship_at(Vector3(0.0, 4.2, -10.0), Vector3(0.0, 3.0, -5.0))
	_box().contain(ship)
	if ship.velocity.y >= 0.0:
		return "a slow touch did not bounce"
	if ship.hull != ship.max_hull:
		return "a %f m/s touch cost hull: %f left" % [3.0, ship.hull]
	return ""


func test_fast_hit_deals_damage() -> String:
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -39.5), Vector3(0.0, 0.0, -20.0))
	_box().contain(ship)
	var lost: float = ship.max_hull - ship.hull
	if not is_equal_approx(lost, 20.0 * ship.wall_damage_per_speed):
		return "a 20 m/s hit cost %f hull, expected %f" % [lost, 20.0 * ship.wall_damage_per_speed]
	if lost > 0.25 * ship.max_hull:
		return "a hit at normal top speed is not minor: %f of %f hull" % [lost, ship.max_hull]
	return ""


func test_zero_restitution_still_bounces() -> String:
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -39.5), Vector3(0.0, 0.0, -20.0))
	ship.wall_restitution = 0.0
	_box().contain(ship)
	if ship.velocity.z <= 0.0:
		return "restitution 0 stopped the ship dead (FLT-3)"
	return ""


func test_moving_away_from_a_wall_is_not_a_hit() -> String:
	var ship: ShipState = _ship_at(Vector3(0.0, 0.0, -39.5), Vector3(0.0, 0.0, 6.0))
	var impact: float = _box().contain(ship)
	if impact != 0.0 or ship.velocity.z != 6.0 or ship.hull != ship.max_hull:
		return "a ship leaving the wall was treated as a hit"
	if not _box().holds(ship.position, ship.radius):
		return "ship was not moved back inside"
	return ""


func test_full_thrust_at_a_wall_never_leaves_or_stops() -> String:
	var box: BoxBounds = _box()
	var sim: Sim = Sim.new(7, 1, box)
	var bounces: int = 0
	var last_z_speed: float = 0.0
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = [_full_thrust()]
		sim.step(inputs)
		var ship: ShipState = sim.ships[0]
		if not box.holds(ship.position, ship.radius):
			return "tick %d: ship left the box at %s" % [tick, ship.position]
		if ship.velocity.length() <= 0.0:
			return "tick %d: ship stopped dead" % tick
		if last_z_speed < 0.0 and ship.velocity.z > 0.0:
			bounces += 1
		last_z_speed = ship.velocity.z
	if bounces == 0:
		return "the ship never reached the wall"
	if sim.ships[0].hull >= sim.ships[0].max_hull:
		return "a full-speed run into the wall dealt no damage"
	return ""


func _run_wall_flight(box: BoxBounds) -> Sim:
	var sim: Sim = Sim.new(11, 2, box)
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = [
			_full_thrust(), ShipInput.new(Vector3i(600, -300, -900), Vector3i(0, 200, 0))]
		sim.step(inputs)
	return sim


func test_same_inputs_give_the_same_hash() -> String:
	var first: int = _run_wall_flight(_box()).state_hash()
	if _run_wall_flight(_box()).state_hash() != first:
		return "two identical runs with walls gave different hashes"
	if _run_wall_flight(null).state_hash() == first:
		return "walls changed nothing in the hash"
	return ""


func test_hull_is_part_of_the_hash() -> String:
	var ship: ShipState = ShipState.new()
	var before: int = ship.state_hash()
	ship.hull -= 1.0
	if ship.state_hash() == before:
		return "losing hull did not change the hash"
	return ""


func test_no_box_leaves_behaviour_unchanged() -> String:
	var open: Sim = Sim.new(3, 1)
	var walled_far: Sim = Sim.new(3, 1, BoxBounds.new(Vector3(-1e6, -1e6, -1e6), Vector3(1e6, 1e6, 1e6)))
	for tick: int in 120:
		var inputs: Array[ShipInput] = [_full_thrust()]
		open.step(inputs)
		walled_far.step(inputs)
	if open.state_hash() != walled_far.state_hash():
		return "walls that are never touched changed the hash"
	if open.ships[0].hull != open.ships[0].max_hull:
		return "a ship in open space lost hull"
	return ""
