extends RefCounted

## The view guard keeps the cockpit window in front of the eyes (#651, CMF-1,
## CMF-8): a head lost from the window for longer than the cockpit file allows,
## or a tracking regain, re-places the frame around the head; a glance aside
## or an ordinary lean never does.

const FRAME: float = 1.0 / 90.0
const SEATED_HEAD: Vector3 = Vector3(0.0, 1.2, 0.0)


static func _spec(number: int) -> CockpitSpec:
	return CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))


## A head at `at` looking `yaw` degrees right and `pitch` degrees up.
static func _head(yaw: float, pitch: float = 0.0, at: Vector3 = SEATED_HEAD) -> Transform3D:
	var basis: Basis = Basis(Vector3.UP, -deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	return Transform3D(basis, at)


## Runs `guard` for `seconds` at 90 Hz from `start_s` with `head` and the
## recentre point at the seated head; returns the frame point at the end.
static func _run(guard: ViewGuard, head: Transform3D, spec: CockpitSpec, start_s: float,
		seconds: float, tracked: bool = true) -> Transform3D:
	var point: Transform3D = Transform3D(Basis(), SEATED_HEAD)
	var at: Transform3D = point
	var frames: int = int(ceil(seconds / FRAME))
	for i: int in frames + 1:
		at = guard.update(point, head, tracked, spec, start_s + i * FRAME)
	return at


func test_every_cockpit_file_has_guard_values_in_range() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = _spec(number)
		if spec.error != "":
			return "preset %d: %s" % [number, spec.error]
		if spec.guard_after_s < 1.0:
			return "preset %d re-places after %.2f s: a glance aside would move the frame" % [number, spec.guard_after_s]
		if spec.guard_distance_m <= HeadRecentre.HEAD_REACH:
			return "preset %d: a seated lean of %.2f m would count as lost" % [number, HeadRecentre.HEAD_REACH]
	return ""


func test_window_angles_match_the_frames_directions() -> String:
	var frame: Transform3D = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.2, 1.0, -0.1))
	for angles: Vector2 in [Vector2(0, 0), Vector2(30, 0), Vector2(-50, 20), Vector2(80, -60), Vector2(150, 10)]:
		var look: Vector3 = frame.basis * CockpitFrame.direction(angles.x, angles.y)
		var head: Transform3D = Transform3D(Basis.looking_at(look, Vector3.UP), frame.origin)
		var got: Vector2 = ViewGuard.window_angles(frame, head)
		if not got.is_equal_approx(angles) and got.distance_to(angles) > 0.01:
			return "looking at %s read as %s" % [angles, got]
	return ""


func test_looking_anywhere_in_the_window_never_moves_the_frame() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = _spec(number)
		var guard: ViewGuard = ViewGuard.new()
		var start: Transform3D = Transform3D(Basis(), SEATED_HEAD)
		var t: float = 0.0
		for yaw: float in [-spec.window_half_angle_h_deg, 0.0, spec.window_half_angle_h_deg]:
			for pitch: float in [-spec.window_half_angle_v_deg, 0.0, spec.window_half_angle_v_deg]:
				var at: Transform3D = _run(guard, _head(yaw, pitch), spec, t, 20.0)
				t += 20.0
				if not at.is_equal_approx(start) or guard.replacements != 0:
					return "preset %d: looking at (%s, %s) for 20 s moved the frame" % [number, yaw, pitch]
	return ""


func test_a_seated_lean_never_moves_the_frame() -> String:
	var spec: CockpitSpec = _spec(1)
	var guard: ViewGuard = ViewGuard.new()
	var lean: Vector3 = SEATED_HEAD + Vector3(0.25, -0.1, -HeadRecentre.HEAD_REACH * 0.7)
	_run(guard, _head(10.0, -15.0, lean), spec, 0.0, 30.0)
	return "" if guard.replacements == 0 else "a seated lean re-placed the frame"


func test_a_glance_past_the_margin_shorter_than_the_wait_does_nothing() -> String:
	var spec: CockpitSpec = _spec(1)
	var guard: ViewGuard = ViewGuard.new()
	var away: Transform3D = _head(spec.window_half_angle_h_deg + spec.guard_margin_deg + 20.0)
	var t: float = 0.0
	for glance: int in 5:
		_run(guard, away, spec, t, spec.guard_after_s * 0.8)
		t += spec.guard_after_s
		_run(guard, _head(0.0), spec, t, 0.5)
		t += 1.0
	return "" if guard.replacements == 0 else "five short glances re-placed the frame"


func test_a_head_lost_from_the_window_gets_the_frame_back_in_front() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = _spec(number)
		var guard: ViewGuard = ViewGuard.new()
		var head: Transform3D = _head(spec.window_half_angle_h_deg + spec.guard_margin_deg + 10.0, 20.0)
		if not ViewGuard.is_lost(Transform3D(Basis(), SEATED_HEAD), head, spec):
			return "preset %d: the test head is not lost, so the test shows nothing" % number
		var at: Transform3D = _run(guard, head, spec, 0.0, spec.guard_after_s + 0.1)
		if guard.replacements != 1 or guard.reason != "head left the window":
			return "preset %d: %d re-placements (%s) after %.1f s lost" % [number, guard.replacements,
				guard.reason, spec.guard_after_s + 0.1]
		if not at.is_equal_approx(ViewGuard.point_for(head)):
			return "preset %d: frame at %s, not at the head %s" % [number, at, ViewGuard.point_for(head)]
		if ViewGuard.is_lost(at, head, spec) or absf(ViewGuard.window_angles(at, head).x) > 0.01:
			return "preset %d: the window is still not in front after the re-place" % number
		if not at.basis.is_conformal() or not is_equal_approx(at.basis.determinant(), 1.0):
			return "preset %d: the re-placed frame is not a rotation: %s" % [number, at.basis]
	return ""


func test_the_eye_far_from_the_centre_gets_the_frame_back() -> String:
	var spec: CockpitSpec = _spec(4)
	var guard: ViewGuard = ViewGuard.new()
	var head: Transform3D = _head(0.0, 0.0, SEATED_HEAD + Vector3(0.0, 0.0, -spec.frame_distance_m))
	var at: Transform3D = _run(guard, head, spec, 0.0, spec.guard_after_s + 0.1)
	if guard.replacements != 1:
		return "an eye at the shell itself was left there"
	return "" if at.origin.is_equal_approx(head.origin) else "frame at %s, eye at %s" % [at.origin, head.origin]


func test_tracking_regain_re_places_at_once_and_lost_tracking_never_does() -> String:
	var spec: CockpitSpec = _spec(2)
	var guard: ViewGuard = ViewGuard.new()
	var away: Transform3D = _head(170.0, 0.0, SEATED_HEAD + Vector3(2.0, 0.0, 0.0))
	_run(guard, away, spec, 0.0, 10.0, false)
	if guard.replacements != 0:
		return "a pose without tracking re-placed the frame"
	var at: Transform3D = guard.update(Transform3D(Basis(), SEATED_HEAD), _head(30.0), true, spec, 10.1)
	if guard.replacements != 1 or guard.reason != "tracking regained":
		return "the regain did not re-place the frame (%s)" % guard.reason
	return "" if at.is_equal_approx(ViewGuard.point_for(_head(30.0))) else "re-placed at %s" % at


func test_a_recentre_puts_the_frame_back_at_the_head_point() -> String:
	var spec: CockpitSpec = _spec(1)
	var guard: ViewGuard = ViewGuard.new()
	var head: Transform3D = _head(150.0)
	_run(guard, head, spec, 0.0, spec.guard_after_s + 0.1)
	var recentred: Transform3D = Transform3D(Basis(Vector3.UP, 2.0), Vector3(0.1, 1.1, 0.0))
	var at: Transform3D = guard.update(recentred, head, true, spec, 20.0)
	if not at.is_equal_approx(recentred) or guard.reason != "recentre":
		return "after a recentre the frame is at %s, not the new head point %s" % [at, recentred]
	return ""


func test_a_pose_that_is_not_finite_is_ignored() -> String:
	var spec: CockpitSpec = _spec(3)
	var guard: ViewGuard = ViewGuard.new()
	var broken: Transform3D = Transform3D(Basis(Vector3(NAN, 0, 0), Vector3.UP, Vector3.BACK), Vector3(INF, 0, 0))
	var at: Transform3D = _run(guard, broken, spec, 0.0, 10.0)
	if guard.replacements != 0 or not at.is_equal_approx(Transform3D(Basis(), SEATED_HEAD)):
		return "a broken pose moved the frame to %s" % at
	return ""
