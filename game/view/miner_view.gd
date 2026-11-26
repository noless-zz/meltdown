class_name MinerView
extends Node3D

## Draws the miners still trapped in the level (SLV-3, #1034): an original lit
## beacon per miner, not a human figure, with a ring around it that fills while
## a ship holds within reach (`MinerRescue.held` against `hold_ticks()`), so
## the hold-to-rescue rule reads at a glance. The beacon is a six-sided column
## in rescue green, never round or orange: an orange glowing capsule near the
## exit was taken for a second reactor (#1208), whose core is an orange sphere. A rescued miner leaves
## `MinerRescue.trapped`, and its marker goes with it.
##
## It only reads the rescue state and the ship it is given and never writes to
## them (MP-2). The ring faces the ship, like `SalvageRing`, so it reads as a
## dial. Nodes are pooled. The look lives in `res://view/miner_look.json`
## (ARC-4), with an optional escape pod under the beacon (#1308, `MinerPod`).
## A rescued miner is seen boarding the ship (#1375, `MinerLeave`).

const NODE_NAME: String = "MinerView"
const MARKER_PREFIX: String = "Miner"
const DEFAULT_LOOK_FILE: String = "res://view/miner_look.json"
const KEYS: Array[String] = ["beacon", "ring"]
const BEACON_KEYS: Array[String] = ["radius", "height", "color", "energy"]
const RING_KEYS: Array[String] = ["radius", "width", "track_color", "track_energy", "fill_color", "fill_energy"]
## Allowed range of every number key, inclusive.
const RANGES: Dictionary = {
	"radius": [0.05, 5.0], "height": [0.1, 10.0], "width": [0.01, 1.0],
	"energy": [0.0, 10.0], "track_energy": [0.0, 10.0], "fill_energy": [0.0, 20.0],
}
## Sides of the beacon column; few enough to read as a column, not a ball.
const BEACON_SIDES: int = 6
## Steps in a full ring; a partial ring uses its share, at least one.
const RING_SEGMENTS: int = 48
const FALLBACK_LOOK: Dictionary = {
	"beacon": {"radius": 0.3, "height": 1.4, "color": Color(0.35, 1.0, 0.5), "energy": 3.0},
	"ring": {"radius": 1.3, "width": 0.14, "track_color": Color(0.4, 0.4, 0.4), "track_energy": 0.4,
		"fill_color": Color(0.5, 1.0, 0.6), "fill_energy": 3.0},
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK_LOOK
var _beacon_mesh: CylinderMesh = null
var _track_mesh: ArrayMesh = null
var _fill_material: StandardMaterial3D = null
var _markers: Array[Node3D] = []
var _pod: MinerPod = MinerPod.new()
## The fill each marker's ring was last built for, 0..1, by marker index.
var _fills: Array[float] = []
## Says what a miner is, the first time it comes into sight (#1220).
var label: MinerLabel = MinerLabel.new()
var leave: MinerLeave = MinerLeave.new()


func _init() -> void:
	name = NODE_NAME
	add_child(leave)
	load_look()
	add_child(label)


## Parses the text of a look file: `{"beacon": {"radius", "height", "color",
## "energy"}, "ring": {"radius", "width", "track_color", "track_energy",
## "fill_color", "fill_energy"}}`, colours as [r, g, b] within 0..1. Returns
## the look with colours as `Color`s, or a dictionary holding only `"error"`,
## which names the key.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or key == MinerPod.KEY or key == MinerLeave.KEY):
			return {"error": "unknown key \"%s\"" % str(key)}
	var look: Dictionary = {}
	if data.has(MinerLeave.KEY):
		look[MinerLeave.KEY] = MinerLeave.parse(data[MinerLeave.KEY])
		if look[MinerLeave.KEY].has("error"):
			return look[MinerLeave.KEY]
	if data.has(MinerPod.KEY):
		look[MinerPod.KEY] = MinerPod.parse(data[MinerPod.KEY])
		if look[MinerPod.KEY].has("error"):
			return look[MinerPod.KEY]
	var shapes: Dictionary = {"beacon": BEACON_KEYS, "ring": RING_KEYS}
	for part: String in shapes:
		var entry: Dictionary = _parse_entry(part, data.get(part, null), shapes[part])
		if entry.has("error"):
			return entry
		look[part] = entry
	if look["ring"]["width"] >= look["ring"]["radius"]:
		return {"error": "\"ring.width\" must be less than ring.radius"}
	return look


## Applies the look file at `path`. A missing or rejected file keeps the
## fallback look, sets `look_error` and pushes a warning. Returns `look_error`.
func load_look(path: String = DEFAULT_LOOK_FILE) -> String:
	var look: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		look = parse_look(FileAccess.get_file_as_string(path))
	_look = FALLBACK_LOOK
	look_error = ""
	if look.has("error"):
		look_error = "%s: %s" % [path, look["error"]]
		push_warning("MinerView uses the fallback look; %s" % look_error)
	else:
		_look = look
	for marker: Node3D in _markers:
		marker.free()
	_markers.clear()
	_fills.clear()
	_pod = MinerPod.new(_look.get(MinerPod.KEY, {}))
	var beacon: Dictionary = _look["beacon"]
	_beacon_mesh = CylinderMesh.new()
	_beacon_mesh.top_radius = beacon["radius"]
	_beacon_mesh.bottom_radius = beacon["radius"]
	_beacon_mesh.height = maxf(beacon["height"], 2.0 * float(beacon["radius"]))
	_beacon_mesh.radial_segments = BEACON_SIDES
	_beacon_mesh.rings = 0
	_beacon_mesh.material = _glow(beacon["color"], beacon["energy"])
	var ring: Dictionary = _look["ring"]
	_track_mesh = build_arc(ring["radius"], ring["width"], 1.0)
	if _track_mesh != null:
		_track_mesh.surface_set_material(0, _glow(ring["track_color"], ring["track_energy"]))
	_fill_material = _glow(ring["fill_color"], ring["fill_energy"])
	leave.configure(_look.get(MinerLeave.KEY, {}), _beacon_mesh, _pod)
	return look_error


## Takes in the copies of one advance's events: each rescued miner starts
## boarding from where its marker was drawn (#1375).
func feed(events: Array[SimEvent]) -> void:
	leave.feed(events, _markers)


## Draws a marker per miner of `rescue.trapped`, its ring filled by how long a
## ship has held at it, facing `ship`; none when `rescue` is null (rescue off).
## A miner first in sight through `walls` gets its label for a while (#1220).
func show_miners(rescue: MinerRescue, ship: ShipState, walls: BoxUnion = null, delta: float = 0.0) -> void:
	label.show_labels(rescue, ship, walls, delta)
	leave.advance(delta, ship)
	var count: int = rescue.trapped.size() if rescue != null else 0
	while _markers.size() < count:
		_add_marker()
	for index: int in count:
		var at: Vector3 = MinerRescue.position_of(rescue.trapped[index])
		var held: int = rescue.held[index] if index < rescue.held.size() else 0
		var marker: Node3D = _markers[index]
		marker.position = at
		marker.visible = true
		var ring: Node3D = marker.get_node("Ring") as Node3D
		ring.basis = SalvageRing._facing(at, ship)  # The same turn as a part's ring.
		_set_fill(index, clampf(float(held) / float(rescue.hold_ticks()), 0.0, 1.0))
	for index: int in range(count, _markers.size()):
		_markers[index].visible = false


## Markers drawn now.
func shown_count() -> int:
	var shown: int = 0
	for marker: Node3D in _markers:
		if marker.visible:
			shown += 1
	return shown


func marker_count() -> int:
	return _markers.size()


## The pooled marker at `index`, for tests.
func marker(index: int) -> Node3D:
	return _markers[index]


## How full the ring of the marker at `index` is drawn, 0..1.
func fill_of(index: int) -> float:
	return _fills[index]


## A flat band in the XZ plane (facing +Y) from angle 0 through `fill` of a
## turn, between `radius - width` and `radius`; null for no fill.
static func build_arc(radius: float, width: float, fill: float) -> ArrayMesh:
	if fill <= 0.0:
		return null
	var steps: int = maxi(1, ceili(RING_SEGMENTS * minf(fill, 1.0)))
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for step: int in steps + 1:
		var angle: float = TAU * minf(fill, 1.0) * float(step) / float(steps)
		var outward: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(outward * (radius - width))
		vertices.append(outward * radius)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return mesh


## A number key within its range, or the reason it is not.
static func check_number(field: String, value: Variant, limits: Array) -> String:
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "\"%s\" must be a number" % field
	if float(value) < float(limits[0]) or float(value) > float(limits[1]):
		return "\"%s\" is %s, must be within %s..%s" % [field, value, limits[0], limits[1]]
	return ""


## `[r, g, b]` within 0..1 as a `Color`, or a String naming `field`.
static func parse_color(field: String, value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "\"%s\" must be [red, green, blue]" % field
	for part: Variant in value:
		if (typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT) or float(part) < 0.0 or float(part) > 1.0:
			return "\"%s\" must hold numbers within 0..1" % field
	return Color(float(value[0]), float(value[1]), float(value[2]))


static func _parse_entry(part: String, entry: Variant, keys: Array[String]) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"error": "key \"%s\" must be an object" % part}
	var data: Dictionary = entry
	for key: Variant in data:
		if not keys.has(key):
			return {"error": "\"%s\" has unknown key \"%s\"" % [part, str(key)]}
	var look: Dictionary = {}
	for key: String in keys:
		var field: String = "%s.%s" % [part, key]
		if not data.has(key):
			return {"error": "\"%s\" is missing" % field}
		if key.ends_with("color"):
			var color: Variant = parse_color(field, data[key])
			if typeof(color) == TYPE_STRING:
				return {"error": color}
			look[key] = color
		else:
			var problem: String = check_number(field, data[key], RANGES[key])
			if problem != "":
				return {"error": problem}
			look[key] = float(data[key])
	return look


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# Emissive so the marker reads in the dark with no light on it (LGT-1).
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	# The band is flat; it must show from either side.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Rebuilds the fill band only when the fill changed, since a held miner
## changes it every tick and a waiting one never does.
func _set_fill(index: int, fill: float) -> void:
	if is_equal_approx(_fills[index], fill):
		return
	_fills[index] = fill
	var band: MeshInstance3D = _markers[index].get_node("Ring/Fill") as MeshInstance3D
	var ring: Dictionary = _look["ring"]
	# Laid just inside the track so the two never fight for the same pixels.
	var mesh: ArrayMesh = build_arc(float(ring["radius"]) * 0.995, ring["width"], fill)
	if mesh != null:
		mesh.surface_set_material(0, _fill_material)
	band.mesh = mesh


func _add_marker() -> void:
	var marker: Node3D = Node3D.new()
	marker.name = "%s%d" % [MARKER_PREFIX, _markers.size()]
	marker.visible = false
	var beacon: MeshInstance3D = MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = _beacon_mesh
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(beacon)
	var ring: Node3D = Node3D.new()
	ring.name = "Ring"
	marker.add_child(ring)
	for part: String in ["Track", "Fill"]:
		var band: MeshInstance3D = MeshInstance3D.new()
		band.name = part
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(band)
	(ring.get_node("Track") as MeshInstance3D).mesh = _track_mesh
	_pod.dress(marker)
	add_child(marker)
	_markers.append(marker)
	_fills.append(0.0)
