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
