extends RefCounted

## The six robot types read apart (#638, CMB-3, ARC-4): every data file has a
## look of its own with parts beyond its body and an eye on its facing, no two
## outlines share their proportions, and the optional tell keys parse, keep
## their defaults and reject bad values naming the field.

const LOOK_FILE: String = "res://view/robot_look.json"
const ROBOTS_DIR: String = "res://data/robots"
## Least difference between two outlines' unit proportion vectors. 0.15 is
## about a fifth more length against height, enough to tell at 20 m.
const MIN_PROPORTION_GAP: float = 0.15


func _shipped() -> Dictionary:
	return RobotLook.parse(FileAccess.get_file_as_string(LOOK_FILE))


func _robot_ids() -> Array[String]:
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids


func _radius(id: String) -> float:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id])).radius


## Half extents of the outline in metres: body and parts, each a unit shape.
func _outline(look: Dictionary, radius: float) -> Vector3:
	var half: Vector3 = look["stretch"]
	for part: Dictionary in look["parts"]:
		half = half.max((part["offset"] as Vector3).abs() + (part["size"] as Vector3))
	return half * radius * float(look["scale"])


func test_every_robot_type_has_a_silhouette_of_its_own() -> String:
	var parsed: Dictionary = _shipped()
	if parsed.has("error"):
		return "shipped look rejected: %s" % parsed["error"]
	var robots: Dictionary = parsed["robots"]
	for id: String in _robot_ids():
		if not robots.has(id):
			return "robot_look.json has no entry for \"%s\"" % id
		var look: Dictionary = robots[id]
		if (look["parts"] as Array).size() < 2:
			return "\"%s\" has fewer than two parts beyond its body" % id
		var eyes: int = 0
		for part: Dictionary in look["parts"]:
			if part["eye"] and (part["offset"] as Vector3).z < 0.0:
				eyes += 1
		if eyes == 0:
			return "\"%s\" has no eye on its facing (-z), so its face side does not show" % id
		# A metre at 20 m is about 2.9 degrees, dozens of pixels on the headset.
		var outline: Vector3 = _outline(look, _radius(id))
		if outline[outline.max_axis_index()] * 2.0 < 1.0:
			return "\"%s\" is under a metre across" % id
	return ""


func test_no_two_outlines_share_their_proportions() -> String:
	var robots: Dictionary = _shipped()["robots"]
	var ids: Array[String] = _robot_ids()
	var shapes: Dictionary[String, Vector3] = {}
	for id: String in ids:
		shapes[id] = _outline(robots[id], _radius(id)).normalized()
	for a: int in ids.size():
		for b: int in range(a + 1, ids.size()):
			var gap: float = shapes[ids[a]].distance_to(shapes[ids[b]])
			if gap < MIN_PROPORTION_GAP:
				return "\"%s\" and \"%s\" outlines differ by %.3f in proportion, under %.2f" % [
					ids[a], ids[b], gap, MIN_PROPORTION_GAP]
	return ""


func test_each_new_type_shows_its_behaviour() -> String:
	var robots: Dictionary = _shipped()["robots"]
	var glider: Dictionary = robots["glider"]["tell"]
	var needler: Dictionary = robots["needler"]["tell"]
	var skimmer: Dictionary = robots["skimmer"]["tell"]
	var warden: Dictionary = robots["warden"]["tell"]
	if float(glider["roll_deg_per_mps"]) <= float(glider["pitch_deg_per_mps"]) or float(glider["max_deg"]) < 30.0:
		return "the glider, a strafer, does not bank hard into its circle"
	if float(needler["pitch_deg_per_mps"]) <= float(needler["roll_deg_per_mps"]) or float(needler["max_deg"]) < 20.0:
		return "the needler, a chaser, does not dive nose down as it closes"
	if float(skimmer["yaw_deg_per_mps"]) <= 0.0 or float(skimmer["roll_deg_per_mps"]) != 0.0:
		return "the skimmer does not skid flat around its target"
	if float(warden["max_deg"]) != 0.0 or float(warden["watch_dim"]) < 0.5:
		return "the warden does not hold still and glare while it sees the pilot"
	return ""


func _look_with_tell(tell: Dictionary) -> Dictionary:
	var plain: Dictionary = {"shape": "box", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5]}
	var entry: Dictionary = plain.duplicate()
	entry["tell"] = tell
	return {"default": plain, "robots": {"skimmer": entry}}


func test_optional_tell_keys_parse_default_and_reject_bad_values() -> String:
	var base: Dictionary = {"pitch_deg_per_mps": 1.0, "roll_deg_per_mps": 1.0, "max_deg": 20.0}
	var parsed: Dictionary = RobotLook.parse(JSON.stringify(_look_with_tell(base)))
	if parsed.has("error"):
		return "a tell without the optional keys was rejected: %s" % parsed["error"]
	var tell: Dictionary = parsed["robots"]["skimmer"]["tell"]
	if float(tell["yaw_deg_per_mps"]) != 0.0 or float(tell["watch_dim"]) != 0.0:
		return "missing optional tell keys did not default to 0: %s" % tell
	var full: Dictionary = base.duplicate()
	full["yaw_deg_per_mps"] = 2.0
	full["watch_dim"] = 0.5
	parsed = RobotLook.parse(JSON.stringify(_look_with_tell(full)))
	if parsed.has("error") or float(parsed["robots"]["skimmer"]["tell"]["yaw_deg_per_mps"]) != 2.0:
		return "optional tell keys not read"
	var cases: Array[Array] = [
		["yaw_deg_per_mps", 11.0], ["watch_dim", 1.5], ["watch_dim", true], ["yaw_deg_per_mps", -1.0],
	]
	for case: Array in cases:
		var bad: Dictionary = base.duplicate()
		bad[case[0]] = case[1]
		var result: Dictionary = RobotLook.parse(JSON.stringify(_look_with_tell(bad)))
		var field: String = "robots.skimmer.tell.%s" % case[0]
		if not result.has("error"):
			return "accepted %s = %s" % [case[0], case[1]]
		if not String(result["error"]).contains(field):
			return "error \"%s\" does not name \"%s\"" % [result["error"], field]
	return ""
