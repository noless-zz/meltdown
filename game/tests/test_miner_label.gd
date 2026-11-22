extends RefCounted

## The label over a trapped miner the first time it comes into sight (#1220,
## SLV-3, PLT-2, ARC-3, ARC-4): not before it is in sight, once per miner, gone
## after its time, never for a rescued miner, and drawing it writes nothing.

const TestMinerRescue := preload("res://tests/test_miner_rescue.gd")

## 1 m ahead of the ship, in sight and within the 4 m rescue reach.
const NEAR: Vector3i = Vector3i(0, 0, -1000)
## 60 m ahead, beyond the shipped 25 m sight distance.
const FAR: Vector3i = Vector3i(0, 0, -60000)


func _sim(miners: Array[Vector3i]) -> Sim:
	return TestMinerRescue.sim_with(miners)


func test_shipped_look_file_is_valid() -> String:
	var label: MinerLabel = MinerLabel.new()
	var problem: String = label.look_error
	if problem == "" and label.look()["text"] != "Trapped miner: hold near to rescue":
		problem = "text is \"%s\"" % label.look()["text"]
	label.free()
	return problem


func test_rejected_look_names_the_key() -> String:
	var good: Dictionary = {"text": "x", "sight_distance_m": 25, "show_seconds": 6,
		"height_above_m": 1.6, "font_size": 96, "pixel_size": 0.0035, "color": [1, 1, 1]}
	if MinerLabel.parse_look(JSON.stringify(good)).has("error"):
		return "good look rejected: %s" % MinerLabel.parse_look(JSON.stringify(good))
	var cases: Dictionary = {
		"show_seconds": 0, "height_above_m": 9, "text": "", "color": [2, 0, 0], "sight_distance_m": true,
	}
	for key: String in cases:
		var bad: Dictionary = good.duplicate()
		bad[key] = cases[key]
		var parsed: Dictionary = MinerLabel.parse_look(JSON.stringify(bad))
		if not parsed.has("error") or not (parsed["error"] as String).contains(key):
			return "bad %s gave %s" % [key, parsed]
	var extra: Dictionary = good.duplicate()
	extra["size"] = 1
	if not MinerLabel.parse_look(JSON.stringify(extra)).has("error"):
		return "unknown key accepted"
	return ""


func test_shown_on_first_sight_and_not_before() -> String:
	var sim: Sim = _sim([FAR] as Array[Vector3i])
	var label: MinerLabel = MinerLabel.new()
	var ship: ShipState = sim.ships[0]
	var problem: String = ""
	label.show_labels(sim.rescue, ship, null, 0.1)
	if label.shown_count() != 0:
		problem = "label shown for a miner 60 m off"
	else:
		# A ship of its own, 10 m from the miner; the sim's ship is not touched.
		var near: ShipState = ShipState.new()
		near.position = Vector3(0, 0, -50)
		label.show_labels(sim.rescue, near, null, 0.1)
		if not label.showing(FAR):
			problem = "no label at 10 m in open space"
		elif not label.label_of(FAR).visible:
			problem = "label node hidden"
		elif label.label_of(FAR).text != "Trapped miner: hold near to rescue":
			problem = "label says \"%s\"" % label.label_of(FAR).text
		elif label.label_of(FAR).position.distance_to(MinerRescue.position_of(FAR)) > 3.0:
			problem = "label %s m from its miner" % label.label_of(FAR).position.distance_to(MinerRescue.position_of(FAR))
	label.free()
	return problem


func test_a_wall_between_hides_the_miner() -> String:
	# Two boxes that only touch face to face: a wall stands between them.
	var walls: BoxUnion = BoxUnion.new([
		BoxBounds.new(Vector3(-5, -5, -5), Vector3(5, 5, 5)),
		BoxBounds.new(Vector3(-5, -5, -15), Vector3(5, 5, -5)),
	] as Array[BoxBounds])
	var label: MinerLabel = MinerLabel.new()
	var miner: Vector3i = Vector3i(0, 0, -10000)
	var problem: String = ""
	if label.in_sight(miner, Vector3.ZERO, walls):
		problem = "miner behind a wall counted as in sight"
	elif not label.in_sight(miner, Vector3.ZERO, null):
		problem = "miner 10 m off in open space not in sight"
	label.free()
	return problem


func test_shown_once_and_gone_after_its_time() -> String:
	var sim: Sim = _sim([FAR, Vector3i(0, 0, -1000)] as Array[Vector3i])
	var label: MinerLabel = MinerLabel.new()
	var seconds: float = float(label.look()["show_seconds"])
	var problem: String = ""
	var near_miner: Vector3i = sim.rescue.trapped[1]
	label.show_labels(sim.rescue, sim.ships[0], null, 0.0)
	label.show_labels(sim.rescue, sim.ships[0], null, seconds * 0.5)
	if not label.showing(near_miner):
		problem = "label gone at half its time"
	else:
		label.show_labels(sim.rescue, sim.ships[0], null, seconds * 0.6)
		if label.showing(near_miner) or label.label_of(near_miner).visible:
			problem = "label still shown after its time"
		else:
			for frame: int in 10:
				label.show_labels(sim.rescue, sim.ships[0], null, 0.1)
			if label.showing(near_miner) or label.label_of(near_miner).visible:
				problem = "label shown again while the miner stays in sight"
	label.free()
	return problem


func test_a_new_run_shows_it_again() -> String:
	var label: MinerLabel = MinerLabel.new()
	var first: Sim = _sim([NEAR] as Array[Vector3i])
	label.show_labels(first.rescue, first.ships[0], null, 0.0)
	label.show_labels(first.rescue, first.ships[0], null, 100.0)
	var second: Sim = _sim([NEAR] as Array[Vector3i])
	label.show_labels(second.rescue, second.ships[0], null, 0.0)
	var shown: bool = label.showing(NEAR)
	label.free()
	return "" if shown else "a new run did not show the label"


func test_gone_when_rescued_and_never_for_a_rescued_miner() -> String:
	var sim: Sim = _sim([NEAR] as Array[Vector3i])
	var label: MinerLabel = MinerLabel.new()
	var problem: String = ""
	label.show_labels(sim.rescue, sim.ships[0], null, 0.0)
	var before: int = MinerRescue.state_hash(sim)
	label.show_labels(sim.rescue, sim.ships[0], null, 0.1)
	if MinerRescue.state_hash(sim) != before:
		problem = "drawing changed the rescue state"
	TestMinerRescue.idle(sim, TestMinerRescue.HOLD_TICKS)
	label.show_labels(sim.rescue, sim.ships[0], null, 0.1)
	if problem == "" and sim.rescue.rescued != 1:
		problem = "setup rescued %d" % sim.rescue.rescued
	elif problem == "" and (label.shown_count() != 0 or label.label_of(NEAR).visible):
		problem = "label still shown after the rescue"
	label.free()
	# Rescued before it was ever in sight: no label at all.
	var unseen: Sim = _sim([NEAR] as Array[Vector3i])
	var late: MinerLabel = MinerLabel.new()
	late.show_labels(unseen.rescue, null, null, 0.0)
	TestMinerRescue.idle(unseen, TestMinerRescue.HOLD_TICKS)
	late.show_labels(unseen.rescue, unseen.ships[0], null, 0.1)
	if problem == "" and (late.shown_count() != 0 or late.label_of(NEAR) != null):
		problem = "a rescued miner got a label"
	late.free()
	return problem


func test_miner_view_carries_the_label_and_rescue_off_shows_none() -> String:
	var view: MinerView = MinerView.new()
	var problem: String = ""
	if view.label == null or view.label.get_parent() != view:
		problem = "MinerView has no label node"
	else:
		view.show_miners(Sim.new(1, 1).rescue, null, null, 0.1)
		if view.label.shown_count() != 0:
			problem = "labels with rescue off"
		else:
			var sim: Sim = _sim([NEAR] as Array[Vector3i])
			view.show_miners(sim.rescue, sim.ships[0], null, 0.0)
			if not view.label.showing(NEAR):
				problem = "MinerView did not pass the miners on"
	view.free()
	return problem
