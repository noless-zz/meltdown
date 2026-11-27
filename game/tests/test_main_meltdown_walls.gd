extends RefCounted

## The mine's emergency look in the main scene (#1454, GFX-6, MP-2, ARC-1):
## G2's walls draw no meltdown while the reactor lives, take the look once it
## dies and ramp it in by simulation time, and the `meltdown_walls_shown`
## acceptance check passes on the result. One main scene for the whole file,
## so the unit test job stays short (#1483).

const Check := preload("res://acceptance/checks/meltdown_walls_check.gd")
const TICK: float = 1.0 / 60.0
## G2's reactor room: far from the exit, so the ship does not escape at once.
const REACTOR_BOX: int = 4


func test_g2_walls_take_the_look_only_after_the_reactor_dies() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("use_level", LevelSwitch.path_for("g2"))
	main.call("_ready")
	var problem: String = _check(main)
	main.free()
	return problem


func _check(main: Node) -> String:
	var session: LocalSession = main.get("session") as LocalSession
	var view: LevelView = main.get_node_or_null(LevelView.NODE_NAME) as LevelView
	if view == null:
		return "the main scene shows no level"
	main.call("advance_frame", 0.0)
	for i: int in 30:
		main.call("advance_frame", TICK)
	if view.meltdown_walls.value() != MeltdownWalls.OFF:
		return "with the reactor alive the walls show %s" % view.meltdown_walls.value()
	var walls: BoxUnion = session.replay.walls()
	var room: BoxBounds = walls.boxes[REACTOR_BOX]
	session.sim.ships[0].position = (room.min_corner + room.max_corner) / 2.0
	session.sim.ships[0].velocity = Vector3.ZERO
	session.sim.reactor.apply_damage(session.sim.reactor.hull)
	main.call("advance_frame", TICK)
	var first: Vector3 = view.meltdown_walls.value()
	var death_tick: int = session.sim.tick
	for i: int in 120:
		main.call("advance_frame", TICK)
	var later: Vector3 = view.meltdown_walls.value()
	if first.x > later.x or later.x <= 0.0 or later.y <= 0.0:
		return "the look did not ramp in: %s at the death, %s two seconds on" % [first, later]
	var elapsed: float = float(session.sim.tick - death_tick) / 60.0
	var want: Vector3 = MeltdownWalls.amount(view.meltdown_walls.rules, elapsed)
	if not later.is_equal_approx(want):
		return "%s s of ticks after the death the walls show %s, not %s" % [elapsed, later, want]
	var measurements: Dictionary = {}
	var verdict: Array = Check.judge_view(view, true, measurements)
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "the acceptance check failed: %s" % verdict[1]
	if Check.judge_view(view, false, {})[0] == AcceptanceReport.RESULT_PASS:
		return "the acceptance check passed with the reactor alive"
	return ""
