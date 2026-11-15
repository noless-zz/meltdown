extends RefCounted

## `LatestInputSource` hands the latest input to every tick as a fresh object,
## so the replay keeps what each tick actually flew (ARC-2, MP-2).


func _same_values(a: ShipInput, b: ShipInput) -> bool:
	return a.thrust_q == b.thrust_q and a.turn_q == b.turn_q and a.afterburner == b.afterburner


func test_idle_until_an_input_is_set() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	if not _same_values(source.next_input(0), ShipInput.new()):
		return "a new source did not fly idle input"
	return ""


func test_set_input_is_returned_on_every_tick() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	var input: ShipInput = ShipInput.new(Vector3i(100, -200, -1000), Vector3i(5, 6, 7), true)
	source.set_input(input)
	for tick: int in 5:
		if not _same_values(source.next_input(tick), input):
			return "tick %d did not return the set input" % tick
	return ""


func test_every_call_returns_a_new_object() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	var input: ShipInput = ShipInput.new(Vector3i(0, 0, -1000))
	source.set_input(input)
	var first: ShipInput = source.next_input(0)
	var second: ShipInput = source.next_input(1)
	if is_same(first, second):
		return "two ticks got the same object"
	if is_same(first, input) or is_same(second, input):
		return "a tick got the caller's own object"
	return ""


func test_changing_the_callers_object_later_changes_nothing() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	var input: ShipInput = ShipInput.new(Vector3i(0, 0, -1000))
	source.set_input(input)
	input.thrust_q = Vector3i(1000, 0, 0)
	if source.next_input(0).thrust_q != Vector3i(0, 0, -1000):
		return "editing the set object changed the stored input"
	return ""


func test_null_input_means_idle() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	source.set_input(null)
	if not _same_values(source.next_input(0), ShipInput.new()):
		return "setting null did not return to idle"
	return ""


func test_replay_holds_one_distinct_input_per_tick() -> String:
	var source: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LocalSession.new(3, source)
	source.set_input(ShipInput.new(Vector3i(0, 0, -1000)))
	for i: int in 45:
		session.advance(1.0 / 90.0)
	# A later change must not reach the ticks already recorded.
	source.set_input(ShipInput.new(Vector3i(1000, 0, 0)))
	for i: int in 45:
		session.advance(1.0 / 90.0)
	var frames: Array[Array] = session.replay.frames
	if frames.size() != 60:
		return "expected 60 recorded ticks, found %d" % frames.size()
	for i: int in frames.size():
		for j: int in range(i + 1, frames.size()):
			if is_same(frames[i][0], frames[j][0]):
				return "ticks %d and %d share one input object" % [i, j]
	var first: ShipInput = frames[0][0]
	var last: ShipInput = frames[59][0]
	if first.thrust_q != Vector3i(0, 0, -1000) or last.thrust_q != Vector3i(1000, 0, 0):
		return "recorded inputs do not match what was set when each tick ran"
	var replayed: Sim = session.replay.run()
	if replayed == null or replayed.state_hash() != session.sim.state_hash():
		return "the replay does not reproduce the live session"
	return ""
