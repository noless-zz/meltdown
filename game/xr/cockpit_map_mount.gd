class_name CockpitMapMount
extends RefCounted

## Where a cockpit mounts the map hologram when the pilot chooses the cockpit
## place (#1321, MAP-1, ARC-4): the cockpit file's optional `map_mount` object,
##
##     "map_mount": {"yaw_deg": 27, "pitch_deg": -10, "distance_m": 0.4, "size_m": 0.075}
##
## seen from the eye point like `CockpitInstrument` (yaw right of straight
## ahead, pitch above it). The spot is the one on the right; while the status
## panel sits in a right-hand corner the map moves to the mirrored spot on the
## left, so map and panel never share a side. `size_m` is the edge of the cube
## the map is fitted into there, smaller than in the hand so it stays clear of
## the panel and inside the window (`MapPanelClearance`). A file without the
## object gets `FALLBACK`. View only: nothing here reaches the simulation (ARC-3).

const KEY: String = "map_mount"
const KEYS: Array[String] = ["yaw_deg", "pitch_deg", "distance_m", "size_m"]
## Allowed range of each key, inclusive: [minimum, maximum]. The distance keeps
## the map nearer than any frame shell may be and beyond the camera's near plane.
const RANGES: Dictionary[String, Array] = {
	"yaw_deg": [0.0, 80.0],
	"pitch_deg": [-80.0, 80.0],
	"distance_m": [0.3, 0.85],
	"size_m": [0.03, 0.3],
}
## The panel corners on the right, which send the map to the mirrored spot.
const RIGHT_CORNERS: Array[String] = ["top_right", "bottom_right"]
## Used without a `map_mount` object: the spot the shipped files name.
const FALLBACK: Dictionary = {"yaw_deg": 27.0, "pitch_deg": -10.0, "distance_m": 0.4, "size_m": 0.075}

var yaw_deg: float = FALLBACK["yaw_deg"]
var pitch_deg: float = FALLBACK["pitch_deg"]
var distance_m: float = FALLBACK["distance_m"]
var size_m: float = FALLBACK["size_m"]


## Parses a `map_mount` value: every key in `KEYS` as a number in its range
## and nothing else. Returns the mount or a message naming the field at fault.
static func parse(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"%s\" must be an object" % KEY
	var data: Dictionary = value
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return "%s has unknown key \"%s\"" % [KEY, str(key)]
	var mount: CockpitMapMount = CockpitMapMount.new()
	for key: String in KEYS:
		if not data.has(key):
			return "%s.%s is missing" % [KEY, key]
		var number: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT:
			return "%s.%s must be a number" % [KEY, key]
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(number) < low or float(number) > high:
			return "%s.%s is %s, must be within %s..%s" % [KEY, key, number, low, high]
		mount.set(key, float(number))
	return mount


## Whether the map sits on the left: while the panel is in a right-hand corner.
static func on_left(panel_corner: String) -> bool:
	return RIGHT_CORNERS.has(panel_corner)


## The map's centre in the cockpit frame's space (eye at the origin, -z ahead)
## for a panel in `panel_corner`.
func spot(panel_corner: String) -> Vector3:
	var yaw: float = deg_to_rad(-yaw_deg if on_left(panel_corner) else yaw_deg)
	var pitch: float = deg_to_rad(pitch_deg)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * distance_m
