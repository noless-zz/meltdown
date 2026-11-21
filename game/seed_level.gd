class_name SeedLevel
extends RefCounted

## Builds the level the main scene flies for `--seed=<n>` (#382, #441, GEN-1,
## GEN-2, GEN-5): `MineGenerator` for that seed, with the loop bridges, the
## reactor plan, the robot plan, the debris plan and the miner plan (#938)
## from `res://data/gen/`.
## This is the one loader: the 1,000-seed validator sweep
## (`tests/seed_sweep.gd`) takes its inputs, its levels and its checks from
## here too, so a flown seed is exactly a level the sweep checks. It ships in
## the APK and `tests/` does not, which is why the sweep calls it and not the
## other way round. The level runs `LevelValidator`, with the robot radii and
## the start module's boxes, before it is handed over; a level that fails, or
## a broken data file, is printed with its messages and not flown.
##
## It sits beside `LevelSwitch`, which hands it the seed, because `gen/` never
## opens files: this class reads the data files and hands `gen/` their text.
##
## An instance holds the parsed inputs (`load_inputs`), so the sweep reads the
## files once for thousands of seeds.

## Modules per level, as the validator sweep builds them.
const MODULE_COUNT: int = 10
const MODULES_DIR: String = "res://data/modules/"
const GENERATOR_FILE: String = "res://data/gen/generator.json"
const REACTOR_FILE: String = "res://data/gen/reactor.json"
const VALIDATOR_FILE: String = "res://data/gen/validator.json"
const ROBOTS_FILE: String = "res://data/gen/robots.json"
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const MINERS_FILE: String = "res://data/gen/miners.json"
const ROBOTS_DIR: String = "res://data/robots/"
const SHIP_FILE: String = "res://data/ships/default_ship.json"

var modules: Array[ModuleDef] = []
var validator: LevelValidator = null
var reactor_plan: ReactorPlan = null
var bridges: LoopBridges = null
var robot_plan: RobotPlan = null
var debris_plan: DebrisPlan = null
var miner_plan: MinerPlan = null
var tuning: ShipTuning = null
var robot_radii: Dictionary[String, int] = {}
## The first broken data file as "<file name>: <its message>"; empty when all
## files were read.
var error: String = ""


## Every input read from the data files. `overrides` maps a `res://` path to
## the text to use in its place, so a test can break one file; a
## `validator_text` other than "" replaces the validator file the same way.
static func load_inputs(validator_text: String = "", overrides: Dictionary = {}) -> SeedLevel:
	var inputs: SeedLevel = SeedLevel.new()
	inputs.modules = load_modules(overrides)
	if validator_text == "":
		validator_text = read_text(VALIDATOR_FILE, overrides)
	inputs.validator = LevelValidator.parse_json(validator_text)
	inputs.reactor_plan = ReactorPlan.parse_json(read_text(REACTOR_FILE, overrides))
	inputs.bridges = LoopBridges.parse_json(read_text(GENERATOR_FILE, overrides))
	inputs.robot_plan = RobotPlan.parse_json(read_text(ROBOTS_FILE, overrides), robot_texts(overrides))
	inputs.debris_plan = DebrisPlan.parse_json(read_text(DEBRIS_FILE, overrides))
	inputs.miner_plan = MinerPlan.parse_json(read_text(MINERS_FILE, overrides))
	inputs.tuning = ShipTuning.parse_json(read_text(SHIP_FILE, overrides))
	# A broken data file must not quietly give a level without a reactor,
	# loops, robots or debris, nor let a sweep pass every seed on defaults.
	for problem: Array in [[VALIDATOR_FILE, inputs.validator.error],
			[REACTOR_FILE, inputs.reactor_plan.error], [GENERATOR_FILE, inputs.bridges.error],
			[ROBOTS_FILE, inputs.robot_plan.error], [DEBRIS_FILE, inputs.debris_plan.error],
			[MINERS_FILE, inputs.miner_plan.error], [SHIP_FILE, inputs.tuning.error]]:
		if problem[1] != "":
			inputs.error = "%s: %s" % [(problem[0] as String).get_file(), problem[1]]
			return inputs
	inputs.robot_radii = inputs.robot_plan.radii_by_id()
	# The validator checks the reactor against the plan's own fraction (#912).
	inputs.validator.min_escape_fraction = inputs.reactor_plan.min_escape_fraction
	# Debris is placed so the escape still fits this validator's margin (#493).
	inputs.debris_plan.escape_validator = inputs.validator
	return inputs


## The validated level for `level_seed`, or null after printing why, so the
## caller keeps the test tunnel. The exit radius comes from `defaults_path`,
## like a level file's that leaves it out (ARC-4).
static func load_level(level_seed: int, defaults_path: String = LevelSwitch.DEFAULTS_FILE,
		validator_text: String = "", overrides: Dictionary = {}) -> LevelDef:
	var defaults: LevelDefaults = LevelSwitch.load_defaults(defaults_path)
	if defaults == null:
		return _rejected(level_seed, ["level defaults %s rejected" % defaults_path])
	var inputs: SeedLevel = load_inputs(validator_text, overrides)
	if inputs.error != "":
		return _rejected(level_seed, [inputs.error])
	var generator: MineGenerator = inputs.generate(level_seed)
	var level: LevelDef = inputs.level_of(generator)
	if level.error != "":
		return _rejected(level_seed, ["level: %s" % level.error])
	level.exit_radius_mm = defaults.exit_radius_mm
	if level.reactor != null:
		level.reactor.exit_radius_mm = defaults.exit_radius_mm
	var failures: Array[String] = inputs.validate(level, generator)
	if not failures.is_empty():
		return _rejected(level_seed, failures)
	return level


## `MineGenerator` for `level_seed` with these modules and loop bridges.
func generate(level_seed: int, module_count: int = MODULE_COUNT) -> MineGenerator:
	return MineGenerator.generate(level_seed, modules, module_count, bridges)


## The generated level with its reactor, robots, debris and miners, not yet
## validated.
func level_of(generator: MineGenerator) -> LevelDef:
	return generator.to_level_def(reactor_plan, tuning.radius, robot_plan, debris_plan, miner_plan)


## `LevelValidator`'s messages for a level `level_of` built from `generator`,
## with the robot radii and the start module's boxes (#428).
func validate(level: LevelDef, generator: MineGenerator) -> Array[String]:
	return validator.validate(level, tuning.radius, true, robot_radii, start_module_boxes(generator))


## Every module file in `MODULES_DIR`, in file name order, so the generator
## sees the same list on every device (GEN-2).
static func load_modules(overrides: Dictionary = {}) -> Array[ModuleDef]:
	var list: Array[ModuleDef] = []
	for file: String in _json_files(MODULES_DIR):
		list.append(ModuleDef.parse_json(read_text(MODULES_DIR + file, overrides)))
	return list


## Every robot file's text by id, for `RobotPlan.parse_json`.
static func robot_texts(overrides: Dictionary = {}) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in _json_files(ROBOTS_DIR):
		texts[file.trim_suffix(".json")] = read_text(ROBOTS_DIR + file, overrides)
	return texts


## The boxes of the module the generated level starts in.
static func start_module_boxes(generator: MineGenerator) -> Array[int]:
	var boxes: Array[int] = []
	if generator.open_owner.is_empty():
		return boxes
	var start: int = GeneratedLevel.start_placement(generator)
	var placement: ModulePlacement = generator.placements[start]
	for box: int in range(placement.first_box, placement.end_box):
		boxes.append(box)
	return boxes


static func _json_files(dir: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			found.append(file)
	found.sort()
	return found


## The text at `path`, or its override, or "" for a missing file.
static func read_text(path: String, overrides: Dictionary = {}) -> String:
	if overrides.has(path):
		return overrides[path]
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func _rejected(level_seed: int, messages: Array) -> LevelDef:
	print("Meltdown: seed %d rejected; flying the test tunnel" % level_seed)
	for message: Variant in messages:
		print("  %s" % message)
	return null
