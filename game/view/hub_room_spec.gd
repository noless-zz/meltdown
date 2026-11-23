class_name HubRoomSpec
extends RefCounted

## Parses `res://data/hub/room.json`, the home base room (#1298, CRW-2, ARC-4,
## ARC-5, GFX-4, decision record 0012). Every position is in metres from the
## seated pilot's eye point, forward as -z, so reach is measured from the seat:
##
##     {"size_m": [w, h, d], "materials": {name: material}, "surfaces":
##      {"walls": name, "floor": name, "ceiling": name}, "lights": [light],
##      "stations": [station], ... optional keys below}
##
## A material is {"color": [r, g, b], "metallic": 0..1, "roughness": 0..1,
## "emission": [r, g, b], "emission_energy": 0..8}; only `color` is required.
## A prop is {"id", "shape": one of SHAPES, "size_m", "position_m",
## "rotation_deg", "material"}. A light is {"position_m", "color", "energy",
## "range_m"}. A station is {"id": one of STATION_IDS, "label", "position_m",
## "screen"}; `position_m` is its screen's centre. Each task the hub pages do
## has exactly one station, and each must sit in front of the seat within
## `max_station_distance_m` and `max_station_yaw_deg` of straight ahead, so
## nothing needs the body turned (CMF-11). Only primitives, no image files.

const DEFAULT_FILE: String = "res://data/hub/room.json"
const STATION_IDS: Array[String] = ["craft", "fit", "crew", "logbook", "resume", "launch"]
const SHAPES: Array[String] = ["box", "cylinder", "sphere", "capsule", "prism"]
const SURFACES: Array[String] = ["walls", "floor", "ceiling"]
## GFX-4: at most 8 dynamic lights in view.
const MAX_LIGHTS: int = 8
const REQUIRED: Array[String] = ["size_m", "materials", "surfaces", "lights", "stations"]
## Optional top-level keys and their defaults.
const DEFAULTS: Dictionary = {
	"eye_height_m": 1.2,
	"centre_m": [0.0, -1.5],
	"max_station_distance_m": 1.6,
	"max_station_yaw_deg": 60.0,
	"background_color": [0.02, 0.02, 0.03],
	"ambient_color": [0.5, 0.55, 0.6],
	"ambient_energy": 0.35,
	"props": [],
}
const MATERIAL_DEFAULTS: Dictionary = {"metallic": 0.0, "roughness": 0.8, "emission": [0.0, 0.0, 0.0],
	"emission_energy": 0.0}
const DEFAULT_SCREEN: String = "screen"
const DEFAULT_CONSOLE: String = "console"

## Why the file was rejected, naming the field, or "".
var error: String = ""
var size: Vector3 = Vector3.ZERO
## Seat eye height above the floor.
var eye_height: float = 1.2
## The floor's centre in plan (x, z) from the eye point.
var centre: Vector2 = Vector2.ZERO
var max_station_distance: float = 1.6
var max_station_yaw_deg: float = 60.0
var background_color: Color = Color.BLACK
var ambient_color: Color = Color.WHITE
var ambient_energy: float = 0.0
## name -> {"color": Color, "metallic": float, "roughness": float, "emission": Color, "emission_energy": float}
var materials: Dictionary = {}
## "walls"/"floor"/"ceiling" -> material name.
var surfaces: Dictionary = {}
## Each {"id", "shape", "size": Vector3, "position": Vector3, "rotation": Vector3 (degrees), "material"}.
var props: Array[Dictionary] = []
## Each {"position": Vector3, "color": Color, "energy": float, "range": float}.
var lights: Array[Dictionary] = []
## Each {"id", "label", "position": Vector3, "screen": material name, "console": material name}.
var stations: Array[Dictionary] = []


static func load_shipped(path: String = DEFAULT_FILE) -> HubRoomSpec:
	if not FileAccess.file_exists(path):
		var missing: HubRoomSpec = HubRoomSpec.new()
		missing.error = "no room file at %s" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> HubRoomSpec:
	var spec: HubRoomSpec = HubRoomSpec.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		spec.error = "the room file is not a JSON object"
		return spec
	spec.error = spec._read(parsed)
	return spec


## "" when the station at `position` is in front of the seat and within the
## distance and yaw limits; otherwise why not.
func reach_problem(position: Vector3) -> String:
	if position.z >= 0.0:
		return "not in front of the seat"
	if position.length() > max_station_distance + 0.0001:
		return "%.2f m from the eye, over %.2f m" % [position.length(), max_station_distance]
	var yaw: float = rad_to_deg(atan2(absf(position.x), -position.z))
	if yaw > max_station_yaw_deg + 0.0001:
		return "%.0f degrees off straight ahead, over %.0f" % [yaw, max_station_yaw_deg]
	return ""


func _read(data: Dictionary) -> String:
	for key: String in REQUIRED:
		if not data.has(key):
			return "missing key \"%s\"" % key
	for key: Variant in data:
		if not REQUIRED.has(key) and not DEFAULTS.has(key):
			return "unknown key \"%s\"" % str(key)
	var merged: Dictionary = DEFAULTS.duplicate(true)
	merged.merge(data, true)
	var problem: String = _read_numbers(merged)
	if problem == "":
		problem = _read_materials(merged["materials"], merged["surfaces"])
	if problem == "":
		problem = _read_props(merged["props"])
	if problem == "":
		problem = _read_lights(merged["lights"])
	if problem == "":
		problem = _read_stations(merged["stations"])
	return problem


func _read_numbers(data: Dictionary) -> String:
	if not HubRoomValues.is_vector(data["size_m"], 3, 0.5, 30.0):
		return "\"size_m\" must be [width, height, depth], each 0.5..30"
	size = HubRoomValues.vector3(data["size_m"])
	if not HubRoomValues.is_vector(data["centre_m"], 2, -30.0, 30.0):
		return "\"centre_m\" must be [x, z]"
	centre = Vector2(float(data["centre_m"][0]), float(data["centre_m"][1]))
	for key: String in ["eye_height_m", "max_station_distance_m", "max_station_yaw_deg", "ambient_energy"]:
		if not HubRoomValues.is_number(data[key], 0.0, 180.0):
			return "\"%s\" must be a number 0..180" % key
	eye_height = float(data["eye_height_m"])
	max_station_distance = float(data["max_station_distance_m"])
	max_station_yaw_deg = float(data["max_station_yaw_deg"])
	ambient_energy = float(data["ambient_energy"])
	for key: String in ["background_color", "ambient_color"]:
		if not HubRoomValues.is_vector(data[key], 3, 0.0, 1.0):
			return "\"%s\" must be [red, green, blue], each 0..1" % key
	background_color = HubRoomValues.color(data["background_color"])
	ambient_color = HubRoomValues.color(data["ambient_color"])
	return ""


func _read_materials(raw: Variant, raw_surfaces: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return "\"materials\" must be an object of named materials"
	for name: Variant in raw:
		var read: Variant = HubRoomValues.material(raw[name], MATERIAL_DEFAULTS)
		if typeof(read) == TYPE_STRING:
			return "materials.%s: %s" % [str(name), read]
		materials[str(name)] = read
	if typeof(raw_surfaces) != TYPE_DICTIONARY:
		return "\"surfaces\" must name a material for %s" % ", ".join(SURFACES)
	for surface: String in SURFACES:
		var problem: String = _known_material("surfaces.%s" % surface, (raw_surfaces as Dictionary).get(surface))
		if problem != "":
			return problem
		surfaces[surface] = str(raw_surfaces[surface])
	return ""


func _read_props(raw: Variant) -> String:
	if typeof(raw) != TYPE_ARRAY:
		return "\"props\" must be a list"
	for i: int in (raw as Array).size():
		var prop: Variant = raw[i]
		var field: String = "props[%d]" % i
		if typeof(prop) != TYPE_DICTIONARY or not SHAPES.has(str((prop as Dictionary).get("shape", ""))):
			return "%s: \"shape\" must be one of %s" % [field, ", ".join(SHAPES)]
		if not HubRoomValues.is_vector(prop.get("size_m"), 3, 0.01, 30.0):
			return "%s: \"size_m\" must be [x, y, z], each 0.01..30" % field
		if not HubRoomValues.is_vector(prop.get("position_m"), 3, -30.0, 30.0):
			return "%s: \"position_m\" must be [x, y, z]" % field
		var rotation: Variant = prop.get("rotation_deg", [0.0, 0.0, 0.0])
		if not HubRoomValues.is_vector(rotation, 3, -360.0, 360.0):
			return "%s: \"rotation_deg\" must be [x, y, z] in degrees" % field
		var problem: String = _known_material(field + ".material", prop.get("material"))
		if problem != "":
			return problem
		props.append({"id": str(prop.get("id", field)), "shape": str(prop["shape"]),
			"size": HubRoomValues.vector3(prop["size_m"]), "position": HubRoomValues.vector3(prop["position_m"]),
			"rotation": HubRoomValues.vector3(rotation), "material": str(prop["material"])})
	return ""


func _read_lights(raw: Variant) -> String:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() > MAX_LIGHTS:
		return "\"lights\" must be a list of at most %d lights (GFX-4)" % MAX_LIGHTS
	for i: int in (raw as Array).size():
		var light: Variant = raw[i]
		var field: String = "lights[%d]" % i
		if typeof(light) != TYPE_DICTIONARY or not HubRoomValues.is_vector(light.get("position_m"), 3, -30.0, 30.0):
			return "%s: \"position_m\" must be [x, y, z]" % field
		if not HubRoomValues.is_vector(light.get("color", [1.0, 1.0, 1.0]), 3, 0.0, 1.0):
			return "%s: \"color\" must be [red, green, blue], each 0..1" % field
		if not HubRoomValues.is_number(light.get("energy", 1.0), 0.0, 16.0) \
				or not HubRoomValues.is_number(light.get("range_m", 5.0), 0.1, 30.0):
			return "%s: \"energy\" must be 0..16 and \"range_m\" 0.1..30" % field
		lights.append({"position": HubRoomValues.vector3(light["position_m"]),
			"color": HubRoomValues.color(light.get("color", [1.0, 1.0, 1.0])),
			"energy": float(light.get("energy", 1.0)), "range": float(light.get("range_m", 5.0))})
	return ""


func _read_stations(raw: Variant) -> String:
	if typeof(raw) != TYPE_ARRAY:
		return "\"stations\" must be a list"
	var seen: Array[String] = []
	for i: int in (raw as Array).size():
		var station: Variant = raw[i]
		var field: String = "stations[%d]" % i
		var id: String = str((station as Dictionary).get("id", "")) if typeof(station) == TYPE_DICTIONARY else ""
		if not STATION_IDS.has(id) or seen.has(id):
			return "%s: \"id\" must be one of %s, each once" % [field, ", ".join(STATION_IDS)]
		seen.append(id)
		if not HubRoomValues.is_vector(station.get("position_m"), 3, -30.0, 30.0):
			return "%s: \"position_m\" must be [x, y, z]" % field
		var position: Vector3 = HubRoomValues.vector3(station["position_m"])
		var reach: String = reach_problem(position)
		if reach != "":
			return "%s (%s): %s" % [field, id, reach]
		for key: String in ["screen", "console"]:
			var problem: String = _known_material("%s.%s" % [field, key], station.get(key, key))
			if problem != "":
				return problem
		stations.append({"id": id, "label": str(station.get("label", id.capitalize())), "position": position,
			"screen": str(station.get("screen", DEFAULT_SCREEN)), "console": str(station.get("console", DEFAULT_CONSOLE))})
	for id: String in STATION_IDS:
		if not seen.has(id):
			return "\"stations\" has no \"%s\" station" % id
	return ""


func _known_material(field: String, name: Variant) -> String:
	if typeof(name) != TYPE_STRING or not materials.has(name):
		return "%s must name a material in \"materials\"" % field
	return ""
