class_name EyeViews
extends RefCounted

## What each of the headset's two eyes shows with the head held straight
## ahead (#1507, CMF-8). The owner saw the status panel whole in the left eye
## and only as a sliver in the right one: a binocular conflict. Anything fixed
## in the cockpit for the pilot to read must lie where both eyes see it, so
## this models each eye as its own point and its own (asymmetric) frustum,
## not the centre camera.
##
## Read from `res://xr/eye_views.json` (ARC-4), in the cockpit's space from the
## eye point (x right, y up, -z ahead), for the left eye; the right eye is its
## mirror image:
##
##     {"ipd_m": d, "outward_deg": o, "inward_deg": i, "up_deg": u,
##      "down_deg": w, "edge_margin_deg": m}
##
## `outward_deg` is the left eye's half-angle to the left (away from the
## nose), `inward_deg` to the right (towards it). The inward sides of the two
## eyes bound the region both see. `edge_margin_deg` is kept clear inside
## every edge, where the Quest 3's lenses blur and the view may be cropped.
## On a headset, `from_interface` reads the runtime's own projections instead.
##
## Presentation only: nothing here reads or writes simulation state (ARC-3).

const DEFAULT_FILE: String = "res://xr/eye_views.json"
const LEFT: int = 0
const RIGHT: int = 1
const EYE_NAMES: Array[String] = ["left eye", "right eye"]
## Each key with the range it must lie in.
const RANGES: Dictionary = {
	"ipd_m": Vector2(0.05, 0.08),
	"outward_deg": Vector2(20.0, 80.0),
	"inward_deg": Vector2(20.0, 80.0),
	"up_deg": Vector2(20.0, 80.0),
	"down_deg": Vector2(20.0, 80.0),
	"edge_margin_deg": Vector2(0.0, 10.0),
}
## Starting values for the Quest 3 (96 degrees tall per eye, as in
## `xr/hub_screen.json`); the device run prints the runtime's real ones.
const FALLBACK: Dictionary = {
	"ipd_m": 0.063,
	"outward_deg": 52.0,
	"inward_deg": 42.0,
	"up_deg": 44.0,
	"down_deg": 52.0,
	"edge_margin_deg": 3.0,
}

## Where each eye sits from the eye point, `LEFT` then `RIGHT`.
var origins: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Each eye's view edges as tangents, `Rect2(left, down, width, height)`:
## a point at (x, y, -z) is inside when (x / z, y / z) lies in the rect.
var edges: Array[Rect2] = [Rect2(), Rect2()]
## How far inside every edge a point must lie, in degrees.
var margin_deg: float = 0.0
## The values the views were built from, for reports.
var values: Dictionary = {}
## Empty, or what was wrong with the file.
var error: String = ""


## The views a look file `values` (as `parse` gives) describes.
static func from_values(given: Dictionary) -> EyeViews:
	var views: EyeViews = EyeViews.new()
	views.values = given
	var half: float = float(given["ipd_m"]) * 0.5
	var out_t: float = tan(deg_to_rad(float(given["outward_deg"])))
	var in_t: float = tan(deg_to_rad(float(given["inward_deg"])))
	var up_t: float = tan(deg_to_rad(float(given["up_deg"])))
	var down_t: float = tan(deg_to_rad(float(given["down_deg"])))
	views.origins = [Vector3(-half, 0.0, 0.0), Vector3(half, 0.0, 0.0)]
	views.edges = [Rect2(-out_t, -down_t, out_t + in_t, down_t + up_t),
		Rect2(-in_t, -down_t, out_t + in_t, down_t + up_t)]
	views.margin_deg = float(given["edge_margin_deg"])
	return views


## The views of the running XR interface's two eyes, with `margin` degrees
## kept clear, or null when no stereo interface is running.
static func from_interface(xr: XRInterface, margin: float) -> EyeViews:
	if xr == null or not xr.is_initialized() or xr.get_view_count() != 2:
		return null
	var views: EyeViews = EyeViews.new()
	var head: Array[Vector3] = []
	for view: int in 2:
		head.append(xr.get_transform_for_view(view, Transform3D.IDENTITY).origin)
		views.edges[view] = edges_of(xr.get_projection_for_view(view, 1.0, 0.05, 100.0))
	var half: float = head[LEFT].distance_to(head[RIGHT]) * 0.5
	views.origins = [Vector3(-half, 0.0, 0.0), Vector3(half, 0.0, 0.0)]
	views.margin_deg = margin
	views.values = {"ipd_m": half * 2.0, "source": "runtime"}
	for view: int in 2:
		var rect: Rect2 = views.edges[view]
		views.values[EYE_NAMES[view]] = [snappedf(rad_to_deg(atan(rect.position.x)), 0.1),
			snappedf(rad_to_deg(atan(rect.end.x)), 0.1), snappedf(rad_to_deg(atan(rect.position.y)), 0.1),
			snappedf(rad_to_deg(atan(rect.end.y)), 0.1)]
	return views


## The view edges, as tangents, of an off-axis perspective `projection`.
static func edges_of(projection: Projection) -> Rect2:
	# Godot's frustum keeps 2n/(r-l) in x.x and (r+l)/(r-l) in z.x; an edge
	# is where the projected x reaches -1 or +1 (the same for y).
	var sx: float = projection.x.x
	var ox: float = projection.z.x
	var sy: float = projection.y.y
	var oy: float = projection.z.y
	var left: float = (ox - 1.0) / sx
	var down: float = (oy - 1.0) / sy
	return Rect2(left, down, 2.0 / sx, 2.0 / sy)


## Empty when `point` (cockpit space, from the eye point) lies inside both
## eyes' views at least `margin_deg` from every edge, else what is wrong,
## naming the eye and the edge.
func problem_at(point: Vector3) -> String:
	var margin: float = deg_to_rad(margin_deg)
	for eye: int in 2:
		var seen: Vector3 = point - origins[eye]
		if seen.z >= -0.001:
			return "%s: behind the eye" % EYE_NAMES[eye]
		var rect: Rect2 = edges[eye]
		var h: float = atan(seen.x / -seen.z)
		var v: float = atan(seen.y / -seen.z)
		if h < atan(rect.position.x) + margin:
			return "%s: %.1f degrees past its left edge" % [EYE_NAMES[eye], rad_to_deg(atan(rect.position.x) + margin - h)]
		if h > atan(rect.end.x) - margin:
			return "%s: %.1f degrees past its right edge" % [EYE_NAMES[eye], rad_to_deg(h - atan(rect.end.x) + margin)]
		if v < atan(rect.position.y) + margin:
			return "%s: %.1f degrees past its bottom edge" % [EYE_NAMES[eye], rad_to_deg(atan(rect.position.y) + margin - v)]
		if v > atan(rect.end.y) - margin:
			return "%s: %.1f degrees past its top edge" % [EYE_NAMES[eye], rad_to_deg(v - atan(rect.end.y) + margin)]
	return ""


## Parses the text of an eye views file: the values as floats, or a
## dictionary holding only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if not RANGES.has(str(key)):
			return {"error": "unknown key \"%s\"" % str(key)}
	var parsed: Dictionary = {}
	for key: String in RANGES:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
		var value: Variant = data[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		var range_: Vector2 = RANGES[key]
		if float(value) < range_.x or float(value) > range_.y:
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, range_.x, range_.y]}
		parsed[key] = float(value)
	return parsed


## The views in the file at `path`. A missing or rejected file gives the
## `FALLBACK` views with `error` naming the field, and a warning.
static func load_file(path: String = DEFAULT_FILE) -> EyeViews:
	var parsed: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		parsed = parse(FileAccess.get_file_as_string(path))
	if parsed.has("error"):
		push_warning("EyeViews uses the built-in Quest 3 views; %s: %s" % [path, parsed["error"]])
		var views: EyeViews = from_values(FALLBACK)
		views.error = str(parsed["error"])
		return views
	return from_values(parsed)
