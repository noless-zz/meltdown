class_name CockpitDashPiece
extends RefCounted

## One modelled piece of the dash (#1306, GFX-2, ARC-4): a box (a raised
## console, a vent, a switch) or a knob, placed by angle from the eye like the
## rest of the frame. A cockpit file's optional `"dash"` list holds them:
##   {"shape": "box", "yaw_deg": -20, "pitch_deg": -33, "distance_m": 0.34,
##    "size_m": [0.12, 0.02, 0.02], "tone": 0.8, "lamp_color": [0, 0, 0]}
## `size_m` is width along the yaw, height along the pitch and depth toward
## the eye; the piece's face toward the eye sits `distance_m` from it. `tone`
## scales the structure colour; `lamp_color` makes it glow, for indicator
## lamps, and adds no light (GFX-4). Both are optional.
##
## The dash stays inside the preset's frame limits (CMF-1): `CockpitSpec`
## rejects a piece that reaches into the window or past the shell, so the
## window and what it shows never change. View only (ARC-3).

const LIST_KEY: String = "dash"
const SHAPES: Array[String] = ["box", "knob"]
## The part each shape is built into (`CockpitFrame.PARTS`).
const SHAPE_PART: Dictionary[String, String] = {"box": "Dash", "knob": "Knobs"}
const REQUIRED_KEYS: Array[String] = ["shape", "yaw_deg", "pitch_deg", "distance_m", "size_m"]
const OPTIONAL_KEYS: Array[String] = ["tone", "lamp_color"]
## Nearest a piece may come to the eye, metres, like the frame's shapes.
const MIN_DISTANCE_M: float = 0.3
const SIZE_RANGE_M: Vector2 = Vector2(0.002, 0.3)
const TONE_RANGE: Vector2 = Vector2(0.3, 1.5)

var shape: String = "box"
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var distance_m: float = 0.4
var size_m: Vector3 = Vector3(0.05, 0.02, 0.02)
var tone: float = 1.0
var lamp_color: Color = Color.BLACK


## The piece placed in the frame's space as a unit box (or unit cylinder for
## a knob, its axis toward the eye) scaled to `size_m`.
func placed() -> Transform3D:
	var basis: Basis = CockpitGeometry.facing_basis(yaw_deg, pitch_deg)
	if shape == "knob":
		# A cylinder's axis is its Y; turn it toward the eye.
		basis = (basis * Basis(Vector3.RIGHT, PI * 0.5)).scaled_local(Vector3(size_m.x, size_m.z, size_m.y))
	else:
		basis = basis.scaled_local(size_m)
	return Transform3D(basis, CockpitGeometry.direction(yaw_deg, pitch_deg) * (distance_m + size_m.z * 0.5))


## Why the piece does not fit a frame with window half-angles `window` (yaw,
## pitch) and its shell `frame_distance_m` away, or "": every corner lies
## outside the window, and the piece between `MIN_DISTANCE_M` and the shell.
func fit_error(window: Vector2, frame_distance_m: float) -> String:
	if distance_m < MIN_DISTANCE_M:
		return "distance_m is %s, nearer than %s" % [distance_m, MIN_DISTANCE_M]
	for corner: Vector3 in CockpitGeometry.corners(placed(), true):
		if corner.length() > frame_distance_m:
			return "reaches %.3f m from the eye, past the shell at %s" % [corner.length(), frame_distance_m]
		var angles: Vector2 = CockpitGeometry.yaw_pitch(corner)
		if absf(angles.x) < window.x and absf(angles.y) < window.y:
			return "reaches into the window at yaw %.1f, pitch %.1f" % [angles.x, angles.y]
	return ""


## Parses the `"dash"` list. Returns an `Array[CockpitDashPiece]`, or a
## message naming the field at fault ("dash[2].size_m ...").
static func parse_list(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return "\"%s\" must be a list" % LIST_KEY
	var list: Array[CockpitDashPiece] = []
	for index: int in (raw as Array).size():
		var parsed: Variant = parse_entry(raw[index], "%s[%d]" % [LIST_KEY, index])
		if parsed is String:
			return parsed
		list.append(parsed)
	return list


## Parses one entry; `field` names it in messages.
static func parse_entry(entry: Variant, field: String) -> Variant:
	if typeof(entry) != TYPE_DICTIONARY:
		return "%s must be an object" % field
	var data: Dictionary = entry
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (REQUIRED_KEYS.has(key) or OPTIONAL_KEYS.has(key)):
			return "%s has unknown key \"%s\"" % [field, str(key)]
	for key: String in REQUIRED_KEYS:
		if not data.has(key):
			return "%s.%s is missing" % [field, key]
	var piece: CockpitDashPiece = CockpitDashPiece.new()
	if typeof(data["shape"]) != TYPE_STRING or not SHAPES.has(data["shape"]):
		return "%s.shape \"%s\" is not one of %s" % [field, str(data["shape"]), ", ".join(SHAPES)]
	piece.shape = data["shape"]
	var limits: Dictionary[String, Vector2] = {
		"yaw_deg": Vector2(-90.0, 90.0), "pitch_deg": Vector2(-80.0, 80.0),
		"distance_m": Vector2(MIN_DISTANCE_M, 0.95), "tone": TONE_RANGE,
	}
	for key: String in limits:
		if not data.has(key):
			continue
		var problem: String = _number_error(data[key], limits[key])
		if problem != "":
			return "%s.%s %s" % [field, key, problem]
		piece.set(key, float(data[key]))
	var size: Variant = data["size_m"]
	if typeof(size) != TYPE_ARRAY or (size as Array).size() != 3:
		return "%s.size_m must be an array of three numbers" % field
	for part: Variant in size:
		var problem: String = _number_error(part, SIZE_RANGE_M)
		if problem != "":
			return "%s.size_m %s" % [field, problem]
	piece.size_m = Vector3(float(size[0]), float(size[1]), float(size[2]))
	if data.has("lamp_color"):
		var color_error: String = CockpitSpec._color_error(data["lamp_color"])
		if color_error != "":
			return "%s.lamp_color %s" % [field, color_error]
		var parts: Array = data["lamp_color"]
		piece.lamp_color = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return piece


static func _number_error(number: Variant, bounds: Vector2) -> String:
	# A bool must not pass as 0 or 1.
	if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT:
		return "must be a number"
	if float(number) < bounds.x or float(number) > bounds.y:
		return "is %s, must be within %s..%s" % [number, bounds.x, bounds.y]
	return ""
