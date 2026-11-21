class_name AcceptanceMapMarkersCheck
extends RefCounted

## The `map_markers` acceptance check (#913, MAP-1, MAP-2, RUN-2, DEV-7): the
## held map's exit and reactor markers as the running game draws them, which
## `test_map_markers.gd` and `test_main_map_markers.gd` only show on hand-built
## states. After every replay tick it reads the scene's `MapWiring` hologram and
## judges, naming the first tick that broke a rule:
##
## - the exit marker is shown on every tick;
## - from the tick the reactor dies to the end of the replay, the reactor marker
##   is shown (the owner's G3 playtest found it missing once found);
## - the reactor dies at some point, or there is nothing to judge.
##
## It reads the scene and a copy of the reactor; it writes nothing, so every
## hash of the step stands.

## One sample per tick, as `sample_main` builds it and the unit tests hand-feed it.
const KEY_TICK: String = "tick"
const KEY_EXIT_SHOWN: String = "exit_shown"
const KEY_REACTOR_DEAD: String = "reactor_dead"
const KEY_REACTOR_SHOWN: String = "reactor_shown"

var samples: Array[Dictionary] = []


## A check for `step`, or null when the step does not list `map_markers`.
static func for_step(step: AcceptanceStep) -> AcceptanceMapMarkersCheck:
	if not step.has_check(AcceptanceStep.CHECK_MAP_MARKERS):
		return null
	return AcceptanceMapMarkersCheck.new()


## Samples `main`'s map after a replay tick. A scene without a held map adds
## nothing, and the check then fails for want of samples.
func sample_main(main: Node) -> void:
	var map: MapWiring = main.get("map") as MapWiring
	var session: LocalSession = main.get("session") as LocalSession
	if map == null or map.hologram == null or session == null:
		return
	samples.append({
		KEY_TICK: session.sim.tick,
		KEY_EXIT_SHOWN: map.hologram.exit_marker_shown(),
		KEY_REACTOR_DEAD: MapRouteWiring.reactor_destroyed(session),
		KEY_REACTOR_SHOWN: map.hologram.reactor_marker_shown(),
	})


## [result, message] for the samples taken, adding the measurements.
func run(measurements: Dictionary) -> Array:
	return judge(samples, measurements)


## [result, message] for `taken`.
static func judge(taken: Array[Dictionary], measurements: Dictionary) -> Array:
	var dead_ticks: int = 0
	var shown_dead: int = 0
	var first_death: int = -1
	var failure: String = ""
	for sample: Dictionary in taken:
		var tick: int = int(sample[KEY_TICK])
		var problem: String = ""
		if not bool(sample[KEY_EXIT_SHOWN]):
			problem = "the exit marker is hidden"
		if bool(sample[KEY_REACTOR_DEAD]):
			if first_death < 0:
				first_death = tick
			dead_ticks += 1
			if bool(sample[KEY_REACTOR_SHOWN]):
				shown_dead += 1
			elif problem == "":
				problem = "the reactor marker is hidden %d ticks after the reactor died" % (tick - first_death)
		if problem != "" and failure == "":
			failure = "tick %d: %s" % [tick, problem]
	measurements["map_markers_ticks"] = taken.size()
	measurements["map_markers_dead_ticks"] = dead_ticks
	measurements["map_markers_reactor_shown_dead_ticks"] = shown_dead
	if taken.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no tick was sampled: the scene holds no map"]
	if failure != "":
		return [AcceptanceReport.RESULT_FAIL, failure]
	if dead_ticks == 0:
		return [AcceptanceReport.RESULT_FAIL, "the reactor never died while the replay flew"]
	return [AcceptanceReport.RESULT_PASS, "exit marked on all %d ticks; reactor marked on all %d ticks from its death on tick %d" % [
		taken.size(), dead_ticks, first_death]]
