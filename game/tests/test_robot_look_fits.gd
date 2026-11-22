extends RefCounted

## Every robot's drawn model stays inside its collision sphere (#1225, GEN-3,
## GEN-5, ARC-4): the simulation keeps a robot's centre one `radius` off every
## wall, so a wing or fin drawn further out shows through the wall into the next
## tunnel. Checked on the data files, so a new robot type or part is held to it
## too.

const LOOK_FILE: String = "res://view/robot_look.json"
const ROBOTS_DIR: String = "res://data/robots"
## The glider as `robot_look.json` drew it before #1225: wingtip pods 1.85
## units out, at scale 1.0, about 2.1 radii from its centre.
const OLD_GLIDER: Dictionary = {
	"shape": "box", "scale": 1.0, "emission_color": [0.1, 0.85, 1.0],
	"stretch": [0.3, 0.25, 1.1],
	"parts": [
		{"shape": "box", "size": [1.9, 0.05, 0.45], "offset": [0.0, 0.0, 0.25]},
		{"shape": "box", "size": [0.05, 0.45, 0.3], "offset": [0.0, 0.45, 0.8]},
		{"shape": "box", "size": [0.12, 0.25, 0.12], "offset": [-1.85, -0.2, 0.35]},
		{"shape": "box", "size": [0.12, 0.25, 0.12], "offset": [1.85, -0.2, 0.35]},
		{"shape": "sphere", "size": [0.18, 0.14, 0.18], "offset": [0.0, 0.08, -1.05], "eye": true},
	],
}


func _robot_ids() -> Array[String]:
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids


func _parse(robots: Dictionary) -> Dictionary:
	var plain: Dictionary = {"shape": "sphere", "scale": 1.0, "emission_color": [0.5, 0.5, 0.5]}
	return RobotLook.parse(JSON.stringify({"default": plain, "robots": robots}))


func test_every_shipped_robot_fits_inside_its_radius() -> String:
	var parsed: Dictionary = RobotLook.parse(FileAccess.get_file_as_string(LOOK_FILE))
	if parsed.has("error"):
		return "shipped look rejected: %s" % parsed["error"]
	var robots: Dictionary = parsed["robots"]
	var ids: Array[String] = _robot_ids()
	if ids.size() < 6:
		return "only %d robot data files found" % ids.size()
	for id: String in ids:
		var look: Dictionary = robots.get(id, parsed["default"])
		var why: String = RobotLookReach.misfit(id, look)
		if why != "":
			return why
	return ""


func test_the_old_glider_is_caught_naming_robot_and_part() -> String:
	var parsed: Dictionary = _parse({"glider": OLD_GLIDER})
	if parsed.has("error"):
		return "old glider rejected: %s" % parsed["error"]
	var why: String = RobotLookReach.misfit("glider", parsed["robots"]["glider"])
	if why == "":
		return "the old glider, wings 2.1 radii out, passed"
	if not why.contains("\"glider\"") or not why.contains("parts."):
		return "the failure does not name the robot and part: %s" % why
	return ""


func test_a_scale_over_one_is_caught() -> String:
	var entry: Dictionary = {"shape": "sphere", "scale": 1.2, "emission_color": [0.5, 0.5, 0.5],
			"stretch": [0.5, 0.5, 0.5]}
	var why: String = RobotLookReach.misfit("drone", _parse({"drone": entry})["robots"]["drone"])
	return "" if why.contains("scale") else "a scale of 1.2 passed: \"%s\"" % why


func test_reach_of_each_unit_shape() -> String:
	var cases: Array[Array] = [
		["box", Vector3.ONE, Vector3.ZERO, sqrt(3.0)],
		["sphere", Vector3(0.5, 0.5, 2.0), Vector3.ZERO, 2.0],
		["sphere", Vector3(0.1, 0.1, 0.25), Vector3(0, 0, -0.75), 1.0],
		["cylinder", Vector3.ONE, Vector3.ZERO, sqrt(2.0)],
		["cone", Vector3(0.5, 0.5, 0.5), Vector3(0, 1, 0), 1.5],
		["torus", Vector3.ONE, Vector3.ZERO, 1.0],
		["capsule", Vector3.ONE, Vector3.ZERO, 1.0],
		["prism", Vector3.ONE, Vector3.ZERO, sqrt(3.0)],
	]
	for case: Array in cases:
		var got: float = RobotLookReach.piece_reach(case[0], case[1], case[2])
		if absf(got - float(case[3])) > 1e-4:
			return "%s of size %s at %s reaches %.4f, expected %.4f" % [case[0], case[1], case[2], got, case[3]]
	return ""
