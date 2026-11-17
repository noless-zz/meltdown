class_name SeedLevel
extends RefCounted

## Builds the level the main scene flies for `--seed=<n>` (#382, GEN-1, GEN-2,
## GEN-5): `MineGenerator` for that seed, with the loop bridges, the reactor
## plan and the validator from `res://data/gen/`, built exactly as the
## 1,000-seed validator sweep builds its levels (`tests/seed_sweep.gd`), so a
## flown seed is one the sweep checks. The level runs `LevelValidator` before it
## is handed over; a level that fails is printed with its messages and not
## flown.
##
## It sits beside `LevelSwitch`, which hands it the seed, because `gen/` never
## opens files: this class reads the data files and hands `gen/` their text.

## Modules per level, as the validator sweep builds them.
const MODULE_COUNT: int = 10
const MODULES_DIR: String = "res://data/modules/"
const GENERATOR_FILE: String = "res://data/gen/generator.json"
const REACTOR_FILE: String = "res://data/gen/reactor.json"
const VALIDATOR_FILE: String = "res://data/gen/validator.json"
const SHIP_FILE: String = "res://data/ships/default_ship.json"


## The validated level for `level_seed`, or null after printing why, so the
## caller keeps the test tunnel. The exit radius comes from `defaults_path`,
## like a level file's that leaves it out (ARC-4).
static func load_level(level_seed: int, defaults_path: String = LevelSwitch.DEFAULTS_FILE,
		validator_text: String = "") -> LevelDef:
	var defaults: LevelDefaults = LevelSwitch.load_defaults(defaults_path)
	if defaults == null:
		return _rejected(level_seed, ["level defaults %s rejected" % defaults_path])
	var plan: ReactorPlan = ReactorPlan.parse_json(_text(REACTOR_FILE))
	var bridges: LoopBridges = LoopBridges.parse_json(_text(GENERATOR_FILE))
	if validator_text == "":
		validator_text = _text(VALIDATOR_FILE)
	var validator: LevelValidator = LevelValidator.parse_json(validator_text)
	var tuning: ShipTuning = ShipTuning.parse_json(_text(SHIP_FILE))
	# A broken data file must not quietly give a level without a reactor or loops.
	for problem: Array in [[REACTOR_FILE, plan.error], [GENERATOR_FILE, bridges.error],
			[VALIDATOR_FILE, validator.error], [SHIP_FILE, tuning.error]]:
		if problem[1] != "":
			return _rejected(level_seed, ["%s rejected (%s)" % problem])
	var level: LevelDef = build(level_seed, load_modules(), plan, bridges, tuning.radius)
	if level.error != "":
		return _rejected(level_seed, [level.error])
	level.exit_radius_mm = defaults.exit_radius_mm
	if level.reactor != null:
		level.reactor.exit_radius_mm = defaults.exit_radius_mm
	var failures: Array[String] = validator.validate(level, tuning.radius)
	if not failures.is_empty():
		return _rejected(level_seed, failures)
	return level


## The level `MineGenerator` builds for `level_seed` from these inputs, not
## yet validated.
static func build(level_seed: int, modules: Array[ModuleDef], plan: ReactorPlan,
		bridges: LoopBridges, ship_radius: float) -> LevelDef:
	var generator: MineGenerator = MineGenerator.generate(level_seed, modules, MODULE_COUNT, bridges)
	return generator.to_level_def(plan, ship_radius)


## Every module file in `MODULES_DIR`, in file name order, so the generator
## sees the same list on every device (GEN-2).
static func load_modules() -> Array[ModuleDef]:
	var modules: Array[ModuleDef] = []
	var files: PackedStringArray = DirAccess.get_files_at(MODULES_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".json"):
			modules.append(ModuleDef.parse_json(_text(MODULES_DIR + file)))
	return modules


static func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func _rejected(level_seed: int, messages: Array) -> LevelDef:
	print("Meltdown: seed %d rejected; flying the test tunnel" % level_seed)
	for message: Variant in messages:
		print("  %s" % message)
	return null
