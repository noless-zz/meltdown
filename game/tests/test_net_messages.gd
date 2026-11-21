extends RefCounted

## `NetMessages` round-trips every message exactly and refuses malformed
## packets whole (MP-2, MP-7, MP-11, ARC-2).


func _same_input(a: ShipInput, b: ShipInput) -> String:
	for field: String in NetMessages.VECTOR_FIELDS + NetMessages.BOOL_FIELDS + [NetMessages.AIM_FIELD]:
		if a.get(field) != b.get(field):
			return "%s: sent %s, received %s" % [field, a.get(field), b.get(field)]
	return ""


func _round_trip_input(tick: int, ship: int, input: ShipInput) -> String:
	var bytes: PackedByteArray = NetMessages.encode_input(tick, ship, input)
	if bytes.is_empty():
		return "encode refused a valid input"
	var message: Dictionary = NetMessages.decode(bytes)
	if message.has("error"):
		return "decode failed: %s" % message["error"]
	if message["type"] != NetMessages.TYPE_INPUT or message["tick"] != tick or message["ship"] != ship:
		return "header came back as %s" % message
	return _same_input(input, message["input"])


func _expect_error(bytes: PackedByteArray, text: String) -> String:
	var message: Dictionary = NetMessages.decode(bytes)
	if not message.has("error"):
		return "decoded %s without an error" % message
	if message.size() != 1:
		return "an error came back with other fields: %s" % message
	if not String(message["error"]).contains(text):
		return "error '%s' does not mention '%s'" % [message["error"], text]
	return ""


func test_hello_round_trip() -> String:
	for build: String in ["", "a1b2c3d", "0123456789abcdef0123456789abcdef01234567 ünïcode"]:
		var message: Dictionary = NetMessages.decode(NetMessages.encode_hello(build))
		if message.has("error"):
			return "hello '%s' failed: %s" % [build, message["error"]]
		if message["type"] != NetMessages.TYPE_HELLO or message["build"] != build:
			return "hello '%s' came back as %s" % [build, message]
		if message["protocol"] != NetMessages.PROTOCOL_VERSION:
			return "protocol came back as %s" % message["protocol"]
	return ""


func test_hello_with_another_protocol_reports_the_mismatch() -> String:
	var other: int = NetMessages.PROTOCOL_VERSION + 1
	var result: String = _expect_error(NetMessages.encode_hello("abc", other), "protocol version mismatch")
	if not result.is_empty():
		return result
	var error: String = NetMessages.decode(NetMessages.encode_hello("abc", other))["error"]
	if not error.contains(str(other)) or not error.contains(str(NetMessages.PROTOCOL_VERSION)):
		return "mismatch error '%s' does not name both versions" % error
	return ""


func test_hello_refuses_an_overlong_build() -> String:
	if not NetMessages.encode_hello("x".repeat(NetMessages.MAX_BUILD_BYTES)).size() > 0:
		return "the longest allowed build was refused"
	if not NetMessages.encode_hello("x".repeat(NetMessages.MAX_BUILD_BYTES + 1)).is_empty():
		return "an overlong build was encoded"
	return ""


func test_input_round_trip_idle_and_typical() -> String:
	var inputs: Array[ShipInput] = [
		ShipInput.new(),
		ShipInput.new(Vector3i(250, -500, -1000), Vector3i(1200, -800, 30), true),
	]
	for input: ShipInput in inputs:
		var result: String = _round_trip_input(1234, 2, input)
		if not result.is_empty():
			return result
	return ""


func test_input_round_trip_extreme_values() -> String:
	var largest: int = 0x7FFFFFFF
	var smallest: int = -0x80000000
	var maxed: ShipInput = ShipInput.new(
			Vector3i(1000, 1000, 1000), Vector3i(largest, largest, largest), true, true, true)
	var minned: ShipInput = ShipInput.new(
			Vector3i(-1000, -1000, -1000), Vector3i(smallest, smallest, smallest))
	for input: ShipInput in [maxed, minned]:
		# Plain ints rather than Vector2i, whose 32-bit axes cannot hold MAX_TICK.
		for header: Array[int] in [[0, 0] as Array[int], [NetMessages.MAX_TICK, NetMessages.MAX_SHIP_INDEX] as Array[int]]:
			var result: String = _round_trip_input(header[0], header[1], input)
			if not result.is_empty():
				return "%s (tick %d, ship %d)" % [result, header[0], header[1]]
	return ""


func test_each_bool_travels_on_its_own() -> String:
	for field: String in NetMessages.BOOL_FIELDS:
		var input: ShipInput = ShipInput.new()
		input.set(field, true)
		var result: String = _round_trip_input(7, 1, input)
		if not result.is_empty():
			return "only %s set: %s" % [field, result]
	return ""


func test_input_packet_is_at_most_32_bytes() -> String:
	var bytes: PackedByteArray = NetMessages.encode_input(
			NetMessages.MAX_TICK, 3, ShipInput.new(Vector3i(1000, -1000, 1000), Vector3i(-1, 2, -3), true, true, true))
	if bytes.size() > 32:
		return "input packet is %d bytes" % bytes.size()
	# 60 packets a second must stay far under MP-7's 128 kbps upstream.
	if bytes.size() * 8 * 60 > 128000 / 4:
		return "input stream is %d bps" % (bytes.size() * 8 * 60)
	return ""


func test_net_messages_carries_every_ship_input_property() -> String:
	var carried: Array[String] = NetMessages.VECTOR_FIELDS + NetMessages.BOOL_FIELDS
	carried.append(NetMessages.AIM_FIELD)
	var declared: Array[String] = []
	for property: Dictionary in ShipInput.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			declared.append(property["name"])
	if declared.is_empty():
		return "found no script properties on ShipInput"
	for name: String in declared:
		if not carried.has(name):
			return "ShipInput.%s is not carried by NetMessages" % name
	for name: String in carried:
		if not declared.has(name):
			return "NetMessages carries %s, which ShipInput does not declare" % name
	return ""


func test_encode_input_refuses_values_that_do_not_fit() -> String:
	var ok: ShipInput = ShipInput.new()
	var cases: Dictionary = {
		"negative tick": NetMessages.encode_input(-1, 0, ok),
		"tick over u32": NetMessages.encode_input(NetMessages.MAX_TICK + 1, 0, ok),
		"negative ship": NetMessages.encode_input(0, -1, ok),
		"ship over u8": NetMessages.encode_input(0, NetMessages.MAX_SHIP_INDEX + 1, ok),
		"null input": NetMessages.encode_input(0, 0, null),
		"thrust 1001": NetMessages.encode_input(0, 0, ShipInput.new(Vector3i(0, 1001, 0))),
	}
	for name: String in cases:
		if not (cases[name] as PackedByteArray).is_empty():
			return "%s was encoded" % name
	return ""


func test_state_hash_round_trip() -> String:
	var sim: Sim = Sim.new(42)
	for value: int in [0, sim.state_hash(), -1, 0x7FFFFFFFFFFFFFFF, -0x7FFFFFFFFFFFFFFF - 1]:
		for tick: int in [0, 99, NetMessages.MAX_TICK]:
			var message: Dictionary = NetMessages.decode(NetMessages.encode_state_hash(tick, value))
			if message.has("error"):
				return "hash %d failed: %s" % [value, message["error"]]
			if message["type"] != NetMessages.TYPE_STATE_HASH or message["tick"] != tick or message["hash"] != value:
				return "hash %d at tick %d came back as %s" % [value, tick, message]
	if not NetMessages.encode_state_hash(-1, 0).is_empty():
		return "a negative tick was encoded"
	return ""


func test_truncated_packets_are_refused_whole() -> String:
	var packets: Dictionary = {
		"hello": NetMessages.encode_hello("abcdef"),
		"input": NetMessages.encode_input(5, 1, ShipInput.new(Vector3i(1, 2, 3), Vector3i(4, 5, 6), true)),
		"state_hash": NetMessages.encode_state_hash(5, 123456),
	}
	for name: String in packets:
		var bytes: PackedByteArray = packets[name]
		for size: int in range(1, bytes.size()):
			var result: String = _expect_error(bytes.slice(0, size), "truncated " + name)
			if not result.is_empty():
				return "%s cut to %d bytes: %s" % [name, size, result]
	return _expect_error(PackedByteArray(), "empty")


func test_oversized_packets_are_refused_whole() -> String:
	var packets: Dictionary = {
		"hello": NetMessages.encode_hello("abcdef"),
		"input": NetMessages.encode_input(5, 1, ShipInput.new()),
		"state_hash": NetMessages.encode_state_hash(5, 123456),
	}
	for name: String in packets:
		var bytes: PackedByteArray = (packets[name] as PackedByteArray).duplicate()
		bytes.append(0)
		var result: String = _expect_error(bytes, "oversized " + name)
		if not result.is_empty():
			return result
	return ""


func test_unknown_type_is_refused() -> String:
	for type: int in [0, 4, 255]:
		var result: String = _expect_error(PackedByteArray([type, 0, 0, 0, 0]), "unknown message type %d" % type)
		if not result.is_empty():
			return result
	return ""


func test_input_with_out_of_range_thrust_or_unknown_flags_is_refused() -> String:
	var bytes: PackedByteArray = NetMessages.encode_input(1, 0, ShipInput.new())
	var thrust: PackedByteArray = bytes.duplicate()
	thrust.encode_s32(6, 5000)
	var result: String = _expect_error(thrust, "thrust")
	if not result.is_empty():
		return result
	var flags: PackedByteArray = bytes.duplicate()
	flags.encode_u8(NetMessages.INPUT_SIZE - 1, 0x80)
	return _expect_error(flags, "unknown bits")
