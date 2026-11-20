extends RefCounted

## Hits cannot move the head away from the cockpit window (#651): over a
## minute of hits from every side on each preset, the head keeps its place
## and heading inside the frame, and the rig and frame stay rotations. The
## shake goes into the rig's transform; the frame hangs under the rig at the
## head point, so both move together and the eye never leaves the window.

const FRAME: float = 1.0 / 90.0
const SECONDS: float = 60.0
const SEATED_HEAD: Vector3 = Vector3(0.05, 1.2, -0.03)


static func _rotation_error(basis: Basis) -> String:
	if not basis.is_finite():
		return "not finite: %s" % basis
	if not basis.is_conformal() or not is_equal_approx(basis.determinant(), 1.0):
		return "not a rotation: %s (determinant %s)" % [basis, basis.determinant()]
	return ""


static func _random_basis(rng: RandomNumberGenerator) -> Basis:
	var axis: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	if axis.length() < 0.01:
		axis = Vector3.UP
	return Basis(axis.normalized(), rng.randf_range(-PI, PI))


func test_a_minute_of_hits_keeps_the_head_in_the_window_on_every_preset() -> String:
	for number: int in range(1, 5):
		var message: String = _fly_a_minute_of_hits(number)
		if message != "":
			return "preset %d: %s" % [number, message]
	return ""


func _fly_a_minute_of_hits(number: int) -> String:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.set_preset(number)
	var spec: CockpitSpec = comfort.cockpit_spec()
	var recentre: HeadRecentre = HeadRecentre.new()
	var head: Transform3D = Transform3D(Basis(Vector3.UP, 0.4), SEATED_HEAD)
	recentre.apply(head)
	var guard: ViewGuard = ViewGuard.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 651 + number
	var hits: int = 0
	var shaken: int = 0
	var t: float = 0.0
	while t < SECONDS:
		if rng.randf() < 0.12:  # Bursts every few frames, as robots fire since #612.
			var kind: SimEvent.Kind = SimEvent.Kind.SHIP_HIT if rng.randf() < 0.8 else SimEvent.Kind.WALL_IMPACT
			var direction: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			var events: Array[SimEvent] = [SimEvent.new(kind, 0, rng.randf_range(0.5, 60.0), direction)]
			# Now and then a degenerate ship basis, which `feed` normalises.
			var ship_basis: Basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO) if rng.randf() < 0.05 else _random_basis(rng)
			comfort.feed_hit_shake(events, 0, ship_basis)
			hits += 1
		comfort.advance_hit_shake(FRAME)
		t += FRAME
		if comfort.shake_offset != Transform3D.IDENTITY:
			shaken += 1
		var ship_pose: Transform3D = Transform3D(_random_basis(rng), Vector3(rng.randf_range(-50, 50), 0.0, t))
		var rig: Transform3D = recentre.rig_transform(ship_pose * comfort.shake_offset)
		var frame_at: Transform3D = guard.update(RigViews.head_point(recentre), head, true, spec, t)
		var problem: String = _rotation_error(rig.basis)
		if problem == "":
			problem = _rotation_error((rig * frame_at).basis)
		if problem != "":
			return "at %.2f s the rig or frame is %s" % [t, problem]
		if not rig.origin.is_finite():
			return "at %.2f s the rig origin is %s" % [t, rig.origin]
		# The eye seen from the frame, both through the rig: what the pilot sees.
		var eye_in_frame: Transform3D = (rig * frame_at).affine_inverse() * (rig * head)
		if ViewGuard.is_lost(Transform3D.IDENTITY, eye_in_frame, spec):
			return "at %.2f s the head left the window: %s" % [t, eye_in_frame]
		if eye_in_frame.origin.length() > 1.0e-3:
			return "at %.2f s the eye is %.4f m from the frame's centre" % [t, eye_in_frame.origin.length()]
	if guard.replacements != 0:
		return "the guard had to re-place the frame %d times" % guard.replacements
	if number > 1 and shaken == 0:
		return "%d hits never shook the view, so the test shows nothing" % hits
	return ""
