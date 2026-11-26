class_name HubRoomLights
extends RefCounted

## The home base room's lights (#1298, #1369, GFX-4, GFX-5, ARC-4): read from
## the `lights` list of `data/hub/room.json` and built as Godot lights. A light
## is
##
##     {"role": one of ROLES, "type": "omni" or "spot", "position_m": [x, y, z],
##      "aim_m": [x, y, z], "angle_deg": 5..89, "color": [r, g, b],
##      "energy": 0..16, "range_m": 0.1..30}
##
## Only `position_m` is required. A spot shines from its position towards
## `aim_m` in a cone of `angle_deg` either side; `aim_m` is required for a spot.
## The role says what the light is for (a key, a fill, a practical such as a
## screen or the pad, or the ship's own light), so a test can find the ship's
## light without knowing its index. No light casts a shadow: GFX-4 keeps
## shadows for the player's headlight, and the room's even fill is the
## environment's ambient light, which costs nothing per pixel (GFX-5).

const TYPES: Array[String] = ["omni", "spot"]
const ROLES: Array[String] = ["key", "fill", "practical", "ship"]
const DEFAULT_ROLE: String = "practical"
const DEFAULT_ANGLE_DEG: float = 40.0


## The lights in `raw`, or a String naming the bad field.
static func parse(raw: Variant, max_lights: int) -> Variant:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() > max_lights:
		return "\"lights\" must be a list of at most %d lights (GFX-4)" % max_lights
	var lights: Array[Dictionary] = []
	for i: int in (raw as Array).size():
		var read: Variant = _parse_one(raw[i], "lights[%d]" % i)
		if typeof(read) == TYPE_STRING:
			return read
		lights.append(read)
	return lights


static func _parse_one(light: Variant, field: String) -> Variant:
	if typeof(light) != TYPE_DICTIONARY or not HubRoomValues.is_vector(light.get("position_m"), 3, -30.0, 30.0):
		return "%s: \"position_m\" must be [x, y, z]" % field
	if not HubRoomValues.is_vector(light.get("color", [1.0, 1.0, 1.0]), 3, 0.0, 1.0):
		return "%s: \"color\" must be [red, green, blue], each 0..1" % field
	if not HubRoomValues.is_number(light.get("energy", 1.0), 0.0, 16.0) \
			or not HubRoomValues.is_number(light.get("range_m", 5.0), 0.1, 30.0):
		return "%s: \"energy\" must be 0..16 and \"range_m\" 0.1..30" % field
	var type: String = str(light.get("type", "omni"))
	var role: String = str(light.get("role", DEFAULT_ROLE))
	if not TYPES.has(type) or not ROLES.has(role):
		return "%s: \"type\" must be one of %s and \"role\" one of %s" % [field, ", ".join(TYPES), ", ".join(ROLES)]
	var position: Vector3 = HubRoomValues.vector3(light["position_m"])
	var aim: Vector3 = position + Vector3.DOWN
	if type == "spot":
		if not HubRoomValues.is_vector(light.get("aim_m"), 3, -30.0, 30.0):
			return "%s: a spot needs \"aim_m\" [x, y, z]" % field
		aim = HubRoomValues.vector3(light["aim_m"])
		if aim.distance_to(position) < 0.01:
			return "%s: \"aim_m\" is the light's own position" % field
	if not HubRoomValues.is_number(light.get("angle_deg", DEFAULT_ANGLE_DEG), 5.0, 89.0):
		return "%s: \"angle_deg\" must be 5..89" % field
	return {"role": role, "type": type, "position": position, "aim": aim,
		"angle": float(light.get("angle_deg", DEFAULT_ANGLE_DEG)),
		"color": HubRoomValues.color(light.get("color", [1.0, 1.0, 1.0])),
		"energy": float(light.get("energy", 1.0)), "range": float(light.get("range_m", 5.0))}


## The light for `data`, named `Light<index>`, lighting only `layers`.
static func build(index: int, data: Dictionary, layers: int) -> Light3D:
	var made: Light3D = null
	if data["type"] == "spot":
		var spot: SpotLight3D = SpotLight3D.new()
		spot.spot_range = data["range"]
		spot.spot_angle = data["angle"]
		var forward: Vector3 = (data["aim"] as Vector3) - (data["position"] as Vector3)
		var up: Vector3 = Vector3.FORWARD if absf(forward.normalized().y) > 0.99 else Vector3.UP
		spot.transform = Transform3D(Basis.looking_at(forward, up), data["position"])
		made = spot
	else:
		var omni: OmniLight3D = OmniLight3D.new()
		omni.omni_range = data["range"]
		omni.position = data["position"]
		made = omni
	made.name = "Light%d" % index
	made.light_color = data["color"]
	made.light_energy = data["energy"]
	made.shadow_enabled = false  # GFX-4: shadows from the player's headlight only.
	made.light_cull_mask = layers  # The room's lights never light the mine.
	# A light is culled by the camera's mask like a mesh: off the room's layer,
	# a camera drawing the room alone drops it and the room is lit by ambient only.
	made.layers = layers
	made.set_meta("role", data["role"])
	return made


## True when `point` is inside the cone of the spot `data` and within its range.
static func spot_reaches(data: Dictionary, point: Vector3) -> bool:
	if data["type"] != "spot":
		return false
	var to_point: Vector3 = point - (data["position"] as Vector3)
	if to_point.length() > float(data["range"]):
		return false
	var forward: Vector3 = (data["aim"] as Vector3) - (data["position"] as Vector3)
	return rad_to_deg(forward.angle_to(to_point)) <= float(data["angle"])
