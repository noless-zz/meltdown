class_name AcceptanceEyePair
extends RefCounted

## One sampled frame of the headset's two eyes, judged for the m1
## `eyes_same_frame` steps (#1513, CMF-8, GFX-7, DEV-6). On 27 Nov the owner
## saw a picture that was wrong in a way no flat screenshot showed (#1503). An eye
## drawn with a squashed or wrong field of view, or the two eyes posed from
## different frames, breaks the stereo picture in the same unseen way. So every
## drawn frame is checked:
##
## - each eye's field of view (its four edges, in degrees from straight ahead)
##   matches the runtime's own for that eye, within `fov_tolerance_deg`;
## - the right eye's view is the mirror of the left one, within
##   `mirror_tolerance_deg` (the Quest's lenses are mirror images);
## - in the head's space, the two eyes point the same way, within
##   `eye_rotation_tolerance_deg`, and sit side by side `ipd_min_m` to `ipd_max_m`
##   apart and centred on the head within `head_offset_tolerance_m`. Eyes posed
##   from different frames of a turning head point different ways and leave the
##   head's centre.
##
## The limits are data (`acceptance/checks/eye_frames.json`, ARC-4). Pure: tests
## pass fake projections and transforms; `read_interface` reads the live runtime.
## View only: nothing here reads or writes simulation state (ARC-3).

const LEFT: int = 0
const RIGHT: int = 1
const EYE_NAMES: Array[String] = ["left eye", "right eye"]
const EDGE_NAMES: Array[String] = ["left", "right", "bottom", "top"]
## The near and far planes the interface is asked for; the edges do not depend on them.
const NEAR: float = 0.05
const FAR: float = 100.0
## The limit keys `problem` reads, each with the range a data file may set.
const LIMIT_RANGES: Dictionary = {
	"fov_tolerance_deg": Vector2(0.01, 5.0),
	"mirror_tolerance_deg": Vector2(0.01, 10.0),
	"eye_rotation_tolerance_deg": Vector2(0.01, 5.0),
	"head_offset_tolerance_m": Vector2(0.0001, 0.05),
	"ipd_min_m": Vector2(0.03, 0.08),
	"ipd_max_m": Vector2(0.05, 0.1),
}


## The four view edges of `projection` in degrees from straight ahead, as
## Vector4(left, right, bottom, top): left and bottom are negative.
static func fov_deg(projection: Projection) -> Vector4:
	var rect: Rect2 = EyeViews.edges_of(projection)
	return Vector4(rad_to_deg(atan(rect.position.x)), rad_to_deg(atan(rect.end.x)),
		rad_to_deg(atan(rect.position.y)), rad_to_deg(atan(rect.end.y)))


## One frame of the running interface: {"fovs": [left, right] as `fov_deg`,
## "eyes": [left, right] eye transforms in the head's space}, or why there is no
## stereo runtime to read.
static func read_interface(xr: XRInterface) -> Variant:
	if xr == null or not xr.is_initialized():
		return "no XR runtime"
	if xr.get_view_count() != 2:
		return "the XR runtime draws %d view(s), not two eyes" % xr.get_view_count()
	# Both come from the same interface, so they are the poses of the frame being drawn.
	var head: Transform3D = XRServer.get_hmd_transform()
	var fovs: Array[Vector4] = []
	var eyes: Array[Transform3D] = []
	for view: int in 2:
		fovs.append(fov_deg(xr.get_projection_for_view(view, 1.0, NEAR, FAR)))
		eyes.append(head.affine_inverse() * xr.get_transform_for_view(view, Transform3D.IDENTITY))
	return {"fovs": fovs, "eyes": eyes}


## Empty when the frame is right, else what is wrong, naming the eye and edge.
## `fovs` and `reference` hold `fov_deg` per eye; `eyes` are the eye transforms
## in the head's space; `limits` holds every key of `LIMIT_RANGES`.
static func problem(fovs: Array[Vector4], reference: Array[Vector4], eyes: Array[Transform3D],
		limits: Dictionary) -> String:
	var fov_tolerance: float = float(limits["fov_tolerance_deg"])
	for eye: int in 2:
		for edge: int in 4:
			if absf(fovs[eye][edge] - reference[eye][edge]) > fov_tolerance:
				return "%s: %s edge at %.2f degrees, the runtime's at %.2f" % [
					EYE_NAMES[eye], EDGE_NAMES[edge], fovs[eye][edge], reference[eye][edge]]
	var mirror: String = mirror_problem(fovs, float(limits["mirror_tolerance_deg"]))
	if mirror != "":
		return mirror
	return pose_problem(eyes, limits)


## Empty when the right eye's view mirrors the left one's within `tolerance` degrees.
static func mirror_problem(fovs: Array[Vector4], tolerance: float) -> String:
	var left: Vector4 = fovs[LEFT]
	var right: Vector4 = fovs[RIGHT]
	# The left eye's left (outward) edge mirrors the right eye's right edge, and so on.
	var pairs: Array[Vector2] = [Vector2(-left.x, right.y), Vector2(left.y, -right.x),
		Vector2(left.z, right.z), Vector2(left.w, right.w)]
	var names: Array[String] = ["outward", "inward", "bottom", "top"]
	for index: int in pairs.size():
		if absf(pairs[index].x - pairs[index].y) > tolerance:
			return "the eyes do not mirror: %s edges at %.2f and %.2f degrees" % [
				names[index], pairs[index].x, pairs[index].y]
	return ""


## Empty when the two eye transforms, in the head's space, look like one frame's.
static func pose_problem(eyes: Array[Transform3D], limits: Dictionary) -> String:
	var left: Transform3D = eyes[LEFT]
	var right: Transform3D = eyes[RIGHT]
	var turned: float = rad_to_deg(left.basis.get_rotation_quaternion().angle_to(right.basis.get_rotation_quaternion()))
	if turned > float(limits["eye_rotation_tolerance_deg"]):
		return "the eyes point %.2f degrees apart: not posed from the same frame" % turned
	var apart: Vector3 = right.origin - left.origin
	if apart.x < float(limits["ipd_min_m"]) or apart.x > float(limits["ipd_max_m"]):
		return "the eyes are %.4f m apart side to side, outside %.3f..%.3f m" % [
			apart.x, float(limits["ipd_min_m"]), float(limits["ipd_max_m"])]
	var offset_limit: float = float(limits["head_offset_tolerance_m"])
	if Vector2(apart.y, apart.z).length() > offset_limit:
		return "the right eye is %.4f m off the left eye's level: not posed from the same frame" \
			% Vector2(apart.y, apart.z).length()
	var middle: Vector3 = (left.origin + right.origin) * 0.5
	if middle.length() > offset_limit:
		return "the eyes' midpoint is %.4f m from the head: not posed from the head's frame" % middle.length()
	return ""


## The limits in `values` as floats, or {"error": ...} naming the key.
static func parse_limits(values: Dictionary) -> Dictionary:
	var parsed: Dictionary = {}
	for key: String in LIMIT_RANGES:
		if not values.has(key):
			return {"error": "missing key \"%s\"" % key}
		var value: Variant = values[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		var range_: Vector2 = LIMIT_RANGES[key]
		if float(value) < range_.x or float(value) > range_.y:
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, range_.x, range_.y]}
		parsed[key] = float(value)
	if float(parsed["ipd_min_m"]) >= float(parsed["ipd_max_m"]):
		return {"error": "\"ipd_min_m\" must be under \"ipd_max_m\""}
	return parsed


## `fov` rounded for a report: [left, right, bottom, top] degrees.
static func describe_fov(fov: Vector4) -> Array[float]:
	return [snappedf(fov.x, 0.01), snappedf(fov.y, 0.01), snappedf(fov.z, 0.01), snappedf(fov.w, 0.01)]


## The section `name` of the JSON file at `path` (`acceptance/checks/eye_frames.json`),
## or {"error": ...} naming the file and what is wrong.
static func read_section(path: String, name: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "%s: file not found" % path}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"error": "%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get(name)) != TYPE_DICTIONARY:
		return {"error": "%s: needs an object \"%s\"" % [path, name]}
	return (json.data as Dictionary)[name]
