class_name StressScene
extends RefCounted

## The PRF-8 stress scene (#1288, G6): the largest room module, 20 robots of
## mixed types, 4 player ships, 8 dynamic lights and the meltdown running. It
## is data, not code (ARC-4): `data/levels/stress_level.json` is an ordinary
## level, flown alone with `--level=stress`, and `data/levels/stress_scene.json`
## adds what a level file has no key for: the three extra ships with their
## scripted inputs (no network), the lights, and the seed.
##
## The meltdown is not switched on by code either. The level's reactor has a
## small hull and sits straight ahead of the start, and ship 0's script flies
## forward out of the exit sphere firing, so the reactor dies within the first
## second and the countdown runs for the rest of the scene.
##
## `replay` builds the scene as a `Replay`: the session the main scene builds
## for the level (`LevelStart.level_session`: parts and aim), flown in the
## scene's ship file (`ship`, a tougher default ship so the robots do not end
## the scene before it is measured), with
## the ship count and the extra ships' starts added and every ship's scripted
## input for each tick. Running it twice gives the same hash (ARC-1, ARC-2).
##
## `core/` has no branch for any of this: the replay is run by `Replay.run`.

const SCENE_FILE: String = "res://data/levels/stress_scene.json"
const MODULES_DIR: String = "res://data/modules/"
const KEYS: Array[String] = ["level", "seed", "module", "ship", "ships", "inputs", "lights"]
const SHIP_KEYS: Array[String] = ["position", "facing"]
const LIGHT_KEYS: Array[String] = ["position", "color", "range", "energy"]
## Every ship has a start: the level's for ship 0, the file's for the others.
const SHIP_COUNT: int = 4

var level_name: String = ""
var run_seed: int = 0
## The room module the level's walls are taken from (`module_boxes`).
var module_id: String = ""
## The ship file every ship flies: the default ship with a hull and shield
## deep enough that 20 robots cannot end the scene before it is measured.
var ship_path: String = ""
## Starts of ships 1, 2 and 3, metres; ship 0 starts where the level says.
var ship_positions: Array[Vector3] = []
var ship_facings: Array[Vector3] = []
## One script per ship, ship 0 first.
var scripts: Array[StressInputs] = []
## Each light as {"position": Vector3, "color": Color, "range": float, "energy": float}.
var lights: Array[Dictionary] = []
## Why the file was rejected; empty when it was read.
var error: String = ""


static func load_file(path: String = SCENE_FILE) -> StressScene:
	if not FileAccess.file_exists(path):
		return _failed("%s: file not found" % path)
	return parse_json(FileAccess.get_file_as_string(path))


static func parse_json(text: String) -> StressScene:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var scene: StressScene = StressScene.new()
	scene.error = scene._read(json.data)
	return scene


## The scene file's lights when `path` is its level, so `--level=stress`
## draws them (`SceneLights`); empty for any other level or a rejected file.
static func lights_for(path: String, scene_path: String = SCENE_FILE) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if path == "" or path.begins_with(LevelSwitch.SEED_PREFIX):
		return none
	var scene: StressScene = load_file(scene_path)
	return scene.lights if scene.error == "" and scene.level_path() == path else none


## Number of ships the scene flies.
func ship_count() -> int:
	return ship_positions.size() + 1


## The level file `level_name` names, as `--level=` reads it.
func level_path() -> String:
	return LevelSwitch.path_for(level_name)


## Every ship's input for `tick`, ship 0 first.
func inputs_at(tick: int) -> Array[ShipInput]:
	var inputs: Array[ShipInput] = []
	for script: StressInputs in scripts:
		inputs.append(script.input_at(tick))
	return inputs


## The scene as a replay of `ticks` ticks for its first `ships` ships (all by
## default), or null when the level is rejected. One ship gives exactly the
## session `--level=<level_name>` flies, with ship 0's script as its input.
func replay(ticks: int, ships: int = -1) -> Replay:
	var count: int = ship_count() if ships < 0 else clampi(ships, 1, ship_count())
	var level: LevelDef = LevelSwitch.load_level(level_path())
	if level == null:
		return null
	var session: LocalSession = AimData.apply(LocalSession.for_level(level, run_seed, null,
		LocalSession.load_tuning(ship_path)))
	var built: Replay = _with_ships(session.replay, count)
	for tick: int in ticks:
		var inputs: Array[ShipInput] = inputs_at(tick)
		inputs.resize(count)
		built.add_tick(inputs)
	return built


## The boxes of module `module_id`, read from its data file, for the check that
## the level's walls are that room's; empty when it cannot be read.
func module_boxes() -> Array[BoxBounds]:
	var boxes: Array[BoxBounds] = []
	var path: String = MODULES_DIR + module_id + ".json"
	if not FileAccess.file_exists(path):
		return boxes
	var module: ModuleDef = ModuleDef.parse_json(FileAccess.get_file_as_string(path))
	if module.error == "":
		boxes = module.boxes
	return boxes


## A copy of `source`'s header for `count` ships, the extra ships starting
## where the scene file puts them. Copied field by field, so `Replay` itself
## needs no notion of a stress scene.
func _with_ships(source: Replay, count: int) -> Replay:
	var copy: Replay = Replay.new(source.run_seed, count)
	copy.set_boxes(source.box_mins_mm, source.box_maxs_mm)
	copy.start_positions_mm = source.start_positions_mm.duplicate()
	copy.start_facings_mm = source.start_facings_mm.duplicate()
	for ship: int in range(1, count):
		copy.set_start_pose(ship, ship_positions[ship - 1], ship_facings[ship - 1])
	copy.reactor = source.reactor
	copy.debris = source.debris
	copy.tuning = source.tuning
	copy.loadout = source.loadout
	copy.robots = source.robots
	copy.parts = source.parts
	copy.salvage_rules = source.salvage_rules
	copy.look_aim = source.look_aim
	copy.component_rules = source.component_rules
	copy.rescue_rules = source.rescue_rules
	copy.miners = source.miners
	return copy


## "" when `data` has every key of `keys`, and no key outside `keys` and
## `optional`; otherwise the first problem.
static func check_keys(data: Dictionary, keys: Array[String], optional: Array[String] = []) -> String:
	for key: Variant in data:
		if not keys.has(key) and not optional.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in keys:
		if not data.has(key):
			return "missing key \"%s\"" % key
	return ""


## Reads `value` as three finite numbers into `read`. Returns the problem, or "".
static func read_vector(value: Variant, key: String, read: Array[Vector3]) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "%s: must be a list of three numbers" % key
	var numbers: Array = value
	for number: Variant in numbers:
		if (typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT) or not is_finite(float(number)):
			return "%s: must be a list of three numbers" % key
	read.append(Vector3(float(numbers[0]), float(numbers[1]), float(numbers[2])))
	return ""


static func _failed(message: String) -> StressScene:
	var scene: StressScene = StressScene.new()
	scene.error = message
	return scene


func _read(data: Dictionary) -> String:
	var problem: String = check_keys(data, KEYS)
	if problem != "":
		return problem
	for key: String in ["level", "module", "ship"]:
		if typeof(data[key]) != TYPE_STRING or (data[key] as String) == "":
			return "%s: must be a name" % key
	level_name = data["level"]
	module_id = data["module"]
	ship_path = data["ship"]
	if not ship_path.begins_with("res://data/") or not FileAccess.file_exists(ship_path):
		return "ship: %s is not a ship file under res://data/" % ship_path
	if level_path() == "":
		return "level: \"%s\" is not a level name" % level_name
	var seed_value: Variant = data["seed"]
	if (typeof(seed_value) != TYPE_INT and typeof(seed_value) != TYPE_FLOAT) or float(seed_value) < 0.0 \
			or float(seed_value) != floorf(float(seed_value)):
		return "seed: must be a whole number from 0 up"
	run_seed = int(seed_value)
	problem = _read_ships(data["ships"])
	if problem == "":
		problem = _read_inputs(data["inputs"])
	if problem == "":
		problem = _read_lights(data["lights"])
	return problem


func _read_ships(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != SHIP_COUNT - 1:
		return "ships: must list the %d ships after ship 0" % (SHIP_COUNT - 1)
	var entries: Array = value
	for index: int in entries.size():
		var field: String = "ships[%d]" % index
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return "%s: must be a JSON object" % field
		var entry: Dictionary = entries[index]
		var read: Array[Vector3] = []
		var problem: String = check_keys(entry, SHIP_KEYS)
		if problem == "":
			problem = read_vector(entry["position"], "position", read)
		if problem == "":
			problem = read_vector(entry["facing"], "facing", read)
		if problem == "" and read[1].is_zero_approx():
			problem = "facing: must not be zero"
		if problem != "":
			return "%s: %s" % [field, problem]
		ship_positions.append(read[0])
		ship_facings.append(read[1])
	return ""


func _read_inputs(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != SHIP_COUNT:
		return "inputs: must hold one script per ship, %d" % SHIP_COUNT
	var entries: Array = value
	for index: int in entries.size():
		var script: StressInputs = StressInputs.parse(entries[index], "inputs[%d]" % index)
		if script.error != "":
			return script.error
		scripts.append(script)
	return ""


func _read_lights(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "lights: must be a non-empty list"
	var entries: Array = value
	for index: int in entries.size():
		var field: String = "lights[%d]" % index
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return "%s: must be a JSON object" % field
		var entry: Dictionary = entries[index]
		var read: Array[Vector3] = []
		var problem: String = check_keys(entry, LIGHT_KEYS)
		if problem == "":
			problem = read_vector(entry["position"], "position", read)
		if problem == "":
			problem = read_vector(entry["color"], "color", read)
		for key: String in ["range", "energy"]:
			var number: Variant = entry.get(key)
			if problem == "" and ((typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT) \
					or not is_finite(float(number)) or float(number) <= 0.0):
				problem = "%s: must be a number above zero" % key
		if problem != "":
			return "%s: %s" % [field, problem]
		lights.append({"position": read[0], "color": Color(read[1].x, read[1].y, read[1].z),
			"range": float(entry["range"]), "energy": float(entry["energy"])})
	return ""
