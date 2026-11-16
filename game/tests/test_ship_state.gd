extends RefCounted

const ShipStateScript: GDScript = preload("res://core/ship_state.gd")

const FORWARD: Vector3 = Vector3(0.0, 0.0, -1.0)


func _fly(ticks: int, thrust: Vector3, turn: Vector3) -> Object:
	var ship: Object = ShipStateScript.new()
	for i: int in ticks:
		ship.step(thrust, turn)
	return ship


func test_same_inputs_give_same_hash() -> String:
	var a: Object = _fly(600, Vector3(0.3, -0.2, -1.0), Vector3(0.4, -0.7, 0.2))
	var b: Object = _fly(600, Vector3(0.3, -0.2, -1.0), Vector3(0.4, -0.7, 0.2))
	if a.state_hash() != b.state_hash():
		return "identical inputs produced different state hashes"
	return ""


func test_different_inputs_give_different_hash() -> String:
	var a: Object = _fly(60, FORWARD, Vector3.ZERO)
	var b: Object = _fly(60, -FORWARD, Vector3.ZERO)
	if a.state_hash() == b.state_hash():
		return "different inputs produced the same state hash"
	return ""


func test_speed_never_exceeds_max() -> String:
	var ship: Object = ShipStateScript.new()
	for i: int in 600:
		ship.step(Vector3(1.0, 1.0, -1.0), Vector3.ZERO)
		if ship.velocity.length() > ship.max_speed + 0.001:
			return "speed %f exceeded max %f at tick %d" % [ship.velocity.length(), ship.max_speed, i]
	return ""


func test_forward_thrust_moves_along_negative_z() -> String:
	var ship: Object = _fly(60, FORWARD, Vector3.ZERO)
	if ship.position.z >= 0.0:
		return "expected negative z after forward thrust, got %f" % ship.position.z
	if absf(ship.position.x) > 0.001 or absf(ship.position.y) > 0.001:
		return "forward thrust drifted sideways"
	return ""


func test_ship_comes_to_rest_without_input() -> String:
	var ship: Object = _fly(120, FORWARD, Vector3.ZERO)
	for i: int in 600:
		ship.step(Vector3.ZERO, Vector3.ZERO)
	if ship.velocity.length() > 0.01:
		return "ship still moving at %f after 10 seconds idle" % ship.velocity.length()
	return ""


func test_orientation_stays_orthonormal() -> String:
	var ship: Object = _fly(3600, Vector3.ZERO, Vector3(1.3, -0.9, 0.7))
	var basis: Basis = ship.orientation
	if absf(basis.determinant() - 1.0) > 0.001:
		return "orientation determinant drifted to %f" % basis.determinant()
	return ""


## Hull and shield were once appended untagged, so a damaged hull and an
## equally damaged shield hashed alike and a desync between them went unseen.
func test_damaged_hull_and_damaged_shield_hash_differently() -> String:
	var hull_hit: ShipState = ShipState.new()
	hull_hit.hull = 40.0
	var shield_hit: ShipState = ShipState.new()
	shield_hit.shield = 40.0
	if hull_hit.state_hash() == shield_hit.state_hash():
		return "hull 40 with a full shield hashed like a full hull with shield 40"
	return ""


func test_swapped_hull_and_shield_hash_differently() -> String:
	var a: ShipState = ShipState.new()
	a.hull = 40.0
	a.shield = 30.0
	var b: ShipState = ShipState.new()
	b.hull = 30.0
	b.shield = 40.0
	if a.state_hash() == b.state_hash():
		return "hull 40 / shield 30 hashed like hull 30 / shield 40"
	return ""


## A full ship leaves hull and shield out, so replays that never take damage
## keep the hashes recorded before the tags were added.
func test_full_ship_keeps_the_untagged_hash() -> String:
	var ship: ShipState = _fly(120, Vector3(0.3, -0.2, -1.0), Vector3(0.4, -0.7, 0.2))
	var old: int = hash([ship.position, ship.velocity, ship.orientation, ship.energy,
		ship.afterburner_locked])
	if ship.state_hash() != old:
		return "a full hull and shield changed the hash"
	return ""
