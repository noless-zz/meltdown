extends RefCounted

## The thumbsticks-only scheme (issues #42 and #64, PLT-5, FLT-1, FLT-2):
## every axis, the afterburner button, the dead zone, left-handed mode,
## remapping and invert pitch, all without a headset.

const DZ: float = ThumbstickMapping.STICK_DEAD_ZONE


## Builds the expected input the same way the mapping must: through
## `from_floats`, so rounding matches.
func _expect(thrust: Vector3, turn: Vector3) -> ShipInput:
	return ShipInput.from_floats(thrust, turn)


func _diff(got: ShipInput, want: ShipInput, label: String) -> String:
	if got.thrust_q != want.thrust_q or got.turn_q != want.turn_q \
			or got.afterburner != want.afterburner:
		return "%s: got thrust %s turn %s afterburner %s, want thrust %s turn %s afterburner %s" % [
			label, got.thrust_q, got.turn_q, got.afterburner,
			want.thrust_q, want.turn_q, want.afterburner]
	return ""


func _map(mapping: ThumbstickMapping, ls: Vector2, rs: Vector2,
		lt: float = 0.0, rt: float = 0.0, lg: float = 0.0, rg: float = 0.0,
		buttons: Dictionary = {}) -> ShipInput:
	return mapping.map_controls(ls, rs, lt, rt, lg, rg, buttons)


func test_all_zero_controls_give_zero_input() -> String:
	var got: ShipInput = _map(ThumbstickMapping.new(), Vector2.ZERO, Vector2.ZERO)
	return _diff(got, ShipInput.new(), "all zero")


func test_each_axis_at_full_deflection() -> String:
	var m: ThumbstickMapping = ThumbstickMapping.new()
	var pitch: float = ThumbstickMapping.MAX_PITCH_RATE
	var yaw: float = ThumbstickMapping.MAX_YAW_RATE
	var roll: float = ThumbstickMapping.MAX_ROLL_RATE
	var cases: Array[Array] = [
		["strafe right", _map(m, Vector2(1, 0), Vector2.ZERO), _expect(Vector3(1, 0, 0), Vector3.ZERO)],
		["strafe left", _map(m, Vector2(-1, 0), Vector2.ZERO), _expect(Vector3(-1, 0, 0), Vector3.ZERO)],
		["forward", _map(m, Vector2(0, 1), Vector2.ZERO), _expect(Vector3(0, 0, -1), Vector3.ZERO)],
		["back", _map(m, Vector2(0, -1), Vector2.ZERO), _expect(Vector3(0, 0, 1), Vector3.ZERO)],
		["yaw right", _map(m, Vector2.ZERO, Vector2(1, 0)), _expect(Vector3.ZERO, Vector3(0, -yaw, 0))],
		["yaw left", _map(m, Vector2.ZERO, Vector2(-1, 0)), _expect(Vector3.ZERO, Vector3(0, yaw, 0))],
		["pitch up", _map(m, Vector2.ZERO, Vector2(0, 1)), _expect(Vector3.ZERO, Vector3(pitch, 0, 0))],
		["pitch down", _map(m, Vector2.ZERO, Vector2(0, -1)), _expect(Vector3.ZERO, Vector3(-pitch, 0, 0))],
		["down", _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, {"left_button_lower": true}),
			_expect(Vector3(0, -1, 0), Vector3.ZERO)],
		["up", _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, {"right_button_upper": true}),
			_expect(Vector3(0, 1, 0), Vector3.ZERO)],
		["roll left", _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 1.0), _expect(Vector3.ZERO, Vector3(0, 0, roll))],
		["roll right", _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 1.0), _expect(Vector3.ZERO, Vector3(0, 0, -roll))],
		["both lift buttons cancel", _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
			{"left_button_lower": true, "right_button_upper": true}), ShipInput.new()],
	]
	for c: Array in cases:
		var problem: String = _diff(c[1], c[2], c[0])
		if problem != "":
			return problem
	return ""


func test_turn_directions_match_the_ship() -> String:
	# The signs above are only right if ShipState turns the way the names say.
	var m: ThumbstickMapping = ThumbstickMapping.new()
	var checks: Array[Array] = [
		["pitch up raises the nose", _map(m, Vector2.ZERO, Vector2(0, 1)), Vector3.FORWARD, Vector3.UP],
		["yaw right turns the nose right", _map(m, Vector2.ZERO, Vector2(1, 0)), Vector3.FORWARD, Vector3.RIGHT],
		["roll right lowers the right wing", _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 1.0), Vector3.RIGHT, Vector3.DOWN],
	]
	for c: Array in checks:
		var ship: ShipState = ShipState.new()
		var input: ShipInput = c[1]
		ship.step(input.thrust(), input.turn())
		var axis: Vector3 = ship.orientation * (c[2] as Vector3)
		if axis.dot(c[3]) <= 0.0:
			return "%s: axis is now %s" % [c[0], axis]
	return ""


func test_dead_zone_edges() -> String:
	var just_inside: Vector2 = Vector2(DZ - 0.001, 0.0)
	var on_edge: Vector2 = Vector2(0.0, DZ)
	var diagonal_inside: Vector2 = Vector2(1, 1).normalized() * (DZ * 0.99)
	for stick: Vector2 in [just_inside, on_edge, diagonal_inside]:
		if ThumbstickMapping.apply_dead_zone(stick) != Vector2.ZERO:
			return "%s inside the dead zone gave %s" % [stick, ThumbstickMapping.apply_dead_zone(stick)]
	var m: ThumbstickMapping = ThumbstickMapping.new()
	var problem: String = _diff(_map(m, just_inside, on_edge), ShipInput.new(), "drift")
	if problem != "":
		return problem
	var outside: Vector2 = ThumbstickMapping.apply_dead_zone(Vector2(DZ + 0.01, 0.0))
	if outside.x <= 0.0 or outside.x > 0.02 or outside.y != 0.0:
		return "just outside the dead zone should be small and positive, got %s" % outside
	var halfway: Vector2 = ThumbstickMapping.apply_dead_zone(Vector2(0.0, -(DZ + 1.0) / 2.0))
	if not is_equal_approx(halfway.y, -0.5) or halfway.x != 0.0:
		return "halfway between edge and full should give -0.5, got %s" % halfway
	return ""


func test_full_deflection_gives_one() -> String:
	for stick: Vector2 in [Vector2(1, 0), Vector2(0, -1), Vector2(1, 1).normalized(), Vector2(1, 1)]:
		var out: Vector2 = ThumbstickMapping.apply_dead_zone(stick)
		if not is_equal_approx(out.length(), 1.0):
			return "%s gave length %f" % [stick, out.length()]
		if not out.normalized().is_equal_approx(stick.normalized()):
			return "%s changed direction to %s" % [stick, out]
	return ""


func test_left_handed_mirrors_the_hands() -> String:
	var right_handed: ThumbstickMapping = ThumbstickMapping.new()
	var left_handed: ThumbstickMapping = ThumbstickMapping.new()
	left_handed.left_handed = true
	var ls: Vector2 = Vector2(0.4, 0.8)
	var rs: Vector2 = Vector2(-0.7, 0.3)
	var want: ShipInput = right_handed.map_controls(ls, rs, 0.2, 0.9, 0.6, 0.1)
	var got: ShipInput = left_handed.map_controls(rs, ls, 0.9, 0.2, 0.1, 0.6)
	var problem: String = _diff(got, want, "mirrored")
	if problem != "":
		return problem
	if want.thrust_q == Vector3i.ZERO or want.turn_q == Vector3i.ZERO:
		return "the sample controls should move every group of axes"
	# Same values, not mirrored: the hands must really have swapped roles.
	var unmirrored: ShipInput = left_handed.map_controls(ls, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0)
	return _diff(unmirrored, right_handed.map_controls(Vector2.ZERO, ls, 0.0, 0.0, 0.0, 0.0),
		"left stick turns in left-handed mode")


func test_left_handed_swaps_buttons() -> String:
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout["lift"] = {"right_stick_click": 1.0}
	var m: ThumbstickMapping = ThumbstickMapping.new(layout)
	m.left_handed = true
	var got: ShipInput = _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
		{"left_stick_click": true})
	return _diff(got, _expect(Vector3(0, 1, 0), Vector3.ZERO), "swapped button")


func test_remapped_axis() -> String:
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout["yaw"] = {"left_stick_x": 1.0}
	layout["strafe"] = {"right_stick_x": 1.0}
	var m: ThumbstickMapping = ThumbstickMapping.new(layout)
	var got: ShipInput = _map(m, Vector2(1, 0), Vector2.ZERO)
	var problem: String = _diff(got,
		_expect(Vector3.ZERO, Vector3(0, -ThumbstickMapping.MAX_YAW_RATE, 0)), "yaw on left stick")
	if problem != "":
		return problem
	problem = _diff(_map(m, Vector2.ZERO, Vector2(-1, 0)), _expect(Vector3(-1, 0, 0), Vector3.ZERO),
		"strafe on right stick")
	if problem != "":
		return problem
	# A button bound to an axis drives it; the default layout is untouched.
	layout["forward"] = {"right_stick_click": 1.0}
	problem = _diff(_map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, {"right_stick_click": true}),
		_expect(Vector3(0, 0, -1), Vector3.ZERO), "forward on a button")
	if problem != "":
		return problem
	if ThumbstickMapping.default_layout()["yaw"] != {"right_stick_x": 1.0}:
		return "editing a layout changed the default"
	return ""


func test_invert_pitch() -> String:
	var m: ThumbstickMapping = ThumbstickMapping.new()
	m.invert_pitch = true
	var got: ShipInput = _map(m, Vector2.ZERO, Vector2(0, 1))
	var problem: String = _diff(got,
		_expect(Vector3.ZERO, Vector3(-ThumbstickMapping.MAX_PITCH_RATE, 0, 0)), "inverted pitch up")
	if problem != "":
		return problem
	# Only pitch flips.
	var plain: ThumbstickMapping = ThumbstickMapping.new()
	var ls: Vector2 = Vector2(0.5, -0.6)
	var rs: Vector2 = Vector2(0.8, 0.0)
	return _diff(m.map_controls(ls, rs, 0.3, 0.0, 0.7, 0.0),
		plain.map_controls(ls, rs, 0.3, 0.0, 0.7, 0.0), "other axes")


func test_a_holds_the_afterburner() -> String:
	var m: ThumbstickMapping = ThumbstickMapping.new()
	var held: ShipInput = _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
		{"right_button_lower": true})
	# Boost alone flies forward at full thrust (#149).
	var problem: String = _diff(held, ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO, true),
		"pressed")
	if problem != "":
		return problem
	problem = _diff(_map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
		{"right_button_lower": false}), ShipInput.new(), "released")
	if problem != "":
		return problem
	# The stick clicks and Y do nothing in the flight layout.
	problem = _diff(_map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
		{"right_stick_click": true, "left_stick_click": true, "left_button_upper": true}),
		ShipInput.new(), "other buttons")
	if problem != "":
		return problem
	# Boosting while flying keeps every other axis as it was.
	var ls: Vector2 = Vector2(0.3, 0.6)
	var rs: Vector2 = Vector2(-0.5, 0.4)
	var flying: ShipInput = m.map_controls(ls, rs, 0.2, 0.7, 0.0, 0.4)
	var boosting: ShipInput = m.map_controls(ls, rs, 0.2, 0.7, 0.0, 0.4, {"right_button_lower": true})
	if boosting.turn_q != flying.turn_q or boosting.thrust_q.x != flying.thrust_q.x \
			or boosting.thrust_q.y != flying.thrust_q.y:
		return "the afterburner changed an axis other than forward"
	if boosting.thrust_q.z != -ShipInput.SCALE:
		return "boosting should give full forward thrust, got %d" % boosting.thrust_q.z
	if flying.afterburner or not boosting.afterburner:
		return "afterburner should follow A while flying"
	return ""


func test_afterburner_defaults_to_released() -> String:
	# Callers written before the afterburner existed pass no buttons at all.
	var m: ThumbstickMapping = ThumbstickMapping.new()
	if m.map_controls(Vector2(0, 1), Vector2.ZERO, 0.0, 0.0, 0.0, 0.0).afterburner:
		return "no buttons argument should mean no afterburner"
	if _map(m, Vector2.ZERO, Vector2.ZERO).afterburner:
		return "an empty buttons dictionary should mean no afterburner"
	if ThumbstickMapping.default_layout()["afterburner"] != {"right_button_lower": 1.0}:
		return "the default afterburner control should be A (right lower button)"
	return ""


func test_left_handed_moves_the_afterburner_to_x() -> String:
	var m: ThumbstickMapping = ThumbstickMapping.new()
	m.left_handed = true
	if not _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
			{"left_button_lower": true}).afterburner:
		return "X should boost in left-handed mode"
	if _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
			{"right_button_lower": true}).afterburner:
		return "A should not boost in left-handed mode"
	return ""


func test_custom_afterburner_control() -> String:
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout["afterburner"] = {"left_stick_click": 1.0}
	var m: ThumbstickMapping = ThumbstickMapping.new(layout)
	if not _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
			{"left_stick_click": true}).afterburner:
		return "the remapped button should boost"
	if _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0,
			{"right_button_lower": true}).afterburner:
		return "the old control should no longer boost"
	# An analogue control works too, from half pull.
	layout["afterburner"] = {"left_grip": 1.0}
	if _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.4).afterburner:
		return "a grip below half pull should not boost"
	if not _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.5).afterburner:
		return "a grip at half pull should boost"
	# A layout without the action never boosts.
	layout.erase("afterburner")
	if _map(m, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 1.0, 0.0, {"right_button_lower": true}).afterburner:
		return "a layout without an afterburner entry should never boost"
	if ThumbstickMapping.default_layout()["afterburner"] != {"right_button_lower": 1.0}:
		return "editing a layout changed the default"
	return ""
