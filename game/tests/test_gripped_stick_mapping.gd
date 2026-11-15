extends RefCounted

## The gripped virtual stick and throttle scheme (issue #68, PLT-5, FLT-1,
## FLT-2, ARC-3): centre, every axis at full deflection, grip release, dead
## zones, clamping, left-handed mode and the afterburner, all without a headset.

const TILT_FULL: float = GrippedStickMapping.STICK_TILT_FULL_RAD
const TILT_DZ: float = GrippedStickMapping.STICK_TILT_DEAD_ZONE_RAD
const TWIST_FULL: float = GrippedStickMapping.STICK_TWIST_FULL_RAD
const TWIST_DZ: float = GrippedStickMapping.STICK_TWIST_DEAD_ZONE_RAD
const MOVE_FULL: float = GrippedStickMapping.THROTTLE_FULL_M
const MOVE_DZ: float = GrippedStickMapping.THROTTLE_DEAD_ZONE_M
const CENTRE: Transform3D = Transform3D.IDENTITY


## Stick poses. Tilting the top ahead is a negative rotation about x, to the
## right a negative rotation about z, and a clockwise twist seen from above a
## negative rotation about y.
static func _tilt_ahead(angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -angle), Vector3.ZERO)


static func _tilt_right(angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, -angle), Vector3.ZERO)


static func _twist_clockwise(angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -angle), Vector3.ZERO)


static func _moved(offset: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, offset)


## Right-handed: left is the throttle, right the stick; both grips held.
static func _axes(m: GrippedStickMapping, throttle: Transform3D, stick: Transform3D,
		throttle_grip: float = 1.0, stick_grip: float = 1.0) -> Dictionary:
	return m.axes(throttle, stick, throttle_grip, stick_grip)


static func _check_axes(got: Dictionary, want: Dictionary, label: String) -> String:
	for name: String in GrippedStickMapping.AXES:
		var expected: float = float(want.get(name, 0.0))
		if absf(float(got[name]) - expected) > 1e-4:
			return "%s: %s is %s, want %s (all: %s)" % [label, name, got[name], expected, got]
	return ""


func test_centre_pose_gives_idle() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var got: ShipInput = m.map_controls(CENTRE, CENTRE, 1.0, 1.0)
	if got.thrust_q != Vector3i.ZERO or got.turn_q != Vector3i.ZERO or got.afterburner:
		return "centre gave thrust %s turn %s afterburner %s" % [got.thrust_q, got.turn_q, got.afterburner]
	return ""


func test_each_axis_at_full_deflection() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var cases: Array[Array] = [
		["push ahead", _axes(m, _moved(Vector3(0, 0, -MOVE_FULL)), CENTRE), {"forward": 1.0}],
		["pull back", _axes(m, _moved(Vector3(0, 0, MOVE_FULL)), CENTRE), {"forward": -1.0}],
		["move right", _axes(m, _moved(Vector3(MOVE_FULL, 0, 0)), CENTRE), {"strafe": 1.0}],
		["move left", _axes(m, _moved(Vector3(-MOVE_FULL, 0, 0)), CENTRE), {"strafe": -1.0}],
		["move up", _axes(m, _moved(Vector3(0, MOVE_FULL, 0)), CENTRE), {"lift": 1.0}],
		["move down", _axes(m, _moved(Vector3(0, -MOVE_FULL, 0)), CENTRE), {"lift": -1.0}],
		["stick ahead", _axes(m, CENTRE, _tilt_ahead(TILT_FULL)), {"pitch": -1.0}],
		["stick back", _axes(m, CENTRE, _tilt_ahead(-TILT_FULL)), {"pitch": 1.0}],
		["stick right", _axes(m, CENTRE, _tilt_right(TILT_FULL)), {"roll": 1.0}],
		["stick left", _axes(m, CENTRE, _tilt_right(-TILT_FULL)), {"roll": -1.0}],
		["twist right", _axes(m, CENTRE, _twist_clockwise(TWIST_FULL)), {"yaw": 1.0}],
		["twist left", _axes(m, CENTRE, _twist_clockwise(-TWIST_FULL)), {"yaw": -1.0}],
	]
	for c: Array in cases:
		var problem: String = _check_axes(c[1], c[2], c[0])
		if problem != "":
			return problem
	return ""


func test_full_deflection_reaches_ship_input_at_full_rate() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var got: ShipInput = m.map_controls(
		_moved(Vector3(0, 0, -MOVE_FULL)), _tilt_ahead(-TILT_FULL), 1.0, 1.0)
	var want: ShipInput = ShipInput.from_floats(
		Vector3(0, 0, -1), Vector3(GrippedStickMapping.MAX_PITCH_RATE, 0, 0))
	if got.thrust_q != want.thrust_q or got.turn_q != want.turn_q:
		return "got thrust %s turn %s, want thrust %s turn %s" % [
			got.thrust_q, got.turn_q, want.thrust_q, want.turn_q]
	return ""


func test_turn_directions_match_the_ship() -> String:
	# The signs are only right if ShipState turns the way the names say.
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var checks: Array[Array] = [
		["stick back raises the nose", _tilt_ahead(-TILT_FULL), Vector3.FORWARD, Vector3.UP],
		["twist right turns the nose right", _twist_clockwise(TWIST_FULL), Vector3.FORWARD, Vector3.RIGHT],
		["stick right lowers the right wing", _tilt_right(TILT_FULL), Vector3.RIGHT, Vector3.DOWN],
	]
	for c: Array in checks:
		var ship: ShipState = ShipState.new()
		var input: ShipInput = m.map_controls(CENTRE, c[1], 1.0, 1.0)
		ship.step(input.thrust(), input.turn())
		var axis: Vector3 = ship.orientation * (c[2] as Vector3)
		if axis.dot(c[3]) <= 0.0:
			return "%s: axis is now %s" % [c[0], axis]
	return ""


func test_releasing_the_grip_gives_idle() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var throttle: Transform3D = _moved(Vector3(MOVE_FULL, MOVE_FULL, -MOVE_FULL))
	var stick: Transform3D = _tilt_ahead(TILT_FULL) * _twist_clockwise(TWIST_FULL)
	var below: float = GrippedStickMapping.GRIP_HOLD_THRESHOLD - 0.01
	var none: Dictionary = {}
	var cases: Array[Array] = [
		["both released", _axes(m, throttle, stick, 0.0, 0.0), none],
		["grips just under the threshold", _axes(m, throttle, stick, below, below), none],
		["stick released", _axes(m, throttle, stick, 1.0, 0.0),
			{"strafe": 1.0, "lift": 1.0, "forward": 1.0}],
		["throttle released", _axes(m, throttle, _tilt_right(TILT_FULL), 0.0, 1.0), {"roll": 1.0}],
	]
	for c: Array in cases:
		var problem: String = _check_axes(c[1], c[2], c[0])
		if problem != "":
			return problem
	var pressed: Dictionary = {GrippedStickMapping.AFTERBURNER_BUTTON: true}
	if m.map_controls(throttle, stick, 0.0, 0.0, pressed).afterburner:
		return "afterburner fired with the throttle grip released"
	return ""


func test_dead_zones() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var inside: Array[Array] = [
		["throttle inside", _axes(m, _moved(Vector3(MOVE_DZ, -MOVE_DZ, -MOVE_DZ) * 0.9), CENTRE)],
		["throttle on the edge", _axes(m, _moved(Vector3(0, 0, -MOVE_DZ)), CENTRE)],
		["tilt inside", _axes(m, CENTRE, _tilt_ahead(TILT_DZ * 0.9))],
		["tilt on the edge", _axes(m, CENTRE, _tilt_right(TILT_DZ))],
		["twist inside", _axes(m, CENTRE, _twist_clockwise(-TWIST_DZ * 0.9))],
	]
	for c: Array in inside:
		var problem: String = _check_axes(c[1], {}, c[0])
		if problem != "":
			return problem
	# Half way between the dead zone edge and full deflection gives one half.
	var half_move: float = (MOVE_DZ + MOVE_FULL) / 2.0
	var half_tilt: float = (TILT_DZ + TILT_FULL) / 2.0
	var half_twist: float = (TWIST_DZ + TWIST_FULL) / 2.0
	var halves: Array[Array] = [
		["throttle half", _axes(m, _moved(Vector3(0, 0, -half_move)), CENTRE), {"forward": 0.5}],
		["tilt half", _axes(m, CENTRE, _tilt_right(half_tilt)), {"roll": 0.5}],
		["twist half", _axes(m, CENTRE, _twist_clockwise(half_twist)), {"yaw": 0.5}],
	]
	for c: Array in halves:
		var problem: String = _check_axes(c[1], c[2], c[0])
		if problem != "":
			return problem
	return ""


func test_output_is_clamped_beyond_full_deflection() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var far: float = MOVE_FULL * 5.0
	var throttle: Transform3D = _moved(Vector3(-far, far, far))
	var stick: Transform3D = _tilt_ahead(TILT_FULL * 2.5) * _twist_clockwise(-TWIST_FULL * 3.0)
	var problem: String = _check_axes(_axes(m, throttle, stick),
		{"strafe": -1.0, "lift": 1.0, "forward": -1.0, "pitch": -1.0, "yaw": -1.0}, "far")
	if problem != "":
		return problem
	var input: ShipInput = m.map_controls(throttle, stick, 1.0, 1.0)
	for i: int in 3:
		if absi(input.thrust_q[i]) > ShipInput.SCALE:
			return "thrust %s exceeds full scale" % input.thrust_q
	return ""


func test_tilt_and_twist_are_independent() -> String:
	# A pilot tilting the stick should not also yaw, and a twist should not pitch.
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var stick: Transform3D = _tilt_ahead(TILT_FULL) * _twist_clockwise(TWIST_FULL)
	return _check_axes(_axes(m, CENTRE, stick), {"pitch": -1.0, "yaw": 1.0}, "tilt then twist")


func test_left_handed_swaps_stick_and_throttle() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	m.left_handed = true
	var throttle: Transform3D = _moved(Vector3(0, 0, -MOVE_FULL))
	var stick: Transform3D = _tilt_right(TILT_FULL)
	# Right-hand pose now drives the throttle, left-hand pose the stick.
	var problem: String = _check_axes(m.axes(stick, throttle, 1.0, 1.0),
		{"forward": 1.0, "roll": 1.0}, "left-handed")
	if problem != "":
		return problem
	# The grips swap with the hands: releasing the right grip drops the throttle.
	problem = _check_axes(m.axes(stick, throttle, 1.0, 0.0), {"roll": 1.0}, "left-handed, right released")
	if problem != "":
		return problem
	# The same poses in the right-handed hands mean something else entirely.
	return _check_axes(GrippedStickMapping.new().axes(stick, throttle, 1.0, 1.0), {}, "right-handed")


func test_afterburner_button() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	var on: Dictionary = {GrippedStickMapping.AFTERBURNER_BUTTON: true}
	if not m.map_controls(CENTRE, CENTRE, 1.0, 0.0, on).afterburner:
		return "afterburner button with the throttle held did not fire"
	if m.map_controls(CENTRE, CENTRE, 1.0, 1.0).afterburner:
		return "afterburner fired with no buttons"
	var other: Dictionary = {GrippedStickMapping.AFTERBURNER_BUTTON_LEFT_HANDED: true}
	if m.map_controls(CENTRE, CENTRE, 1.0, 1.0, other).afterburner:
		return "the stick hand's button fired the afterburner"
	m.left_handed = true
	if not m.map_controls(CENTRE, CENTRE, 0.0, 1.0, other).afterburner:
		return "left-handed: the right hand's button did not fire"
	if m.map_controls(CENTRE, CENTRE, 1.0, 1.0, on).afterburner:
		return "left-handed: the left hand's button still fired"
	return ""


func test_invert_pitch() -> String:
	var m: GrippedStickMapping = GrippedStickMapping.new()
	m.invert_pitch = true
	return _check_axes(_axes(m, CENTRE, _tilt_ahead(TILT_FULL)), {"pitch": 1.0}, "inverted")
