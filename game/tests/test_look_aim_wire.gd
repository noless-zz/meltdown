extends RefCounted

## The aim in replays and network inputs (CMB-6, ARC-2, MP-2, #922): carried
## only when off the nose, round-tripped exactly.


static func _aimed(aim_q: Vector3i) -> ShipInput:
	var input: ShipInput = ShipInput.new(Vector3i(0, 0, -500), Vector3i(0, 100, 0), false, false, true)
	input.aim_q = aim_q
	return input


func test_a_replay_with_aim_round_trips_through_text_exactly() -> String:
	var replay: Replay = Replay.new(3, 2)
	replay.look_aim = LookAim.parse_json("{\"cone_degrees\": 40.5, \"gimbal_degrees_per_second\": 200}")
	var off: Vector3i = ShipInput.aim_q_from(Vector3(0.17, -0.05, -1.0))
	var frame: Array[ShipInput] = [_aimed(off), ShipInput.new()]
	replay.add_tick(frame)
	var text: String = replay.to_text()
	var back: Replay = Replay.from_text(text)
	if back.error != "":
		return back.error
	if back.to_text() != text:
		return "text changed on a round trip:\n%s\n%s" % [text, back.to_text()]
	var got: ShipInput = back.frames[0][0]
	if got.aim_q != off or (back.frames[0][1] as ShipInput).aims_off_nose():
		return "aims came back as %s and %s" % [got.aim_q, (back.frames[0][1] as ShipInput).aim_q]
	if back.look_aim == null or back.look_aim.values_hash() != replay.look_aim.values_hash():
		return "the aim line did not come back"
	if not text.contains("aim {") or text.split("\n")[0] != "meltdown-replay 17":
		return "unexpected text:\n%s" % text
	return ""


func test_a_nose_aim_writes_ten_numbers() -> String:
	var replay: Replay = Replay.new(1, 1)
	var frame: Array[ShipInput] = [ShipInput.new()]
	replay.add_tick(frame)
	var lines: PackedStringArray = replay.to_text().strip_edges().split("\n")
	if lines[lines.size() - 1].split(" ").size() != 10:
		return "a nose tick wrote '%s'" % lines[lines.size() - 1]
	return ""


func test_replays_with_bad_aims_are_refused() -> String:
	var head: String = "meltdown-replay 17\nseed 1\nships 1\ninputs\n"
	var cases: Dictionary = {
		head + "0 0 0 0 0 0 0 0 0 0 0 0 0\n": "aim",
		head + "0 0 0 0 0 0 0 0 0 0 0 0 -1000\n": "off the nose",
		head + "0 0 0 0 0 0 0 0 0 0 2000 0 -1000\n": "aim",
		head + "0 0 0 0 0 0 0 0 0 0 1 2\n": "or 13 with an aim",
		"meltdown-replay 16\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0 0 0 0 100 0 -990\n": "needs 10",
		"meltdown-replay 16\nseed 1\nships 1\naim {}\ninputs\n": "version 17",
	}
	for text: String in cases:
		var replay: Replay = Replay.from_text(text)
		if not replay.error.contains(cases[text]):
			return "%s gave '%s', expected '%s'" % [text.c_escape(), replay.error, cases[text]]
	return ""


func test_a_replay_with_aim_runs_to_the_live_hash() -> String:
	var replay: Replay = Replay.new(5, 1)
	replay.look_aim = LookAim.new()
	var sim: Sim = Sim.new(5, 1)
	for tick: int in 60:
		var input: ShipInput = _aimed(ShipInput.aim_q_from(Vector3(0.3, 0.0, -1.0)))
		var frame: Array[ShipInput] = [input]
		replay.add_tick(frame)
		sim.step(frame)
	var back: Replay = Replay.from_text(replay.to_text())
	var flown: Sim = back.run()
	if flown == null:
		return back.run_error
	if flown.state_hash() != sim.state_hash():
		return "the replay flew to %d, live %d" % [flown.state_hash(), sim.state_hash()]
	return ""


func test_a_network_input_carries_the_aim_only_off_the_nose() -> String:
	var plain: PackedByteArray = NetMessages.encode_input(9, 1, ShipInput.new())
	if plain.size() != NetMessages.INPUT_SIZE:
		return "a nose input is %d bytes" % plain.size()
	var off: Vector3i = ShipInput.aim_q_from(Vector3(-0.2, 0.1, -1.0))
	var bytes: PackedByteArray = NetMessages.encode_input(9, 1, _aimed(off))
	if bytes.size() != NetMessages.INPUT_AIM_SIZE:
		return "an aimed input is %d bytes" % bytes.size()
	var message: Dictionary = NetMessages.decode(bytes)
	if message.has("error"):
		return message["error"]
	var got: ShipInput = message["input"]
	if got.aim_q != off or not got.fire_primary or got.thrust_q != Vector3i(0, 0, -500):
		return "decoded %s, %s, %s" % [got.aim_q, got.fire_primary, got.thrust_q]
	var nose: ShipInput = NetMessages.decode(plain)["input"]
	if nose.aims_off_nose():
		return "a nose packet decoded to aim %s" % nose.aim_q
	return ""


func test_malformed_aim_packets_are_refused() -> String:
	var off: Vector3i = ShipInput.aim_q_from(Vector3(0.2, 0.0, -1.0))
	var bytes: PackedByteArray = NetMessages.encode_input(1, 0, _aimed(off))
	var short: PackedByteArray = bytes.slice(0, NetMessages.INPUT_SIZE)
	if not NetMessages.decode(short).get("error", "").contains("truncated input"):
		return "an aim flag without the aim decoded: %s" % NetMessages.decode(short)
	var nose: PackedByteArray = bytes.duplicate()
	nose.encode_s32(NetMessages.INPUT_SIZE, 0)
	nose.encode_s32(NetMessages.INPUT_SIZE + 4, 0)
	nose.encode_s32(NetMessages.INPUT_SIZE + 8, -ShipInput.SCALE)
	if not NetMessages.decode(nose).get("error", "").contains("off the nose"):
		return "a nose aim sent as an aim decoded: %s" % NetMessages.decode(nose)
	var bad: ShipInput = _aimed(Vector3i(5000, 0, 0))
	if not NetMessages.encode_input(1, 0, bad).is_empty():
		return "an oversized aim was encoded"
	return ""
