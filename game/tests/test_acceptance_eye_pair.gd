extends RefCounted

## The `eyes_same_frame` judge (#1513, CMF-8, GFX-7, DEV-6) with fake eye
## projections and poses: a matching pair passes, a squashed, mismatched or
## differently posed one fails naming what is wrong, and no stereo runtime is
## skipped, not passed.

const CHECK_SCRIPT: GDScript = preload("res://acceptance/checks/eyes_same_frame_check.gd")
const DATA_FILE: String = "res://acceptance/checks/eye_frames.json"
## The Quest 3 starting values of `xr/eye_views.json`, left eye.
const OUTWARD: float = 52.0
const INWARD: float = 42.0
const UP: float = 44.0
const DOWN: float = 52.0
const HALF_IPD: float = 0.0315
const FRAME_USEC: int = 11111


## A left-eye frustum `outward`/`inward` degrees to its left/right, `up`/`down` degrees.
static func _frustum(left_deg: float, right_deg: float, down_deg: float, up_deg: float) -> Projection:
	var near: float = AcceptanceEyePair.NEAR
	return Projection.create_frustum(-tan(deg_to_rad(left_deg)) * near, tan(deg_to_rad(right_deg)) * near,
		-tan(deg_to_rad(down_deg)) * near, tan(deg_to_rad(up_deg)) * near, near, AcceptanceEyePair.FAR)


static func _fovs(vertical_squash: float = 1.0) -> Array[Vector4]:
	var left: Vector4 = AcceptanceEyePair.fov_deg(_frustum(OUTWARD, INWARD, DOWN, UP))
	var right: Vector4 = AcceptanceEyePair.fov_deg(_frustum(INWARD, OUTWARD, DOWN * vertical_squash, UP * vertical_squash))
	return [left, right]


static func _eyes(right_yaw_deg: float = 0.0) -> Array[Transform3D]:
	var right: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(right_yaw_deg)), Vector3(HALF_IPD, 0.0, 0.0))
	return [Transform3D(Basis.IDENTITY, Vector3(-HALF_IPD, 0.0, 0.0)), right]


static func _limits() -> Dictionary:
	return AcceptanceEyePair.parse_limits(AcceptanceEyePair.read_section(DATA_FILE, "eyes_same_frame"))


func test_the_shipped_limits_are_read() -> String:
	var limits: Dictionary = _limits()
	if limits.has("error"):
		return str(limits["error"])
	var made: Variant = CHECK_SCRIPT.sampler(DATA_FILE, Callable())
	return "" if made is AcceptanceEyeFrames and is_equal_approx((made as AcceptanceEyeFrames).seconds, 10.0) \
		else "sampler gave %s" % [made]


func test_fov_degrees_come_back_from_a_frustum() -> String:
	var fov: Vector4 = AcceptanceEyePair.fov_deg(_frustum(OUTWARD, INWARD, DOWN, UP))
	var want: Vector4 = Vector4(-OUTWARD, INWARD, -DOWN, UP)
	return "" if (fov - want).length() < 0.001 else "gave %s, want %s" % [fov, want]


func test_a_matching_pair_passes() -> String:
	var problem: String = AcceptanceEyePair.problem(_fovs(), _fovs(), _eyes(), _limits())
	return "" if problem == "" else problem


func test_a_squashed_eye_fails_naming_it() -> String:
	var problem: String = AcceptanceEyePair.problem(_fovs(0.8), _fovs(), _eyes(), _limits())
	return "" if problem.begins_with("right eye: bottom edge") else "gave '%s'" % problem


func test_eyes_that_do_not_mirror_fail() -> String:
	var mismatched: Array[Vector4] = _fovs()
	mismatched[AcceptanceEyePair.RIGHT] = AcceptanceEyePair.fov_deg(_frustum(OUTWARD, INWARD, DOWN, UP))
	var problem: String = AcceptanceEyePair.problem(mismatched, mismatched, _eyes(), _limits())
	return "" if problem.begins_with("the eyes do not mirror: outward") else "gave '%s'" % problem


func test_eyes_posed_from_different_frames_fail() -> String:
	# One frame of a 100 degrees a second head turn at 90 Hz.
	var problem: String = AcceptanceEyePair.problem(_fovs(), _fovs(), _eyes(1.1), _limits())
	return "" if problem.contains("not posed from the same frame") else "gave '%s'" % problem


func test_eyes_off_the_head_fail() -> String:
	var eyes: Array[Transform3D] = _eyes()
	eyes[0].origin += Vector3(0.0, 0.0, 0.03)
	eyes[1].origin += Vector3(0.0, 0.0, 0.03)
	var problem: String = AcceptanceEyePair.problem(_fovs(), _fovs(), eyes, _limits())
	return "" if problem.contains("from the head") else "gave '%s'" % problem


func test_a_bad_limit_is_named() -> String:
	var values: Dictionary = AcceptanceEyePair.read_section(DATA_FILE, "eyes_same_frame")
	values["fov_tolerance_deg"] = "wide"
	var parsed: Dictionary = AcceptanceEyePair.parse_limits(values)
	return "" if str(parsed.get("error", "")).contains("fov_tolerance_deg") else "gave %s" % parsed


func test_ten_seconds_of_right_frames_pass() -> String:
	var frames: AcceptanceEyeFrames = _sampler(func() -> Variant: return {"fovs": _fovs(), "eyes": _eyes()})
	var usec: int = 0
	while not frames.done and usec < 20 * 1000000:
		frames.on_frame(true, usec)
		usec += FRAME_USEC
	var measured: Dictionary = {}
	var verdict: Array = frames.judge(false, measured)
	if verdict[0] != AcceptanceReport.RESULT_PASS or int(measured["frames_sampled"]) < 900:
		return "gave %s, %s" % [verdict, measured]
	return ""


func test_one_squashed_frame_fails_with_its_time() -> String:
	var count: Array[int] = [0]
	var frames: AcceptanceEyeFrames = _sampler(func() -> Variant:
		count[0] += 1
		return {"fovs": _fovs(0.8 if count[0] == 451 else 1.0), "eyes": _eyes()})
	var usec: int = 0
	while not frames.done and usec < 20 * 1000000:
		frames.on_frame(true, usec)
		usec += FRAME_USEC
	var verdict: Array = frames.judge(false, {})
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).begins_with("1 of ") \
			or not str(verdict[1]).contains("first at 5.00 s: right eye"):
		return "gave %s" % [verdict]
	return ""


func test_no_stereo_runtime_is_skipped_not_passed() -> String:
	var frames: AcceptanceEyeFrames = _sampler(func() -> Variant: return AcceptanceEyePair.read_interface(null))
	frames.on_frame(true, 0)
	var verdict: Array = frames.judge(false, {})
	var required: Array = frames.judge(true, {})
	if verdict[0] != AcceptanceReport.RESULT_SKIPPED or not str(verdict[1]).contains("no XR runtime"):
		return "gave %s" % [verdict]
	return "" if required[0] == AcceptanceReport.RESULT_FAIL else "required gave %s" % [required]


func test_no_drawn_frame_is_skipped() -> String:
	var frames: AcceptanceEyeFrames = _sampler(func() -> Variant: return {"fovs": _fovs(), "eyes": _eyes()})
	frames.on_frame(false, 0)
	var verdict: Array = frames.judge(false, {})
	return "" if verdict[0] == AcceptanceReport.RESULT_SKIPPED and frames.frames_sampled == 0 else "gave %s" % [verdict]


static func _sampler(read: Callable) -> AcceptanceEyeFrames:
	return CHECK_SCRIPT.sampler(DATA_FILE, read) as AcceptanceEyeFrames
