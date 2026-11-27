class_name LevelLoadTiming
extends RefCounted

## Times one level load for the m6 `level_load` step (#1445, PRF-7): from the
## request to the first simulation tick flown, in three phases.
##
## - `generate_s`: `LevelSwitch.load_level`, the generator and the validators
##   for a seed, or reading a level file.
## - `build_view_s`: the session with its robots, the run rules' components and
##   miners for a run level, and the level drawn (`LevelSwitch.show_level`, with
##   the ambient bake) with the scene's lights, the same steps as
##   `LevelStart.level_session`.
## - `first_tick_s`: the session's first tick.
##
## The wall clock is read here, in `acceptance/`, and never in `core/` or
## `gen/` (ARC-1). The level is drawn into a world that is not in the scene
## tree, so the scene the suite flies is left as it was; drawing the first frame
## on the GPU (shader compiles) is therefore not in the number, which is why the
## headset figure stays a gate check.

const PHASES: Array[String] = ["generate_s", "build_view_s", "first_tick_s"]
const TOTAL: String = "total_s"
const SHIP_TUNING_PATH: String = LevelStart.SHIP_TUNING_PATH


## The load of `source` timed: {"generate_s", "build_view_s", "first_tick_s",
## "total_s", "hash"}, `hash` being the simulation's after its first tick, or
## {"error": why} when the level is rejected. `shaft` names the shaft a run
## level is reached through, so it gets that shaft's run rules; "" for none.
static func measure(source: String, shaft: String) -> Dictionary:
	var world: Node3D = Node3D.new()
	var started: int = Time.get_ticks_usec()
	var level: LevelDef = LevelSwitch.load_level(source)
	var generated: int = Time.get_ticks_usec()
	if level == null:
		world.free()
		return {"error": "%s was rejected" % source}
	var session: LocalSession = LocalSession.for_level(level, 0, null, LocalSession.load_tuning(SHIP_TUNING_PATH))
	var rules: RunLevelRules = rules_for(shaft)
	if rules != null:
		rules.install(session, level)
	SceneLights.place(LevelSwitch.show_level(world, level), StressScene.lights_for(source))
	AimData.apply(session)
	var built: int = Time.get_ticks_usec()
	session.advance(ShipState.TICK_DT)
	var flown: int = Time.get_ticks_usec()
	world.free()
	return {"generate_s": seconds(generated - started), "build_view_s": seconds(built - generated),
		"first_tick_s": seconds(flown - built), TOTAL: seconds(flown - started),
		"hash": SimHash.of(session.sim)}


## The simulation's hash after the first tick of `source` built the way a run
## builds it (`LevelStart.level_session`) with no clock read, or -1 when the
## level is rejected. Matching `measure`'s hash shows the timing changed nothing.
static func unmeasured_hash(source: String, shaft: String) -> int:
	var world: Node3D = Node3D.new()
	var session: LocalSession = LevelStart.level_session(world, source, null, rules_for(shaft),
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	world.free()
	if session == null:
		return -1
	session.advance(ShipState.TICK_DT)
	return SimHash.of(session.sim)


## The run rules of a level reached through `shaft`, as `LevelStart.run_rules`
## loads them for a run's level: that shaft's drop weights and alarm risk.
## Null for "" or a shaft the shafts file does not have.
static func rules_for(shaft: String) -> RunLevelRules:
	if shaft == "":
		return null
	var shafts: ShaftOffer = ShaftOffer.build(SeedLevel.read_text(RunWiring.SHAFTS_FILE))
	if not shafts.kinds.has(shaft):
		return null
	var risk: Dictionary = shafts.risks[shaft]
	return RunLevelRules.load_files(RunLevelRules.COMPONENTS_DIR, RunLevelRules.RESCUE_FILE,
		shafts.rewards[shaft], RunLevelRules.ALARM_FILE, float(risk["alarm"]))


static func seconds(usec: int) -> float:
	return usec / 1000000.0
