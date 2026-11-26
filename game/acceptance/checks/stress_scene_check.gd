extends RefCounted

## The `stress_scene` acceptance check (#1288, PRF-8, G6): the m6 perf step's
## scene is the one PRF-8 names. It passes when the flown replay started with
## the 20 robots, the scene file lists 4 ships and 8 lights, the 8 lights are
## drawn in the level, and the meltdown is still counting down when the step
## ends, so the frame times the `frame_budget` check takes on the same step
## were measured with the meltdown's effects on. That check reports the
## render scale the frames were drawn at beside their times (#1417).
##
## The step's replay holds all four ships (#1354): ship 0 is the local view
## and ships 1 to 3 fly their scripts beside it with no network
## (`LocalSession.fly_ships`), drawn by `OtherShipsView`. The check fails
## unless all four were flown and the three others are drawn at the end.

const ROBOTS: int = 20
const SHIPS: int = 4
const LIGHTS: int = 8


static func judges() -> Dictionary[String, Callable]:
	return {"stress_scene": _stress_scene}


static func _stress_scene(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var scene: StressScene = StressScene.load_file()
	if scene.error != "":
		return [AcceptanceReport.RESULT_FAIL, "stress scene file rejected: %s" % scene.error]
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "the step's replay was not flown"]
	var replay: Replay = Replay.load_file(step.replay_path)
	var session: LocalSession = runner.main.get("session") as LocalSession
	var reactor: ReactorState = session.sim.reactor if session != null else null
	var drawn: int = SceneLights.count(runner.main.get_node_or_null(LevelView.NODE_NAME))
	measurements["robots_at_start"] = replay.robots.size()
	measurements["robots_left"] = session.sim.robots.size() if session != null else 0
	measurements["ships_in_scene"] = scene.ship_count()
	measurements["ships_flown"] = session.sim.ships.size() if session != null else 0
	measurements["lights_drawn"] = drawn
	var ships_view: OtherShipsView = runner.main.get_node_or_null(OtherShipsView.NODE_NAME) as OtherShipsView
	var ships_drawn: int = ships_view.shown() if ships_view != null else 0
	measurements["ships_drawn"] = ships_drawn
	measurements["meltdown_ticks_left"] = reactor.meltdown_ticks_left if reactor != null else 0
	var problems: PackedStringArray = PackedStringArray()
	if replay.robots.size() != ROBOTS:
		problems.append("%d robots at the start, not %d" % [replay.robots.size(), ROBOTS])
	if scene.ship_count() != SHIPS:
		problems.append("the scene lists %d ships, not %d" % [scene.ship_count(), SHIPS])
	if measurements["ships_flown"] != SHIPS or ships_drawn != SHIPS - 1:
		problems.append("%d ships flown and %d drawn beside the local one, not %d and %d" % [
			measurements["ships_flown"], ships_drawn, SHIPS, SHIPS - 1])
	if scene.lights.size() != LIGHTS or drawn != LIGHTS:
		problems.append("%d lights listed and %d drawn, not %d" % [scene.lights.size(), drawn, LIGHTS])
	if reactor == null or not reactor.destroyed or reactor.meltdown_ticks_left <= 0:
		problems.append("the meltdown is not running at the end")
	if not problems.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "; ".join(problems)]
	return [AcceptanceReport.RESULT_PASS, "%d robots (%d left), %d lights drawn, meltdown running with %d ticks left; %d ships flown, %d drawn beside the local one" % [
		replay.robots.size(), measurements["robots_left"], drawn, reactor.meltdown_ticks_left,
		measurements["ships_flown"], ships_drawn]]
