class_name StressInputs
extends RefCounted

## One ship's scripted input in the stress scene (#1288, PRF-8, ARC-4): a list
## of segments flown in order, then again from `loop_from` for as long as the
## scene runs. The script is data, so the extra ships need no network and no
## code branch: the same rule turns the same tick into the same input (ARC-2).
##
## In `stress_scene.json`, one entry of `inputs`:
##
##     {"loop_from": 1, "segments": [
##         {"ticks": 40, "thrust": [0, 0, -0.6], "fire": true},
##         {"ticks": 150, "thrust": [0.4, 0, 0], "turn": [0, 0.3, 0]}]}
##
## `thrust` is ship-space thrust per axis, -1..1; `turn` is pitch, yaw and roll
## in radians per second, at most `MAX_TURN`; `fire` holds primary fire. A
## segment may leave any of the three out: it is then at rest or not firing.

const KEYS: Array[String] = ["segments"]
const OPTIONAL_KEYS: Array[String] = ["loop_from"]
const SEGMENT_KEYS: Array[String] = ["ticks"]
const OPTIONAL_SEGMENT_KEYS: Array[String] = ["thrust", "turn", "fire"]
## A turn rate above this is a typo, not a pilot (radians per second).
const MAX_TURN: float = 6.0

## Ticks of each segment, in order.
var ticks: Array[int] = []
## The input of each segment, already rounded to `ShipInput`'s integers, so
## the recording and the flight use exactly the same numbers.
var inputs: Array[ShipInput] = []
var loop_from: int = 0
## Why the entry was rejected; empty when it was read.
var error: String = ""


## Reads one `inputs` entry. On failure `error` names the field.
static func parse(value: Variant, field: String) -> StressInputs:
	var read: StressInputs = StressInputs.new()
	read.error = read._read(value, field)
	return read


## The input for `tick` (0 is the first tick of the scene).
func input_at(tick: int) -> ShipInput:
	var total: int = 0
	for index: int in ticks.size():
		total += ticks[index]
	var at: int = tick
	if at >= total:
		var loop_start: int = 0
		for index: int in loop_from:
			loop_start += ticks[index]
		at = loop_start + (at - total) % (total - loop_start)
	for index: int in ticks.size():
		if at < ticks[index]:
			return _copy(inputs[index])
		at -= ticks[index]
	return ShipInput.new()


static func _copy(input: ShipInput) -> ShipInput:
	var copy: ShipInput = ShipInput.new(input.thrust_q, input.turn_q)
	copy.fire_primary = input.fire_primary
	return copy


func _read(value: Variant, field: String) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "%s: must be a JSON object" % field
	var data: Dictionary = value
	var problem: String = StressScene.check_keys(data, KEYS, OPTIONAL_KEYS)
	if problem != "":
		return "%s: %s" % [field, problem]
	if typeof(data["segments"]) != TYPE_ARRAY or (data["segments"] as Array).is_empty():
		return "%s.segments: must be a non-empty list" % field
	var segments: Array = data["segments"]
	for index: int in segments.size():
		problem = _read_segment(segments[index])
		if problem != "":
			return "%s.segments[%d]: %s" % [field, index, problem]
	if data.has("loop_from"):
		var start: Variant = data["loop_from"]
		if typeof(start) != TYPE_INT and not (typeof(start) == TYPE_FLOAT and float(start) == floorf(float(start))):
			return "%s.loop_from: must be a whole number" % field
		loop_from = int(start)
		if loop_from < 0 or loop_from >= ticks.size():
			return "%s.loop_from: must name one of the %d segments" % [field, ticks.size()]
	return ""


func _read_segment(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be a JSON object"
	var data: Dictionary = value
	var problem: String = StressScene.check_keys(data, SEGMENT_KEYS, OPTIONAL_SEGMENT_KEYS)
	if problem != "":
		return problem
	var count: Variant = data["ticks"]
	if (typeof(count) != TYPE_INT and typeof(count) != TYPE_FLOAT) or float(count) < 1.0 \
			or float(count) != floorf(float(count)):
		return "ticks: must be a whole number from 1 up"
	var read: Array[Vector3] = []
	for key: String in ["thrust", "turn"]:
		var limit: float = 1.0 if key == "thrust" else MAX_TURN
		problem = StressScene.read_vector(data.get(key, [0.0, 0.0, 0.0]), key, read)
		if problem != "":
			return problem
		var axes: Vector3 = read[-1].abs()
		if axes.x > limit or axes.y > limit or axes.z > limit:
			return "%s: each axis must be -%s to %s" % [key, limit, limit]
	if data.has("fire") and typeof(data["fire"]) != TYPE_BOOL:
		return "fire: must be true or false"
	var input: ShipInput = ShipInput.from_floats(read[0], read[1])
	input.fire_primary = data.get("fire", false)
	ticks.append(int(count))
	inputs.append(input)
	return ""
