extends RefCounted

## The `portal_visibility_counted` acceptance check (#1364, GFX-3, PRF-2,
## PRF-4, PRF-5), lane-b's file under `acceptance/checks/`. In
## `suites/m6/effects.json` the `portal_visibility` step flies a replay; this
## check re-flies it tick by tick and, with the eye at ship 0 looking along its
## nose, culls a level view built from the flight's walls as the game does each
## frame. It reports boxes drawn and draw calls (one per mesh surface) per
## frame, culled and with culling switched off (`enabled` false in
## `level_visibility.json`), and the robots, pickups, miners and bolts per
## frame and how many of them sit in a hidden box and are hidden with it
## (#1382). It passes when:
##
## - the box holding the eye is drawn on every tick;
## - culling draws fewer boxes and fewer draw calls on average than drawing
##   every box.
##
## The flight with the culling followed must end on the step's pinned hash:
## the view reads the simulation and never writes it (MP-2). No GPU is needed;
## whether anything pops in at an opening stays a headset check.

const CHECK: String = "portal_visibility_counted"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var flown: Dictionary = fly(replay)
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	for key: String in flown:
		if key != "hash" and key != "own_box_hidden_at":
			measurements["portal_%s" % key] = flown[key]
	if step.expected_hash != AcceptanceStep.NO_HASH and flown["hash"] != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "flown with culling followed the hash is %d, not %d"
			% [flown["hash"], step.expected_hash]]
	return judge_flight(flown)


## Pass or fail for a flight `fly` returned, as [result, why].
static func judge_flight(flown: Dictionary) -> Array:
	if int(flown["frames"]) == 0:
		return [AcceptanceReport.RESULT_FAIL, "the flight has no frames"]
	if int(flown["own_box_hidden_at"]) >= 0:
		return [AcceptanceReport.RESULT_FAIL, "the eye's own box was hidden at tick %d" % flown["own_box_hidden_at"]]
	if float(flown["boxes_mean"]) >= float(flown["boxes_all"]) \
			or float(flown["draw_calls_mean"]) >= float(flown["draw_calls_all"]):
		return [AcceptanceReport.RESULT_FAIL, "culling drew %.1f of %d boxes and %.1f of %d draw calls on average"
			% [flown["boxes_mean"], flown["boxes_all"], flown["draw_calls_mean"], flown["draw_calls_all"]]]
	return [AcceptanceReport.RESULT_PASS,
		"%d frames: boxes drawn %.1f on average (most %d) of %d; draw calls %.1f on average (most %d) of %d with culling off; items hidden with their box %.1f of %.1f on average (most %d)"
		% [flown["frames"], flown["boxes_mean"], flown["boxes_most"], flown["boxes_all"],
		flown["draw_calls_mean"], flown["draw_calls_most"], flown["draw_calls_all"],
		flown.get("items_hidden_mean", 0.0), flown.get("items_mean", 0.0), flown.get("items_hidden_most", 0)]]


## Flies `replay` and culls each tick: {"frames", "boxes_all",
## "draw_calls_all" (culling off), "boxes_mean", "boxes_most",
## "draw_calls_mean", "draw_calls_most" (culled), "own_box_hidden_at" (first
## tick the eye's box was hidden, or -1), "items_mean", "items_hidden_mean",
## "items_hidden_most", "hash"}, or empty when the replay cannot start.
static func fly(replay: Replay) -> Dictionary:
	# As `robot_voices_check.gd`: `Replay.run` with no frames is the sim before its first tick.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return {}
	var view: LevelView = LevelView.new()
	view.build(sim.walls)
	var all_calls: int = 0
	for index: int in view.box_count():
		all_calls += view.surfaces_of(index)
	var most_boxes: int = 0
	var most_calls: int = 0
	var hidden_at: int = -1
	var items_total: int = 0
	var items_hidden_total: int = 0
	var items_hidden_most: int = 0
	var tick: int = 0
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		tick += 1
		var ship: ShipState = sim.ships[0]
		view.cull(ship.position, ship.orientation)
		most_boxes = maxi(most_boxes, view.drawn_boxes)
		most_calls = maxi(most_calls, view.drawn_surfaces)
		var items: Array[Vector3] = item_points(sim)
		items_total += items.size()
		var hidden_items: int = 0
		for point: Vector3 in items:
			if not view.shown_boxes().shows(point):
				hidden_items += 1
		items_hidden_total += hidden_items
		items_hidden_most = maxi(items_hidden_most, hidden_items)
		if hidden_at < 0:
			for index: int in view.visibility().boxes_at(ship.position, 0.0):
				if not view.box_node(index).visible:
					hidden_at = tick
	var count: int = maxi(view.culled_frames, 1)
	var result: Dictionary = {"frames": view.culled_frames, "boxes_all": view.box_count(),
		"draw_calls_all": all_calls, "boxes_mean": float(view.drawn_boxes_total) / count,
		"boxes_most": most_boxes, "draw_calls_mean": float(view.drawn_surfaces_total) / count,
		"draw_calls_most": most_calls, "own_box_hidden_at": hidden_at,
		"items_mean": float(items_total) / count, "items_hidden_mean": float(items_hidden_total) / count,
		"items_hidden_most": items_hidden_most, "hash": sim.state_hash()}
	view.free()
	return result


## Where the things the item views draw are: robots, floating parts, component
## heaps, trapped miners and bolts. Read only (MP-2).
static func item_points(sim: Sim) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for robot: RobotState in sim.robots:
		if robot != null:
			points.append(robot.position)
	for item: SalvageItem in sim.salvage:
		if item != null:
			points.append(item.position)
	for heap: ComponentItem in sim.components:
		points.append(heap.position)
	for projectile: Projectile in sim.projectiles:
		if projectile != null:
			points.append(projectile.position)
	if sim.rescue != null:
		for miner: Vector3i in sim.rescue.trapped:
			points.append(MinerRescue.position_of(miner))
	return points
