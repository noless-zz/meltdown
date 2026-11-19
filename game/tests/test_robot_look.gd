extends RefCounted

## The robot look file (#604, CMB-3, ARC-4): silhouette parts, the lean tell
## and the hit, damage and burst effects parse, fall back to defaults, reject
## bad values naming the field, and the shipped drone and hauler differ in
## outline, not colour alone.

const LOOK_FILE: String = "res://view/robot_look.json"
const ROBOTS_DIR: String = "res://data/robots"


func _valid_entry() -> Dictionary:
	return {"shape": "box", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5]}


func _valid_look() -> Dictionary:
	var drone: Dictionary = _valid_entry()
	drone["stretch"] = [1.0, 0.5, 1.5]
	drone["parts"] = [{"shape": "torus", "size": [1.5, 0.5, 1.5], "offset": [0.0, 0.0, 0.0]},
		{"shape": "sphere", "size": [0.2, 0.2, 0.2], "offset": [0.0, 0.0, -1.0], "eye": true}]
	drone["eye_color"] = [1.0, 1.0, 0.5]
	drone["tell"] = {"pitch_deg_per_mps": 3.0, "roll_deg_per_mps": 1.0, "max_deg": 20.0}
	return {"default": _valid_entry(), "robots": {"drone": drone}, "effects": {"hit_flash_seconds": 0.2}}


func _shipped() -> Dictionary:
	return RobotLook.parse(FileAccess.get_file_as_string(LOOK_FILE))


func test_new_fields_parse_and_missing_ones_take_defaults() -> String:
	var parsed: Dictionary = RobotLook.parse(JSON.stringify(_valid_look()))
	if parsed.has("error"):
		return "valid look rejected: %s" % parsed["error"]
	var drone: Dictionary = parsed["robots"]["drone"]
	if drone["stretch"] != Vector3(1.0, 0.5, 1.5) or (drone["parts"] as Array).size() != 2:
		return "stretch or parts not read: %s" % [drone]
	if not drone["parts"][1]["eye"] or drone["parts"][0]["eye"]:
		return "eye flags read wrong"
	if float(drone["tell"]["max_deg"]) != 20.0:
		return "tell not read"
	var plain: Dictionary = parsed["default"]
	if plain["stretch"] != Vector3.ONE or not (plain["parts"] as Array).is_empty() \
			or float(plain["tell"]["max_deg"]) != 0.0:
		return "an entry without the new keys did not get the defaults"
	var effects: Dictionary = parsed["effects"]
	if float(effects["hit_flash_seconds"]) != 0.2:
		return "effects value not read"
	if float(effects["damaged_below"]) != float(RobotLook.DEFAULT_EFFECTS["damaged_below"]):
		return "a missing effects key did not keep its default"
	var bare: Dictionary = _valid_look()
	bare.erase("effects")
	if RobotLook.parse(JSON.stringify(bare)).has("error"):
		return "a look without effects was rejected"
	return ""


func test_bad_values_are_rejected_with_the_field_named() -> String:
	var cases: Array[Array] = []
	var look: Dictionary = _valid_look()
	look["robots"]["drone"]["parts"][0]["shape"] = "pyramid"
	cases.append([look, "robots.drone.parts.0.shape"])
	look = _valid_look()
	look["robots"]["drone"]["parts"][1]["size"] = [0.2, 0.2]
	cases.append([look, "robots.drone.parts.1.size"])
	look = _valid_look()
	look["robots"]["drone"]["parts"][1]["offset"] = [0.0, 9.0, 0.0]
	cases.append([look, "robots.drone.parts.1.offset"])
	look = _valid_look()
	look["robots"]["drone"]["parts"][1]["eye"] = 1
	cases.append([look, "robots.drone.parts.1.eye"])
	look = _valid_look()
	look["robots"]["drone"]["parts"][0]["spin"] = 1.0
	cases.append([look, "spin"])
	look = _valid_look()
	look["robots"]["drone"]["stretch"] = [1.0, 0.0, 1.0]
	cases.append([look, "robots.drone.stretch"])
	look = _valid_look()
	look["robots"]["drone"]["tell"]["max_deg"] = 90.0
	cases.append([look, "robots.drone.tell.max_deg"])
	look = _valid_look()
	look["robots"]["drone"]["tell"].erase("roll_deg_per_mps")
	cases.append([look, "roll_deg_per_mps"])
	look = _valid_look()
	look["effects"]["damaged_flicker_period"] = 0.1
	cases.append([look, "effects.damaged_flicker_period"])
	look = _valid_look()
	look["effects"]["burst_color"] = [1.0, 1.0, 2.0]
	cases.append([look, "effects.burst_color"])
	look = _valid_look()
	look["effects"]["sparkle"] = 1.0
	cases.append([look, "sparkle"])
	for case: Array in cases:
		var parsed: Dictionary = RobotLook.parse(JSON.stringify(case[0]))
		if not parsed.has("error"):
			return "accepted a look with a bad \"%s\"" % case[1]
		if not String(parsed["error"]).contains(case[1]):
			return "error \"%s\" does not name \"%s\"" % [parsed["error"], case[1]]
	return ""


func test_shipped_file_parses_with_effects() -> String:
	var parsed: Dictionary = _shipped()
	if parsed.has("error"):
		return "shipped look rejected: %s" % parsed["error"]
	var effects: Dictionary = parsed["effects"]
	if float(effects["damaged_below"]) != 0.5:
		return "damage state does not start below half hull"
	if float(effects["hit_flash_seconds"]) > 0.25:
		return "hit flash of %s s outlasts a quick burst of hits" % effects["hit_flash_seconds"]
	return ""


## Half extents of the outline in metres: body and parts, each a unit shape.
func _outline(look: Dictionary, radius: float) -> Vector3:
	var half: Vector3 = look["stretch"]
	for part: Dictionary in look["parts"]:
		var offset: Vector3 = part["offset"]
		half = half.max(offset.abs() + (part["size"] as Vector3))
	return half * radius * float(look["scale"])


func test_drone_and_hauler_differ_in_outline() -> String:
	var parsed: Dictionary = _shipped()
	var drone: Dictionary = parsed["robots"]["drone"]
	var hauler: Dictionary = parsed["robots"]["hauler"]
	for pair: Array in [["drone", drone], ["hauler", hauler]]:
		if (pair[1]["parts"] as Array).size() < 2:
			return "%s has fewer than two parts beyond its body" % pair[0]
	if drone["shape"] == hauler["shape"]:
		return "drone and hauler share a body shape"
	var drone_size: Vector3 = _outline(drone, _radius("drone"))
	var hauler_size: Vector3 = _outline(hauler, _radius("hauler"))
	# Length over height, seen side on: a squat ring against a long low hull.
	var drone_ratio: float = drone_size.z / drone_size.y
	var hauler_ratio: float = hauler_size.z / hauler_size.y
	if hauler_ratio < drone_ratio * 1.5:
		return "length to height %.2f (hauler) against %.2f (drone): too alike" % [hauler_ratio, drone_ratio]
	# A metre at 20 m is about 2.9 degrees, dozens of pixels on the headset.
	if minf(drone_size.x, hauler_size.x) * 2.0 < 1.0:
		return "an outline is under a metre wide"
	return ""


func test_hauler_tell_and_drone_eye() -> String:
	var parsed: Dictionary = _shipped()
	var hauler: Dictionary = parsed["robots"]["hauler"]
	if float(hauler["tell"]["pitch_deg_per_mps"]) <= 0.0 or float(hauler["tell"]["max_deg"]) < 10.0:
		return "the hauler, a chaser, does not lean in as it closes"
	var eyes: int = 0
	for part: Dictionary in parsed["robots"]["drone"]["parts"]:
		if part["eye"] and (part["offset"] as Vector3).z < 0.0:
			eyes += 1
	if eyes != 1:
		return "the drone needs one eye on its facing (-z), found %d" % eyes
	return ""


func _radius(id: String) -> float:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))
	return def.radius
