extends RefCounted

## Boost on A and primary fire on the right trigger (issue #149, decision
## record 0004, PLT-5, FLT-2, CMB-1): boost alone moves the ship, a stick
## pulled back still wins, the triggers fire instead of lifting, and
## left-handed mode mirrors both.

const Z: Vector2 = Vector2.ZERO
const BOOST: Dictionary = {"right_button_lower": true}


func _default_file() -> ThumbstickMapping:
	return ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE)


func test_a_from_a_standstill_boosts_at_full_forward_thrust() -> String:
	var input: ShipInput = _default_file().map_controls(Z, Z, 0.0, 0.0, 0.0, 0.0, BOOST)
	if not input.afterburner:
		return "A should hold the afterburner"
	if input.thrust_q != Vector3i(0, 0, -ShipInput.SCALE):
		return "A alone should give forward thrust 1, got %s" % input.thrust_q
	return ""


func test_stick_forward_part_way_still_boosts_at_full() -> String:
	var input: ShipInput = _default_file().map_controls(Vector2(0, 0.4), Z, 0.0, 0.0, 0.0, 0.0, BOOST)
	if input.thrust_q.z != -ShipInput.SCALE:
		return "boost should raise part forward to full, got %d" % input.thrust_q.z
	return ""


func test_stick_pulled_back_wins_over_boost() -> String:
	var m: ThumbstickMapping = _default_file()
	var back: Vector2 = Vector2(0, -1)
	var plain: ShipInput = m.map_controls(back, Z, 0.0, 0.0, 0.0, 0.0)
	var boosting: ShipInput = m.map_controls(back, Z, 0.0, 0.0, 0.0, 0.0, BOOST)
	if boosting.thrust_q != plain.thrust_q:
		return "pulling back under boost should keep the stick's thrust %s, got %s" % [
			plain.thrust_q, boosting.thrust_q]
	if not boosting.afterburner:
		return "the afterburner should stay on while pulling back"
	return ""


func test_right_trigger_fires_primary_from_half_pull() -> String:
	var m: ThumbstickMapping = _default_file()
	if m.map_controls(Z, Z, 0.0, 0.4, 0.0, 0.0).fire_primary:
		return "a trigger below half pull should not fire"
	var fired: ShipInput = m.map_controls(Z, Z, 0.0, 0.5, 0.0, 0.0)
	if not fired.fire_primary:
		return "the right trigger at half pull should fire"
	if fired.thrust_q != Vector3i.ZERO or fired.turn_q != Vector3i.ZERO or fired.afterburner:
		return "firing should not move the ship"
	return ""


func test_left_trigger_is_unbound_until_secondaries_exist() -> String:
	var input: ShipInput = _default_file().map_controls(Z, Z, 1.0, 0.0, 0.0, 0.0)
	if input.fire_primary or input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO:
		return "the left trigger should do nothing yet"
	return ""


func test_left_handed_mirrors_boost_and_fire() -> String:
	var m: ThumbstickMapping = _default_file()
	m.left_handed = true
	if not m.map_controls(Z, Z, 1.0, 0.0, 0.0, 0.0).fire_primary:
		return "left-handed: the left trigger should fire"
	if m.map_controls(Z, Z, 0.0, 1.0, 0.0, 0.0).fire_primary:
		return "left-handed: the right trigger should not fire"
	var boost: ShipInput = m.map_controls(Z, Z, 0.0, 0.0, 0.0, 0.0, {"left_button_lower": true})
	if not boost.afterburner or boost.thrust_q.z != -ShipInput.SCALE:
		return "left-handed: X should boost forward, got %s" % boost.thrust_q
	var up: ShipInput = m.map_controls(Z, Z, 0.0, 0.0, 0.0, 0.0, {"left_button_upper": true})
	var down: ShipInput = m.map_controls(Z, Z, 0.0, 0.0, 0.0, 0.0, {"right_button_lower": true})
	if up.thrust_q != Vector3i(0, ShipInput.SCALE, 0) or down.thrust_q != Vector3i(0, -ShipInput.SCALE, 0):
		return "left-handed: Y should lift up and A down, got %s / %s" % [up.thrust_q, down.thrust_q]
	return ""


func test_fire_primary_can_be_remapped() -> String:
	var m: ThumbstickMapping = ThumbstickMapping.from_json("{\"fire_primary\": {\"left_grip\": 1.0}}")
	if m.error != "":
		return "fire_primary rejected: " + m.error
	if not m.map_controls(Z, Z, 0.0, 0.0, 1.0, 0.0).fire_primary:
		return "the remapped grip should fire"
	if m.map_controls(Z, Z, 0.0, 1.0, 0.0, 0.0).fire_primary:
		return "the right trigger should no longer fire"
	return ""
