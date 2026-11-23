class_name NetMessages
extends RefCounted

## The packets clients and host exchange, as pure encode and decode functions.
##
## No sockets or nodes here: the transport hands bytes in and out, so every
## format rule can be unit tested without a network (ARC-1). Inputs travel in
## `ShipInput`'s stored integer form, so the host simulates exactly the numbers
## the client flew (ARC-2, MP-2).
##
## Layout, all little-endian, byte 0 is the message type:
## - hello: type, protocol u16, build length u16, build UTF-8 bytes.
## - input: type, tick u32, ship u8, thrust 3 x s32, turn 3 x s32, flags u8
##   (31 bytes; 60 a second is about 15 kbps, far under MP-7's 128 kbps), then,
##   only when the aim is off the nose and the flags byte says so, aim 3 x s32
##   (43 bytes; CMB-6). A nose aim adds nothing, so most packets stay 31 bytes.
##   Flags: bits 0 to 3 the `BOOL_FIELDS`, bit 4 the aim follows, bits 5 and 6
##   the slot popup's choice (decision record 0011), bit 7 unused.
## - state_hash: type, tick u32, hash s64.
##
## `decode` returns either `{"error": String}` or a complete message with a
## `"type"` key; a malformed packet never yields a half-filled message.
## Protocol 3 added the aim (CMB-6), protocol 4 the slot choice.

## Raised whenever any packet layout changes, so mismatched builds refuse each
## other at hello instead of misreading inputs (MP-11).
const PROTOCOL_VERSION: int = 4

const TYPE_HELLO: int = 1
const TYPE_INPUT: int = 2
const TYPE_STATE_HASH: int = 3

const HELLO_HEADER_SIZE: int = 5
const MAX_BUILD_BYTES: int = 255
const INPUT_SIZE: int = 31
## An input packet that carries an aim.
const INPUT_AIM_SIZE: int = INPUT_SIZE + 12
const STATE_HASH_SIZE: int = 13
const MAX_TICK: int = 0xFFFFFFFF
const MAX_SHIP_INDEX: int = 255

## Every script property of `ShipInput`, in packet order. A test compares this
## with `ShipInput`'s property list, so a new input field cannot be dropped on
## the network unnoticed.
const VECTOR_FIELDS: Array[String] = ["thrust_q", "turn_q"]
## Packed as bits of the flags byte, bit 0 first.
const BOOL_FIELDS: Array[String] = ["afterburner", "reset_to_start", "fire_primary", "slot_held"]
## Carried after the flags byte only when it is off the nose; the flags byte's
## bit after the `BOOL_FIELDS` says it follows.
const AIM_FIELD: String = "aim_q"
const AIM_FLAG: int = 1 << 4
## `ShipInput.slot_choice`, 0 to 3, in the two flag bits above the aim's.
const SLOT_CHOICE_FIELD: String = "slot_choice"
const SLOT_CHOICE_SHIFT: int = 5
const SLOT_CHOICE_MASK: int = 3 << SLOT_CHOICE_SHIFT


## Empty array if `build` is longer than `MAX_BUILD_BYTES` in UTF-8.
static func encode_hello(build: String, protocol: int = PROTOCOL_VERSION) -> PackedByteArray:
	var text: PackedByteArray = build.to_utf8_buffer()
	if text.size() > MAX_BUILD_BYTES or protocol < 0 or protocol > 0xFFFF:
		return PackedByteArray()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(HELLO_HEADER_SIZE)
	bytes.encode_u8(0, TYPE_HELLO)
	bytes.encode_u16(1, protocol)
	bytes.encode_u16(3, text.size())
	bytes.append_array(text)
	return bytes


## Empty array if the tick, ship index or any input value does not fit the
## packet, rather than sending a value the host would read differently.
static func encode_input(tick: int, ship: int, input: ShipInput) -> PackedByteArray:
	if input == null or tick < 0 or tick > MAX_TICK or ship < 0 or ship > MAX_SHIP_INDEX:
		return PackedByteArray()
	# Vector3i is 32-bit per axis, so turn always fits its s32 fields.
	if not _thrust_in_range(input.thrust_q) or not ShipInput.aim_q_valid(input.aim_q) \
			or not ShipInput.slot_choice_valid(input.slot_choice):
		return PackedByteArray()
	var aimed: bool = input.aims_off_nose()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(INPUT_AIM_SIZE if aimed else INPUT_SIZE)
	bytes.encode_u8(0, TYPE_INPUT)
	bytes.encode_u32(1, tick)
	bytes.encode_u8(5, ship)
	var offset: int = 6
	for field: String in VECTOR_FIELDS:
		var value: Vector3i = input.get(field)
		for axis: int in 3:
			bytes.encode_s32(offset, value[axis])
			offset += 4
	var flags: int = 0
	for bit: int in BOOL_FIELDS.size():
		if input.get(BOOL_FIELDS[bit]):
			flags |= 1 << bit
	flags |= input.slot_choice << SLOT_CHOICE_SHIFT
	if aimed:
		flags |= AIM_FLAG
		for axis: int in 3:
			bytes.encode_s32(INPUT_SIZE + axis * 4, input.aim_q[axis])
	bytes.encode_u8(offset, flags)
	return bytes


## Empty array if the tick does not fit.
static func encode_state_hash(tick: int, state_hash: int) -> PackedByteArray:
	if tick < 0 or tick > MAX_TICK:
		return PackedByteArray()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(STATE_HASH_SIZE)
	bytes.encode_u8(0, TYPE_STATE_HASH)
	bytes.encode_u32(1, tick)
	bytes.encode_s64(5, state_hash)
	return bytes


## hello: `type`, `protocol`, `build`. input: `type`, `tick`, `ship`, `input`
## (a new `ShipInput`). state_hash: `type`, `tick`, `hash`. Otherwise `error`.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return _error("empty packet")
	var type: int = bytes.decode_u8(0)
	match type:
		TYPE_HELLO:
			return _decode_hello(bytes)
		TYPE_INPUT:
			return _decode_input(bytes)
		TYPE_STATE_HASH:
			return _decode_state_hash(bytes)
	return _error("unknown message type %d" % type)


static func _decode_hello(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HELLO_HEADER_SIZE:
		return _error("truncated hello: %d bytes, header needs %d" % [bytes.size(), HELLO_HEADER_SIZE])
	var length: int = bytes.decode_u16(3)
	var expected: int = HELLO_HEADER_SIZE + length
	var size_error: String = _size_error("hello", bytes.size(), expected)
	if not size_error.is_empty():
		return _error(size_error)
	var protocol: int = bytes.decode_u16(1)
	var build: String = bytes.slice(HELLO_HEADER_SIZE).get_string_from_utf8()
	if protocol != PROTOCOL_VERSION:
		return _error("protocol version mismatch: peer %d (build %s), this build %d"
				% [protocol, build, PROTOCOL_VERSION])
	return {"type": TYPE_HELLO, "protocol": protocol, "build": build}


static func _decode_input(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < INPUT_SIZE:
		return _error(_size_error("input", bytes.size(), INPUT_SIZE))
	var aimed: bool = bytes.decode_u8(INPUT_SIZE - 1) & AIM_FLAG != 0
	var size_error: String = _size_error("input", bytes.size(),
		INPUT_AIM_SIZE if aimed else INPUT_SIZE)
	if not size_error.is_empty():
		return _error(size_error)
	var input: ShipInput = ShipInput.new()
	var offset: int = 6
	for field: String in VECTOR_FIELDS:
		var value: Vector3i = Vector3i(
				bytes.decode_s32(offset), bytes.decode_s32(offset + 4), bytes.decode_s32(offset + 8))
		input.set(field, value)
		offset += 12
	if not _thrust_in_range(input.thrust_q):
		return _error("input thrust %s outside -%d..%d" % [input.thrust_q, ShipInput.SCALE, ShipInput.SCALE])
	var flags: int = bytes.decode_u8(offset)
	if flags & ~((1 << BOOL_FIELDS.size()) - 1) & ~AIM_FLAG & ~SLOT_CHOICE_MASK != 0:
		return _error("input flags 0x%02x set unknown bits" % flags)
	for bit: int in BOOL_FIELDS.size():
		input.set(BOOL_FIELDS[bit], flags & (1 << bit) != 0)
	input.slot_choice = (flags & SLOT_CHOICE_MASK) >> SLOT_CHOICE_SHIFT
	if aimed:
		var aim: Vector3i = Vector3i(bytes.decode_s32(INPUT_SIZE),
			bytes.decode_s32(INPUT_SIZE + 4), bytes.decode_s32(INPUT_SIZE + 8))
		# The nose is never sent, so one input has one packet (MP-2).
		if not ShipInput.aim_q_valid(aim) or aim == ShipInput.NOSE_AIM_Q:
			return _error("input aim %s must be off the nose, not zero, each axis within -%d..%d"
				% [aim, ShipInput.SCALE, ShipInput.SCALE])
		input.aim_q = aim
	return {"type": TYPE_INPUT, "tick": bytes.decode_u32(1), "ship": bytes.decode_u8(5), "input": input}


static func _decode_state_hash(bytes: PackedByteArray) -> Dictionary:
	var size_error: String = _size_error("state_hash", bytes.size(), STATE_HASH_SIZE)
	if not size_error.is_empty():
		return _error(size_error)
	return {"type": TYPE_STATE_HASH, "tick": bytes.decode_u32(1), "hash": bytes.decode_s64(5)}


static func _size_error(name: String, size: int, expected: int) -> String:
	if size < expected:
		return "truncated %s: %d bytes, expected %d" % [name, size, expected]
	if size > expected:
		return "oversized %s: %d bytes, expected %d" % [name, size, expected]
	return ""


static func _thrust_in_range(thrust_q: Vector3i) -> bool:
	for axis: int in 3:
		if absi(thrust_q[axis]) > ShipInput.SCALE:
			return false
	return true


static func _error(message: String) -> Dictionary:
	return {"error": message}
