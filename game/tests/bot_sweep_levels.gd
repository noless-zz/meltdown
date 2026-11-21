extends RefCounted

## The data files the bot sweeps build their levels from, read once (#1009):
## `bot_escape_sweep.gd` flies single levels and `bot_run_sweep.gd` flies runs
## of them, and both must fly exactly the same level for the same seed, so the
## reading and the building live here instead of in each sweep. Levels are
## built as the validator sweep builds them (`seed_sweep.gd`), with the reactor
## plan and the shipped loop bridges, robots only when asked for, and debris
## only when asked for.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## Read here as `seed_sweep.gd` reads its data files; `gen/` never opens files.
const DEBRIS_FILE: String = "res://data/gen/debris.json"

var modules: Array[ModuleDef] = []
var plan: ReactorPlan = null
var bridges: LoopBridges = null
## Null when the sweep places no robots.
var robot_plan: RobotPlan = null
## Null when the sweep places no debris.
var debris_plan: DebrisPlan = null
var radius: float = 1.0
var tuning: ShipTuning = null


## Reads every input, with robots when `with_robots` and debris when
## `with_debris`.
func _init(with_robots: bool = false, with_debris: bool = false) -> void:
	modules = SeedSweep.load_modules()
	plan = SeedSweep.load_reactor_plan()
	bridges = SeedSweep.load_loop_bridges()
	robot_plan = SeedSweep.load_robot_plan() if with_robots else null
	debris_plan = load_debris_plan() if with_debris else null
	radius = SeedSweep.ship_radius()
	tuning = LocalSession.load_tuning(SHIP_TUNING_PATH)


static func load_debris_plan() -> DebrisPlan:
	return DebrisPlan.parse_json(FileAccess.get_file_as_string(DEBRIS_FILE))


## The first broken data file as "<file>: <message>", or "". A broken file
## would give levels with no reactor, no loops or no robots, and a sweep that
## measures something other than the levels the player flies.
func broken() -> String:
	if plan.error != "":
		return "reactor.json: %s" % plan.error
	if bridges.error != "":
		return "generator.json: %s" % bridges.error
	if robot_plan != null and robot_plan.error != "":
		return "robots.json: %s" % robot_plan.error
	if debris_plan != null and debris_plan.error != "":
		return "debris.json: %s" % debris_plan.error
	return ""


## The generator for `level_seed`, loops closed by the shipped bridges.
func generate(level_seed: int) -> MineGenerator:
	return MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges)


## The level `generator` gives with these inputs.
func level_of(generator: MineGenerator) -> LevelDef:
	return generator.to_level_def(plan, radius, robot_plan, debris_plan)
