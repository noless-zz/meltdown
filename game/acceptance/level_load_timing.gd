class_name LevelLoadTiming
extends RefCounted

## Times one level load for the m6 `level_load` step (#1445, #1480, PRF-7): from the
## request to the first frame drawn after it, in four phases.
##
## - `generate_s`: `LevelSwitch.load_level`, the generator and the validators
##   for a seed, or reading a level file.
## - `build_view_s`: the session with its robots, the run rules' components and
##   miners for a run level, and the level drawn (`LevelSwitch.show_level`, with
##   the ambient bake) with the scene's lights, the same steps as
##   `LevelStart.level_session`.
## - `first_tick_s`: the session's first tick.
## - `first_frame_s`: from that tick to the end of the first frame drawn with the
##   level in the scene, where the headset compiles its shaders (#1480). The
##   frame comes from `AcceptanceFrameHook`; `drawn` says whether one really was.
##
## The wall clock is read here, in `acceptance/`, and never in `core/` or
## `gen/` (ARC-1). `begin` builds the level under a parent node the caller
## chooses and keeps it; `finish` takes it out again, so the scene the suite
## flies afterwards is as it was.

const PHASES: Array[String] = ["generate_s", "build_view_s", "first_tick_s", "first_frame_s"]
const FIRST_FRAME: String = "first_frame_s"
const DRAWN: String = "drawn"
const WORLD_NAME: String = "LevelLoadTiming"
const TOTAL: String = "total_s"
const SHIP_TUNING_PATH: String = LevelStart.SHIP_TUNING_PATH


## The load of `source` timed with no frame drawn: every phase, `first_frame_s`
## being the time to this call's end, `drawn` false, and `hash`, the simulation's
## after its first tick; or {"error": why} when the level is rejected. `shaft`
## names the shaft a run level is reached through, so it gets that shaft's run
## rules; "" for none.
static func measure(source: String, shaft: String) -> Dictionary:
	var timing: Dictionary = begin(source, shaft, null)
	if timing.has("error"):
		return timing
	return finish(timing, false, Time.get_ticks_usec())


## The load of `source` built under `parent` (null: no parent) and timed up to its
## first tick: {"generate_s", "build_view_s", "first_tick_s", "hash", "flown_usec",
## "world"}, or {"error": why}. The level stays in `parent` until `finish`.
static func begin(source: String, shaft: String, parent: Node) -> Dictionary:
	var world: Node3D = Node3D.new()
	world.name = WORLD_NAME
	if parent != null:
		parent.add_child(world)
	var started: int = Time.get_ticks_usec()
	var level: LevelDef = LevelSwitch.load_level(source)
	var generated: int = Time.get_ticks_usec()
	if level == null:
		drop(world)
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
	return {"generate_s": seconds(generated - started), "build_view_s": seconds(built - generated),
		"first_tick_s": seconds(flown - built), "hash": SimHash.of(session.sim), "started_usec": started,
		"flown_usec": flown, "world": world}


## `timing` from `begin` with the frame drawn at `drawn_usec` added: `first_frame_s`,
## `total_s` (request to that frame) and `drawn`. The level leaves the scene.
static func finish(timing: Dictionary, drawn: bool, drawn_usec: int) -> Dictionary:
	var done: Dictionary = timing.duplicate()
	drop(done.get("world") as Node)
	done.erase("world")
	var flown: int = int(done["flown_usec"])
	done[FIRST_FRAME] = seconds(maxi(drawn_usec - flown, 0))
	done[TOTAL] = seconds(maxi(drawn_usec, flown) - int(done["started_usec"]))
	done[DRAWN] = drawn
	done.erase("flown_usec")
	done.erase("started_usec")
	return done


## Takes `world` out of its parent, if any, and frees it.
static func drop(world: Node) -> void:
	if world == null or not is_instance_valid(world):
		return
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.free()


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
