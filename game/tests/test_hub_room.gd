extends RefCounted

## The home base room (#1298, CRW-2, CMF-11, GFX-4, ARC-3, ARC-4, ARC-5): it
## builds from the shipped file, every station is in front of the seat within
## reach, it has at most 8 lights, optional keys fall back to defaults, and the
## main scene's hub shows it on opening and hides it on launch.

const ROOM_FILE: String = "res://data/hub/room.json"
const FRAME: float = 1.0 / 90.0
const PROFILE_PATH: String = "user://t1298_profile.json"
const FITTING_PATH: String = "user://t1298_fitting.json"
## The issue's defaults: the shipped file may not loosen them.
const MAX_DISTANCE_M: float = 1.6
const MAX_YAW_DEG: float = 60.0


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ROOM_FILE))


func test_the_shipped_room_builds_with_six_stations() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	if spec.error != "":
		return "the shipped room is rejected: %s" % spec.error
	var room: HubRoom = HubRoom.new(spec)
	var points: Dictionary[String, Vector3] = room.station_points()
	var problem: String = ""
	for id: String in HubRoomSpec.STATION_IDS:
		if not points.has(id):
			problem = "no %s station" % id
	for wall: String in ["Floor", "Ceiling", "WallLeft", "WallRight", "WallFront", "WallBack"]:
		if room.get_node_or_null(wall) == null:
			problem = "no %s" % wall
	if spec.props.is_empty():
		problem = "the room has no props"
	if points.size() != 6:
		problem = "%d stations, expected 6" % points.size()
	room.free()
	return problem


func test_every_station_is_in_reach_of_the_seat() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	if spec.max_station_distance > MAX_DISTANCE_M or spec.max_station_yaw_deg > MAX_YAW_DEG:
		return "the room file loosens the reach limits"
	var room: HubRoom = HubRoom.new(spec)
	var problem: String = ""
	for id: String in room.station_points():
		var at: Vector3 = room.station_points()[id]
		var yaw: float = rad_to_deg(atan2(absf(at.x), -at.z))
		if at.z >= 0.0 or at.length() > MAX_DISTANCE_M or yaw > MAX_YAW_DEG:
			problem = "%s at %s: %.2f m, %.0f degrees" % [id, at, at.length(), yaw]
	room.free()
	return problem


func test_the_room_has_at_most_eight_lights_and_casts_no_shadows() -> String:
	var room: HubRoom = HubRoom.new()
	var problem: String = ""
	if room.light_count() < 1 or room.light_count() > 8:
		problem = "%d lights" % room.light_count()
	for child: Node in room.get_children():
		if child is Light3D and ((child as Light3D).shadow_enabled or (child as Light3D).light_cull_mask != HubRoom.LAYER_BIT):
			problem = "%s casts shadows or lights the mine" % child.name
	room.free()
	if problem != "":
		return problem
	var data: Dictionary = _shipped()
	var lights: Array = data["lights"]
	while lights.size() <= 8:
		lights.append(lights[0])
	var spec: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(data))
	return "" if spec.error.contains("at most 8") else "nine lights were accepted: %s" % spec.error


func test_every_part_is_drawn_on_the_room_layer_only() -> String:
	var room: HubRoom = HubRoom.new()
	var problem: String = ""
	var pending: Array[Node] = [room]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is VisualInstance3D and not node is Light3D and (node as VisualInstance3D).layers != HubRoom.LAYER_BIT:
			problem = "%s is on layers %d" % [node.name, (node as VisualInstance3D).layers]
	room.free()
	return problem


func test_a_missing_optional_key_falls_back_to_its_default() -> String:
	var data: Dictionary = _shipped()
	for key: String in ["eye_height_m", "max_station_distance_m", "max_station_yaw_deg", "props", "ambient_energy"]:
		data.erase(key)
	(data["stations"][0] as Dictionary).erase("label")
	(data["materials"]["wall"] as Dictionary).erase("roughness")
	var spec: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(data))
	if spec.error != "":
		return "rejected without optional keys: %s" % spec.error
	if spec.eye_height != 1.2 or spec.max_station_distance != 1.6 or spec.max_station_yaw_deg != 60.0:
		return "defaults not used: eye %s, distance %s, yaw %s" % [spec.eye_height, spec.max_station_distance,
			spec.max_station_yaw_deg]
	if not spec.props.is_empty() or spec.ambient_energy != 0.35:
		return "props or ambient energy did not fall back"
	if spec.stations[0]["label"] != str(spec.stations[0]["id"]).capitalize():
		return "a missing label did not fall back to the station's name"
	if spec.materials["wall"]["roughness"] != 0.8:
		return "a missing roughness did not fall back"
	return ""


func test_a_station_out_of_reach_or_missing_is_rejected() -> String:
	var data: Dictionary = _shipped()
	(data["stations"][0] as Dictionary)["position_m"] = [0.0, 0.0, -2.5]
	var far: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(data))
	data = _shipped()
	(data["stations"][0] as Dictionary)["position_m"] = [1.2, -0.5, -0.4]
	var aside: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(data))
	data = _shipped()
	(data["stations"] as Array).pop_back()
	var missing: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(data))
	if far.error == "" or aside.error == "" or missing.error == "":
		return "accepted: far '%s', aside '%s', missing '%s'" % [far.error, aside.error, missing.error]
	var rejected: HubRoom = HubRoom.new(far)
	var shown: bool = rejected.show_for(null)
	rejected.free()
	return "a rejected room showed" if shown else ""


func test_unknown_keys_and_materials_are_rejected() -> String:
	var data: Dictionary = _shipped()
	data["texture"] = "res://wall.png"
	var unknown: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(data))
	data = _shipped()
	(data["props"][0] as Dictionary)["material"] = "gold"
	var no_material: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(data))
	if unknown.error == "" or no_material.error == "":
		return "accepted: unknown key '%s', unknown material '%s'" % [unknown.error, no_material.error]
	return ""


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


func _run_main() -> Node:
	_clean()
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var level_start: LevelStart = main.get("level_start")
	var run: RunWiring = RunWiring.new(12345, ProfileStore.new(PROFILE_PATH), func() -> int: return 77,
		"{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}", false)
	run.ship.fittings = FittingStore.new(FITTING_PATH)
	level_start.run = run
	level_start.source = run.level_source()
	(main.get("destroyed") as DestroyedWiring).escape.run = run
	main.call("restart_level")
	return main


func test_opening_the_hub_shows_the_room_and_launching_hides_it() -> String:
	var main: Node = _run_main()
	var result: String = _check_open_and_launch(main)
	main.free()
	_clean()
	return result


func _check_open_and_launch(main: Node) -> String:
	var hub: HubWiring = main.get("hub")
	var camera: Camera3D = main.get_node("XRRig/Camera") as Camera3D
	var flying_mask: int = camera.cull_mask
	var flying_environment: Environment = camera.environment
	if hub.room == null or hub.room.visible or hub.room.get_parent() != main.get_node("XRRig"):
		return "the room is not hidden under the rig while flying"
	var verdict: Array = _check_script().call("judge_open_room", main, hub, {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "opening: %s" % verdict[1]
	if camera.environment == null or camera.environment == flying_environment:
		return "the room's environment is not on the camera"
	if not hub.room.transform.is_equal_approx(RigViews.head_point(main.get("head_recentre"))):
		return "the room is not at the seat's head point"
	if not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_LAUNCH}) or hub.is_open():
		return "the launch row did not leave the hub: %s" % hub.panel.reason_text()
	if hub.room.visible or camera.cull_mask != flying_mask or camera.environment != flying_environment:
		return "launching left the room showing or the camera's view changed (mask %d)" % camera.cull_mask
	return ""


func _check_script() -> GDScript:
	return load("res://acceptance/checks/hub_room_check.gd") as GDScript
