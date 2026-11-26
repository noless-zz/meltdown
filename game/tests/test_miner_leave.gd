extends RefCounted

## A rescued miner seen boarding (#1375, SLV-3, ARC-4, MP-2): at the fed
## `MINER_RESCUED` copy, a copy of the miner starts where its marker was drawn,
## rises into the local ship while it shrinks, and is gone after the look's
## `seconds`; a rescue by another ship rises straight up. The look is data.

const TestMinerRescue := preload("res://tests/test_miner_rescue.gd")


## A sim whose ship holds at a miner 1 m ahead until it is rescued, drawn by a
## view before and after, with the rescue tick's events.
func _rescued(view: MinerView) -> Array[SimEvent]:
	var miners: Array[Vector3i] = [Vector3i(0, 0, -1000)]
	var sim: Sim = TestMinerRescue.sim_with(miners)
	view.show_miners(sim.rescue, sim.ships[0])
	TestMinerRescue.idle(sim, TestMinerRescue.HOLD_TICKS - 1)
	view.show_miners(sim.rescue, sim.ships[0])
	TestMinerRescue.idle(sim, 1)
	return TestMinerRescue.rescued_events(sim)


func test_the_shipped_look_has_a_leave_and_a_bad_one_is_named() -> String:
	var text: String = FileAccess.get_file_as_string(MinerView.DEFAULT_LOOK_FILE)
	var parsed: Dictionary = MinerView.parse_look(text)
	if parsed.has("error") or not parsed.has(MinerLeave.KEY):
		return "shipped look: %s" % [parsed.get("error", "no leave entry")]
	if float(parsed[MinerLeave.KEY]["seconds"]) > 1.5:
		return "boarding takes %s s; it should read as one moment" % parsed[MinerLeave.KEY]["seconds"]
	var data: Dictionary = JSON.parse_string(text)
	data[MinerLeave.KEY]["seconds"] = 9.0
	if not String(MinerView.parse_look(JSON.stringify(data)).get("error", "")).contains("leave.seconds"):
		return "9 s was accepted"
	data[MinerLeave.KEY] = {"seconds": 1.0, "end_scale": 0.1, "rise_m": 1.0, "spin": 2}
	if not String(MinerView.parse_look(JSON.stringify(data)).get("error", "")).contains("spin"):
		return "an unknown key was accepted"
	data.erase(MinerLeave.KEY)
	if MinerView.parse_look(JSON.stringify(data)).has("error"):
		return "a look without leave was refused"
	return ""


func test_a_rescued_miner_rises_into_the_ship_shrinking_and_is_gone() -> String:
	var view: MinerView = MinerView.new()
	var events: Array[SimEvent] = _rescued(view)
	if events.size() != 1:
		view.free()
		return "setup: %d rescue events" % events.size()
	var at: Vector3 = view.marker(0).position
	view.feed(events)
	var ship: ShipState = ShipState.new()
	ship.position = Vector3(0, 0.5, 0)
	var seconds: float = view.leave.look()["seconds"]
	view.show_miners(null, ship, null, 0.0)
	var leaving: Node3D = view.leave.copy(0)
	var problem: String = ""
	if view.leave.started_count != 1 or view.leave.shown_count() != 1:
		problem = "%d started, %d drawn" % [view.leave.started_count, view.leave.shown_count()]
	elif not leaving.position.is_equal_approx(at) or view.leave.largest_offset_m > 0.001:
		problem = "it starts at %s; the marker was at %s" % [leaving.position, at]
	elif leaving.get_node_or_null("Beacon") == null:
		problem = "the copy has no beacon"
	if problem == "":
		view.show_miners(null, ship, null, seconds * 0.5)
		view.show_miners(null, ship, null, 0.0)
		if leaving.position.distance_to(ship.position) >= at.distance_to(ship.position) or leaving.scale.x >= 1.0:
			problem = "half way it is at %s, scale %s" % [leaving.position, leaving.scale.x]
	if problem == "":
		view.show_miners(null, ship, null, seconds * 0.6)
		view.show_miners(null, ship, null, 0.0)
		if view.leave.shown_count() != 0:
			problem = "still drawn after %.2f s" % seconds
		elif view.leave.longest_drawn_seconds >= seconds:
			problem = "drawn %.3f s into a %.2f s leave" % [view.leave.longest_drawn_seconds, seconds]
	view.free()
	return problem


func test_a_rescue_by_another_ship_rises_straight_up() -> String:
	var leave: MinerLeave = MinerLeave.new()
	leave.configure({}, BoxMesh.new(), MinerPod.new())
	var at: Vector3 = Vector3(3, 0, -4)
	var event: SimEvent = SimEvent.new(SimEvent.Kind.MINER_RESCUED, 1, 0.0, at)
	leave.feed([event] as Array[SimEvent], [] as Array[Node3D])
	var ship: ShipState = ShipState.new()
	ship.position = Vector3(-10, 0, 0)
	leave.advance(float(MinerLeave.FALLBACK["seconds"]) * 0.99, ship)
	leave.advance(0.0, ship)
	var moved: Vector3 = leave.copy(0).position - at
	leave.free()
	if moved.x != 0.0 or moved.z != 0.0 or moved.y <= 0.0:
		return "moved %s" % moved
	return ""


func test_other_events_start_no_leaving_and_the_rescue_state_is_unchanged() -> String:
	var view: MinerView = MinerView.new()
	var miners: Array[Vector3i] = [Vector3i(0, 0, -1000)]
	var sim: Sim = TestMinerRescue.sim_with(miners)
	view.show_miners(sim.rescue, sim.ships[0])
	var before: int = MinerRescue.state_hash(sim)
	var collected: SimEvent = SimEvent.new(SimEvent.Kind.COMPONENT_COLLECTED, 0, 1.0, Vector3.ZERO)
	view.feed([collected] as Array[SimEvent])
	view.show_miners(sim.rescue, sim.ships[0], null, 0.1)
	var started: int = view.leave.started_count
	var same: bool = MinerRescue.state_hash(sim) == before
	view.free()
	if started != 0 or not same:
		return "%d leavings started; rescue state unchanged %s" % [started, same]
	return ""
