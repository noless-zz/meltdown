extends RefCounted

## The PRF-8 stress scene (#1288): its data files load with the counts PRF-8
## names, its four ships are flown by their scripts, it is deterministic, the
## meltdown is running, and `core/` holds no code for it (ARC-1, ARC-2, ARC-4).

const LEVEL_PATH: String = "res://data/levels/stress_level.json"
const REPLAY_PATH: String = "res://acceptance/replays/stress_scene.replay"
const MODULES_DIR: String = "res://data/modules/"
const CORE_DIR: String = "res://core/"
const TICKS: int = 300


static func _scene() -> StressScene:
	return StressScene.load_file()


func test_the_scene_file_loads_with_four_ships_and_eight_lights() -> String:
	var scene: StressScene = _scene()
	if scene.error != "":
		return "stress scene rejected: %s" % scene.error
	if scene.ship_count() != 4 or scene.scripts.size() != 4:
		return "%d ships and %d scripts" % [scene.ship_count(), scene.scripts.size()]
	if scene.lights.size() != 8:
		return "%d lights" % scene.lights.size()
	if scene.level_path() != LEVEL_PATH or LevelSwitch.requested(PackedStringArray(["--level=stress"]), "") != scene.level_name:
		return "the scene flies %s, not what --level=stress loads" % scene.level_path()
	return ""


func test_the_level_holds_twenty_robots_of_mixed_types() -> String:
	var level: LevelDef = LevelSwitch.load_level(LEVEL_PATH)
	if level == null:
		return "stress level rejected"
	var replay: Replay = _scene().replay(1)
	if level.robots.spawns.size() != 20 or replay.robots.size() != 20:
		return "%d robots in the file, %d resolved" % [level.robots.spawns.size(), replay.robots.size()]
	var kinds: Dictionary[String, int] = {}
	for spawn: RobotSpawn in replay.robots:
		kinds[spawn.id] = kinds.get(spawn.id, 0) + 1
	if kinds.size() < 6:
		return "only %d robot types: %s" % [kinds.size(), kinds]
	if level.reactor == null:
		return "the level has no reactor, so no meltdown"
	return ""


func test_the_walls_are_the_largest_room_module() -> String:
	var largest: String = ""
	var largest_volume: float = 0.0
	for file: String in DirAccess.get_files_at(MODULES_DIR):
		if not file.ends_with(".json"):
			continue
		var module: ModuleDef = ModuleDef.parse_json(FileAccess.get_file_as_string(MODULES_DIR + file))
		var volume: float = 0.0
		for box: BoxBounds in module.boxes:
			var size: Vector3 = box.max_corner - box.min_corner
			volume += size.x * size.y * size.z
		if volume > largest_volume:
			largest_volume = volume
			largest = module.id
	var scene: StressScene = _scene()
	if scene.module_id != largest:
		return "the scene names %s; the largest module is %s" % [scene.module_id, largest]
	var level: LevelDef = LevelSwitch.load_level(LEVEL_PATH)
	var boxes: Array[BoxBounds] = scene.module_boxes()
	if level == null or boxes.size() != level.union.boxes.size():
		return "the level's walls are not %s's boxes" % largest
	for index: int in boxes.size():
		if not boxes[index].min_corner.is_equal_approx(level.union.boxes[index].min_corner) \
				or not boxes[index].max_corner.is_equal_approx(level.union.boxes[index].max_corner):
			return "box %d differs from %s's" % [index, largest]
	return ""


func test_four_ships_are_deterministic_over_300_ticks() -> String:
	var scene: StressScene = _scene()
	var first: Sim = scene.replay(TICKS).run()
	var second: Sim = scene.replay(TICKS).run()
	if first == null or second == null:
		return "the scene's replay did not run"
	if first.ships.size() != 4:
		return "%d ships flown" % first.ships.size()
	if first.state_hash() != second.state_hash():
		return "two runs gave %d and %d" % [first.state_hash(), second.state_hash()]
	# Through its text too, as a recorded scene would be flown again.
	var reread: Sim = Replay.from_text(scene.replay(TICKS).to_text()).run()
	if reread == null or reread.state_hash() != first.state_hash():
		return "the replay's text runs to another hash"
	for index: int in first.ships.size():
		var ship: ShipState = first.ships[index]
		if ship.is_destroyed() or ship.position.distance_to(first.start_positions[index]) < 1.0:
			return "ship %d was destroyed or never left its start" % index
	return ""


func test_the_meltdown_is_running_after_300_ticks() -> String:
	var sim: Sim = _scene().replay(TICKS).run()
	if sim.reactor == null or not sim.reactor.destroyed:
		return "the reactor is still intact after %d ticks" % TICKS
	if sim.reactor.meltdown_ticks_left <= 0 or sim.outcome() != ExitRule.Outcome.RUNNING:
		return "the meltdown is over: %d ticks left, outcome %d" % [sim.reactor.meltdown_ticks_left, sim.outcome()]
	return ""


func test_the_step_replay_is_the_scenes_four_ships() -> String:
	var shipped: Replay = Replay.load_file(REPLAY_PATH)
	if shipped.error != "":
		return "%s: %s" % [REPLAY_PATH, shipped.error]
	var built: Replay = _scene().replay(shipped.frames.size())
	if shipped.to_text() != built.to_text():
		return "%s no longer matches StressScene.replay(%d); write it again" % [REPLAY_PATH, shipped.frames.size()]
	if shipped.ship_count != 4:
		return "the step's replay flies %d ships" % shipped.ship_count
	# Long enough for the step's 2 s settle and 60 s measurement at 90 Hz.
	if shipped.frames.size() < 62 * 90:
		return "the replay is %d ticks" % shipped.frames.size()
	var sim: Sim = shipped.run()
	for index: int in sim.ships.size():
		if sim.ships[index].is_destroyed():
			return "ship %d is lost by the replay's end" % index
	if sim.reactor.meltdown_ticks_left <= 0:
		return "the meltdown is over by the replay's end"
	return ""


func test_only_the_stress_level_gets_the_scene_lights() -> String:
	if StressScene.lights_for(LEVEL_PATH).size() != 8:
		return "--level=stress gets %d lights" % StressScene.lights_for(LEVEL_PATH).size()
	for other: String in ["res://data/levels/g2_level.json", "seed:29", ""]:
		if not StressScene.lights_for(other).is_empty():
			return "%s gets scene lights" % other
	return ""


func test_scene_lights_are_drawn_without_shadows_and_replaced() -> String:
	var parent: Node3D = Node3D.new()
	var lights: Array[Dictionary] = _scene().lights
	SceneLights.place(parent, lights)
	SceneLights.place(parent, lights)
	var node: Node = parent.get_node_or_null(SceneLights.NODE_NAME)
	var problem: String = ""
	if node == null or SceneLights.count(parent) != 8 or parent.get_child_count() != 1:
		problem = "%d lights under %d nodes" % [SceneLights.count(parent), parent.get_child_count()]
	else:
		for lamp: Node in node.get_children():
			if not lamp is OmniLight3D or (lamp as OmniLight3D).shadow_enabled:
				problem = "a scene light is not a shadowless omni light"
	var empty: Array[Dictionary] = []
	if problem == "" and (SceneLights.place(parent, empty) != null or SceneLights.count(parent) != 0):
		problem = "no lights left lights drawn"
	parent.free()
	return problem


func test_core_holds_no_stress_scene_code() -> String:
	for file: String in DirAccess.get_files_at(CORE_DIR):
		if file.ends_with(".gd") and FileAccess.get_file_as_string(CORE_DIR + file).to_lower().contains("stress"):
			return "core/%s mentions the stress scene" % file
	return ""
