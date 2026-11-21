extends RefCounted

## A replay carries a whole multi-box level (#286, GEN-5, ARC-2, DEV-1): several
## box lines, in order, read back as one `BoxUnion`, and a run in that union
## replays to the same hash. A one-box replay reads exactly as before.

const G2_LEVEL: String = "res://data/levels/g2_level.json"
const SEED: int = 286
const ONE_BOX_V11: String = "meltdown-replay 11\nseed 1\nships 1\n" \
	+ "box -5000 -4000 -40000 5000 4000 1\ninputs\n0 0 -1000 0 0 0 0 0 0 0\n"


func _g2() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))


func _mm(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * Replay.BOX_SCALE), roundi(point.y * Replay.BOX_SCALE),
		roundi(point.z * Replay.BOX_SCALE))


## A replay carrying every box of `union`, in order.
func _replay_of(union: BoxUnion) -> Replay:
	var mins: Array[Vector3i] = []
	var maxs: Array[Vector3i] = []
	for box: BoxBounds in union.boxes:
		mins.append(_mm(box.min_corner))
		maxs.append(_mm(box.max_corner))
	var replay: Replay = Replay.new(SEED, 1)
	replay.set_boxes(mins, maxs)
	return replay


## "" when `a` and `b` hold the same boxes, corner for corner, in order.
func _same_union(a: BoxUnion, b: BoxUnion) -> String:
	if a == null or b == null:
		return "a union is null"
	if a.boxes.size() != b.boxes.size():
		return "%d boxes, expected %d" % [a.boxes.size(), b.boxes.size()]
	for index: int in a.boxes.size():
		var x: BoxBounds = a.boxes[index]
		var y: BoxBounds = b.boxes[index]
		if x.min_corner != y.min_corner or x.max_corner != y.max_corner:
			return "box %d is %s..%s, expected %s..%s" % [index, x.min_corner, x.max_corner,
				y.min_corner, y.max_corner]
	return ""


## Thrust ahead into the shaft below the start room, then down it, so the ship
## ends in box 1 of the G2 level, outside box 0, after hitting walls there.
func _frames() -> Array[Array]:
	var frames: Array[Array] = []
	for tick: int in 600:
		var thrust: Vector3i = Vector3i(0, 0, -1000) if tick < 240 else Vector3i(0, -1000, 0)
		if tick >= 240 and tick < 270:
			thrust = Vector3i(0, 0, -1000)
		var inputs: Array[ShipInput] = [ShipInput.new(thrust, Vector3i.ZERO, tick % 90 < 45)]
		frames.append(inputs)
	return frames


func test_g2_boxes_written_and_read_back_give_the_same_union() -> String:
	var level: LevelDef = _g2()
	if level.error != "" or level.union.boxes.size() != 6:
		return "G2 level did not load with six boxes: " + level.error
	var text: String = _replay_of(level.union).to_text()
	if text.count("\nbox ") != 6:
		return "expected six box lines:\n" + text
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return "reload failed: " + loaded.error
	var problem: String = _same_union(loaded.walls(), level.union)
	if problem != "":
		return problem
	if loaded.to_text() != text:
		return "round trip changed the text:\n" + loaded.to_text()
	var first: BoxBounds = loaded.bounds()
	if first.min_corner != level.union.boxes[0].min_corner \
			or first.max_corner != level.union.boxes[0].max_corner:
		return "bounds() is not the first box"
	return ""


func test_a_live_run_in_g2_and_its_replay_end_on_the_same_hash() -> String:
	var level: LevelDef = _g2()
	var live: Sim = Sim.new(SEED, 1, null)
	if not live.set_walls(level.union):
		return "live sim refused the G2 walls"
	var replay: Replay = _replay_of(level.union)
	for frame: Array in _frames():
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		live.step(inputs)
		replay.add_tick(inputs)
	var ship: ShipState = live.ships[0]
	# Guard: the run must leave box 0, or a one-box replay would pass too.
	if level.union.boxes[0].holds(ship.position, ship.radius):
		return "ship never left box 0; ended at %s" % ship.position
	if not level.union.holds(ship.position, ship.radius):
		return "ship ended outside the union at %s" % ship.position
	replay.expected_hash = live.state_hash()
	var loaded: Replay = Replay.from_text(replay.to_text())
	if loaded.error != "":
		return "reload failed: " + loaded.error
	var replayed: Sim = loaded.run()
	if replayed == null:
		return "replay refused: " + loaded.run_error
	if _same_union(replayed.walls, level.union) != "":
		return "replayed sim walls: " + _same_union(replayed.walls, level.union)
	if replayed.state_hash() != loaded.expected_hash:
		return "replay hash %d, live %d" % [replayed.state_hash(), loaded.expected_hash]
	# Guard: with box 0 alone the same inputs end elsewhere.
	var one_box: Replay = Replay.from_text(replay.to_text())
	one_box.set_box(one_box.box_min_mm, one_box.box_max_mm)
	var single: Sim = one_box.run()
	if single == null or single.state_hash() == loaded.expected_hash:
		return "the run does not depend on boxes past box 0"
	return ""


func test_a_one_box_replay_reads_as_before() -> String:
	var replay: Replay = Replay.from_text(ONE_BOX_V11)
	if replay.error != "":
		return "version 11 one-box replay refused: " + replay.error
	if replay.box_mins_mm.size() != 1 or replay.walls().boxes.size() != 1:
		return "expected one box"
	if replay.box_min_mm != Vector3i(-5000, -4000, -40000) or replay.box_max_mm != Vector3i(5000, 4000, 1):
		return "box corners %s %s" % [replay.box_min_mm, replay.box_max_mm]
	var old_way: Sim = Sim.new(replay.run_seed, 1, replay.bounds())
	var inputs: Array[ShipInput] = []
	inputs.assign(replay.frames[0])
	old_way.step(inputs)
	var sim: Sim = replay.run()
	if sim == null or sim.state_hash() != old_way.state_hash():
		return "one-box replay runs differently from a sim built from bounds()"
	var lines: PackedStringArray = replay.to_text().split("\n")
	if lines[0] != "meltdown-replay %d" % ReplayRulesLine.PLAIN_VERSION or lines[3] != "box -5000 -4000 -40000 5000 4000 1":
		return "rewritten text:\n" + replay.to_text()
	return ""


func test_only_version_12_takes_several_box_lines() -> String:
	var two: String = "seed 1\nships 1\nbox 0 0 0 1 1 1\nbox 0 0 -5 1 1 1\ninputs\n"
	var old: Replay = Replay.from_text("meltdown-replay 11\n" + two)
	if old.error != "line 5: 'box' appears twice":
		return "version 11 gave '%s'" % old.error
	var newer: Replay = Replay.from_text("meltdown-replay 12\n" + two)
	if newer.error != "":
		return "version 12 refused: " + newer.error
	if newer.box_mins_mm.size() != 2 or newer.box_mins_mm[1] != Vector3i(0, 0, -5):
		return "boxes out of order: %s" % [newer.box_mins_mm]
	var bad: Replay = Replay.from_text("meltdown-replay 12\nseed 1\nships 1\nbox 0 0 0 1 1 1\nbox 0 0 0 1 1 0\ninputs\n")
	if bad.error != "line 5: box min corner must be below its max corner on every axis":
		return "bad second box gave '%s'" % bad.error
	return ""


func test_set_boxes_needs_matching_non_empty_lists() -> String:
	var replay: Replay = Replay.new()
	var none: Array[Vector3i] = []
	var one: Array[Vector3i] = [Vector3i.ZERO]
	var other: Array[Vector3i] = [Vector3i.ONE]
	if replay.set_boxes(none, none) or replay.set_boxes(one, none) or replay.has_box:
		return "accepted empty or mismatched lists"
	if replay.walls() != null:
		return "walls() is not null without boxes"
	if not replay.set_boxes(one, other) or replay.walls().boxes.size() != 1:
		return "refused one box"
	return ""
