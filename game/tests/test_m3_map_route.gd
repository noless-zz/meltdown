extends RefCounted

## The `map_route` acceptance check and the m3 `bot_generated_door_escape` step
## that lists it (#884, MAP-2, MAP-1, RUN-4, DEV-6): the held map's escape route
## and its door crosses, judged tick by tick in the running game. The step's
## hashes are those it had before the check, because the check only reads.

const STEP_ID: String = "bot_generated_door_escape"
const EXPECTED_HASH: int = 854268051
## The replay header written as format version 17 since #922.
const EXPECTED_LEVEL_HASH: int = 174792129
const SeedPick := preload("res://tests/m3_seed_pick.gd")
const M3Run := preload("res://tests/m3_suite_run.gd")
const GRACE: int = MapRouteWiring.ROUTE_EVERY_TICKS
const TICK: float = 1.0 / 60.0
## G2's side room, off the route out, and its reactor room (`test_main_map_route.gd`).
const SIDE_BOX: int = 3
const REACTOR_BOX: int = 4


func test_the_step_lists_map_route_and_keeps_its_hashes() -> String:
	var step: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if step == null:
		return "m3 has no step %s" % STEP_ID
	if not step.has_check(AcceptanceStep.CHECK_MAP_ROUTE) or not step.has_check(AcceptanceStep.CHECK_DOOR_FALLEN):
		return "%s checks %s" % [STEP_ID, step.checks]
	if step.expected_hash != EXPECTED_HASH or step.expected_level_hash != EXPECTED_LEVEL_HASH:
		return "%s expects hash %d and level hash %d" % [STEP_ID, step.expected_hash, step.expected_level_hash]
	return ""


func test_the_check_is_known_and_needs_a_replay() -> String:
	if not AcceptanceStep.KNOWN_CHECKS.has(AcceptanceStep.CHECK_MAP_ROUTE):
		return "map_route is not a known check"
	var parsed: AcceptanceSuite = AcceptanceSuite.parse_json(
		'{"name": "t", "steps": [{"id": "s", "checks": ["map_route"]}]}')
	if not parsed.error.contains("replay: needed by the map_route check"):
		return "a step without a replay gave '%s'" % parsed.error
	return ""


## The shipped step, flown in the shared m3 run (`m3_suite_run.gd`, #1139) by
## the runner in a main scene that holds its map as
## on the headset: every check passes and the route is drawn through the meltdown.
func test_the_runner_passes_the_step_with_the_map() -> String:
	var problem: String = M3Run.step_problem(STEP_ID)
	if problem == "":
		var step: Dictionary = M3Run.step(STEP_ID)
		var measured: Dictionary = step["measurements"]
		var meltdown: int = int(measured.get("map_route_meltdown_ticks", 0))
		if meltdown < 60 or int(measured.get("map_route_drawn_ticks", 0)) < meltdown - GRACE \
				or not str(step["message"]).contains("map_route: route drawn on"):
			problem = "measured %s: %s" % [measured, step["message"]]
	return problem


## G2 with every box explored and a door across the side room's opening, which
## is off the route out, so the guard lets it fall: the check sees the cross.
func test_a_door_in_explored_boxes_is_marked_in_the_scene() -> String:
	var main: Node = _main("g2")
	var session: LocalSession = main.get("session") as LocalSession
	var walls: BoxUnion = session.replay.walls()
	var door: Dictionary = _door_across(walls, SIDE_BOX)
	if door.is_empty():
		main.free()
		return "g2's side room opens into no other box"
	session.sim.set_debris(MeltdownDebris.parse([door]))
	main.call("advance_frame", 0.0)
	main.call("advance_frame", TICK)
	session.sim.ships[0].position = (walls.boxes[REACTOR_BOX].min_corner + walls.boxes[REACTOR_BOX].max_corner) / 2.0
	session.sim.ships[0].velocity = Vector3.ZERO
	var map: MapWiring = main.get("map") as MapWiring
	for box: BoxBounds in walls.boxes:
		map.explored.visit((box.min_corner + box.max_corner) / 2.0)
	var check: AcceptanceMapRouteCheck = AcceptanceMapRouteCheck.new()
	for i: int in 3:  # Before the reactor dies.
		main.call("advance_frame", TICK)
		check.sample_main(main)
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	for i: int in 90:
		main.call("advance_frame", TICK)
		check.sample_main(main)
	var fell: bool = session.sim.debris.is_solid(0)
	main.free()
	var measured: Dictionary = {}
	var result: Array = check.run(measured)
	if not fell:
		return "the door never fell"
	if result[0] != AcceptanceReport.RESULT_PASS or int(measured["map_route_door_marks"]) < 1:
		return "%s, %s" % [result, measured]
	if not str(result[1]).contains("door 0 fell on tick") or not str(result[1]).contains("marks drawn"):
		return "the message does not report the door's marks: %s" % result[1]
	return ""


func test_a_clean_hand_fed_run_passes() -> String:
	var result: Array = AcceptanceMapRouteCheck.judge(_run_samples(), GRACE, {})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "a clean run failed: %s" % result[1]
	return ""


func test_a_route_missing_mid_meltdown_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[50]["drawn"] = false
	return _fails_with(taken, "tick 50: no route is drawn 40 ticks into the meltdown")


func test_the_first_ticks_of_the_meltdown_may_lack_a_route() -> String:
	var taken: Array[Dictionary] = _run_samples()
	for i: int in range(10, 10 + GRACE):
		taken[i]["drawn"] = false
	var result: Array = AcceptanceMapRouteCheck.judge(taken, GRACE, {})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "the search interval's first ticks failed: %s" % result[1]
	taken[10 + GRACE]["drawn"] = false
	return _fails_with(taken, "tick %d: no route is drawn %d ticks into the meltdown" % [10 + GRACE, GRACE])


func test_a_route_before_the_reactor_dies_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[4]["drawn"] = true
	return _fails_with(taken, "tick 4: a route is drawn before the reactor died")


func test_a_route_ending_away_from_the_exit_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[30]["ends_at_exit"] = false
	return _fails_with(taken, "tick 30: the route ends outside the box that holds the exit")


func test_a_route_starting_away_from_the_ship_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	taken[31]["starts_near_ship"] = false
	return _fails_with(taken, "tick 31: the route starts more than one box from the ship")


func test_a_door_not_marked_fails() -> String:
	var taken: Array[Dictionary] = _run_samples()
	for i: int in range(40, taken.size()):
		taken[i]["doors_fallen"] = [5]
	taken[40]["door_marks"] = 1
	taken[55]["door_marks"] = 1
	taken[55]["doors_unmarked"] = [5]
	return _fails_with(taken, "tick 55: fallen door entry 5 (down since tick 40) is not among the route's blocked marks")


func test_no_samples_fail() -> String:
	var result: Array = AcceptanceMapRouteCheck.judge([] as Array[Dictionary], GRACE, {})
	if result[0] == AcceptanceReport.RESULT_PASS or not str(result[1]).contains("the scene holds no map"):
		return "no samples gave %s" % [result]
	return ""


## Ticks 0..99: the reactor dies on tick 10, the run ends on tick 90, and the
## route is drawn, at the exit and near the ship, through the meltdown.
static func _run_samples() -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	for tick: int in 100:
		var meltdown: bool = tick >= 10 and tick < 90
		taken.append({
			"tick": tick, "reactor_dead": tick >= 10, "running": tick < 90, "drawn": meltdown,
			"ends_at_exit": meltdown, "starts_near_ship": meltdown, "doors_fallen": [],
			"door_marks": 0, "doors_unmarked": [],
		})
	return taken


static func _fails_with(taken: Array[Dictionary], text: String) -> String:
	var result: Array = AcceptanceMapRouteCheck.judge(taken, GRACE, {})
	if result[0] == AcceptanceReport.RESULT_PASS or str(result[1]) != text:
		return "wanted '%s', got %s" % [text, result]
	return ""


## A door filling the whole opening between box `box` of `walls` and the first
## box it opens into, falling half a second into the meltdown; {} without one.
static func _door_across(walls: BoxUnion, box: int) -> Dictionary:
	var own: BoxBounds = walls.boxes[box]
	for other: int in walls.boxes.size():
		if other == box:
			continue
		var low: Vector3 = own.min_corner.max(walls.boxes[other].min_corner)
		var high: Vector3 = own.max_corner.min(walls.boxes[other].max_corner)
		if low.x < high.x and low.y < high.y and low.z < high.z:
			var centre: Vector3 = (low + high) / 2.0
			var size: Vector3 = (high - low).max(Vector3(0.5, 0.5, 0.5))
			return {"position": [centre.x, centre.y, centre.z], "size": [size.x, size.y, size.z],
				"after_seconds": 0.5}
	return {}


## The main scene with its rig built and `_ready` run, so it holds the map in a
## hand as on the headset; on `level_name` when given.
static func _main(level_name: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	if level_name != "":
		main.call("use_level", LevelSwitch.path_for(level_name))
	main.call("_ready")
	return main
