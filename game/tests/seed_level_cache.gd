extends RefCounted

## Generators and built levels shared by the seed sweeps (#903, #956, GEN-2,
## ARC-2). Six test files sweep seeds 0..999 of the shipped data, and each used
## to generate and build every seed again; the same seed and files always give
## the same generator and the same level, so they are made once here and every
## sweep checks its own rule on them. Only tests read this: `SeedLevel` builds
## the flown level, and nothing here changes how it does.
##
## A shared level must not be changed by the sweeps that read it.
## `fingerprint` records each level as it was built, and
## `test_seed_level_cache.gd`, which runs after the sweeps, checks every
## level still matches.

## The level `SeedLevel.level_of` builds: reactor, robots, debris (spheres,
## doors, cave-ins, fires) and miners, as `--seed` flies it.
const SHIPPED: String = "shipped"
## The shipped level without the `fires` section: spheres, doors and cave-ins
## (#514), as the doors sweep and the fires sweep's level without fire build it
## (#462, #497).
const WITHOUT_FIRES: String = "without_fires"
const VARIANTS: Array[String] = [SHIPPED, WITHOUT_FIRES]

## Milliseconds spent generating, and building each variant, since the run
## started, so the sweep that reports them can hold them to its time limit.
static var generate_ms: int = 0
static var build_ms: Dictionary[String, int] = {SHIPPED: 0, WITHOUT_FIRES: 0}

static var _inputs: SeedLevel = null
static var _without_fires: DebrisPlan = null
static var _generators: Dictionary[int, MineGenerator] = {}
static var _hashes: Dictionary[int, int] = {}
static var _levels: Dictionary[String, Dictionary] = {SHIPPED: {}, WITHOUT_FIRES: {}}
static var _fingerprints: Dictionary[String, Dictionary] = {SHIPPED: {}, WITHOUT_FIRES: {}}


## The shipped data files, read once.
static func inputs() -> SeedLevel:
	if _inputs == null:
		_inputs = SeedLevel.load_inputs()
	return _inputs


## The generator for `level_seed` with `SeedLevel.MODULE_COUNT` modules from
## the shipped files, generated the first time it is asked for.
static func generator(level_seed: int) -> MineGenerator:
	if not _generators.has(level_seed):
		var started: int = Time.get_ticks_usec()
		var made: MineGenerator = inputs().generate(level_seed)
		generate_ms += (Time.get_ticks_usec() - started) / 1000
		_generators[level_seed] = made
		_hashes[level_seed] = made.output_hash()
	return _generators[level_seed]


## The generator for `level_seed` when one is shared already, else null.
static func peek_generator(level_seed: int) -> MineGenerator:
	return _generators.get(level_seed, null)


## `output_hash` of `level_seed`'s generator when it was generated, before any
## level was built from it, so a sweep can show building left it as it was.
static func generated_hash(level_seed: int) -> int:
	generator(level_seed)
	return _hashes[level_seed]


## The `variant` level for `level_seed`, built the first time it is asked for.
static func level(level_seed: int, variant: String = SHIPPED) -> LevelDef:
	var built: Dictionary = _levels[variant]
	if not built.has(level_seed):
		var from: MineGenerator = generator(level_seed)
		var started: int = Time.get_ticks_usec()
		var made: LevelDef = _build(from, variant)
		build_ms[variant] += (Time.get_ticks_usec() - started) / 1000
		built[level_seed] = made
		_fingerprints[variant][level_seed] = fingerprint(made)
	return built[level_seed]


## The `variant` level for `level_seed` when one is built already, else null.
static func peek_level(level_seed: int, variant: String = SHIPPED) -> LevelDef:
	return _levels[variant].get(level_seed, null)


## Each shared level whose `fingerprint` no longer matches the one taken when
## it was built, as "<variant> seed <n>".
static func changed_levels() -> Array[String]:
	var found: Array[String] = []
	for variant: String in VARIANTS:
		for level_seed: int in _levels[variant]:
			if fingerprint(_levels[variant][level_seed]) != _fingerprints[variant][level_seed]:
				found.append("%s seed %d" % [variant, level_seed])
	return found


## The number of levels of `variant` shared so far.
static func level_count(variant: String = SHIPPED) -> int:
	return _levels[variant].size()


## Everything a sweep reads from a level, as one string.
static func fingerprint(of: LevelDef) -> String:
	var parts: Array[String] = [of.error, str(of.start_position_mm), str(of.start_facing_mm),
			str(of.union.boxes.size()) if of.union != null else "", str(of.box_modules)]
	if of.union != null:
		for box: BoxBounds in of.union.boxes:
			parts.append("%s %s" % [box.min_corner, box.max_corner])
	parts.append("" if of.reactor == null else of.reactor.to_json())
	if of.robots != null:
		for spawn: RobotSpawn in of.robots.spawns:
			parts.append("%s %s %s" % [spawn.id, spawn.position_mm, spawn.facing_mm])
	parts.append("" if of.debris == null else of.debris.to_json())
	parts.append(str(of.miners))
	return "|".join(parts)


static func _build(from: MineGenerator, variant: String) -> LevelDef:
	var shipped: SeedLevel = inputs()
	if variant == SHIPPED:
		return shipped.level_of(from)
	if _without_fires == null:
		var data: Dictionary = JSON.parse_string(SeedLevel.read_text(SeedLevel.DEBRIS_FILE))
		data.erase(DebrisPlan.FIRES_KEY)
		_without_fires = DebrisPlan.parse_json(JSON.stringify(data))
		_without_fires.escape_validator = shipped.debris_plan.escape_validator
	return from.to_level_def(shipped.reactor_plan, shipped.tuning.radius, shipped.robot_plan,
			_without_fires)
