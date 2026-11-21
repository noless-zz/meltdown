class_name RunPlan
extends RefCounted

## A run as a chain of levels drawn from one run seed (RUN-1, GEN-2, #926):
## how many levels it has and each level's generator seed and depth. Read from
## `data/run/run.json`; core opens no files, so the caller hands the text to
## `build`.
##
## The seeds come from a documented integer mix, never from a random number
## generator or the clock (ARC-2), and use only 32-bit arithmetic with masks, so
## every device gets the same plan for the same run seed (GEN-2):
##
## - `base` folds the 64-bit run seed into 32 bits: its low 32 bits XOR
##   `fmix32` of its high 32 bits (a run seed from 0 to 2^32 - 1 is its own base).
## - The level count is `min_levels + fmix32(base) % (max_levels - min_levels + 1)`.
## - Level `i` (0-based) has seed `fmix32((base + (i + 1) * seed_salt) mod 2^32)`.
##
## `fmix32` is the MurmurHash3 finaliser, a bijection on 32-bit values, and the
## salt must be odd, so the inputs of one run's levels differ and no two levels
## of a run share a seed.

## Every key of the data file, in the order the file lists them.
const KEYS: Array[String] = ["min_levels", "max_levels", "seed_salt"]
## Most levels a run may have; keeps every `(i + 1) * seed_salt` far below 2^63.
const MOST_LEVELS: int = 16
const MASK_32: int = 0xFFFFFFFF

## Fewest levels in a run, 1..`max_levels`.
var min_levels: int = 3
## Most levels in a run, `min_levels`..`MOST_LEVELS`.
var max_levels: int = 5
## Odd integer, 1..2^32 - 1, stepping one level's mix input to the next.
var seed_salt: int = 2654435769
## The run seed this plan was built from.
var run_seed: int = 0
## Each level's generator seed, by 0-based level index; level `i` has depth `i + 1`.
var level_seeds: Array[int] = []
## Set by `build` when the text was rejected; empty otherwise, and then
## `level_seeds` is empty.
var error: String = ""


## Parses the text of a run data file and builds the plan for `p_run_seed`.
## A missing, unknown or out-of-range key is an error that names the key.
static func build(p_run_seed: int, text: String) -> RunPlan:
	var plan: RunPlan = RunPlan.new()
	plan.run_seed = p_run_seed
	plan.error = plan._parse(text)
	if plan.error == "":
		plan._draw()
	return plan


func level_count() -> int:
	return level_seeds.size()


## Generator seed of the level at `index` (0-based).
func level_seed(index: int) -> int:
	return level_seeds[index]


## 1-based depth of the level at `index`: the first level is depth 1.
func depth(index: int) -> int:
	return index + 1


## Shafts offered after the level at `index` (RUN-1, #927): 2 or 3 kinds of
## `shafts`, drawn from that level's seed, so from the run seed and the index.
## None after the last level or for an index outside the plan.
func offer_after(index: int, shafts: ShaftOffer) -> Array[String]:
	if index < 0 or index + 1 >= level_count():
		return []
	return shafts.draw(level_seed(index))


## Generator seed of the level at `index` (1 or more) when it is reached through
## the shaft `kind`; -1 for index 0, an index outside the plan or an unknown kind.
func level_seed_through(index: int, shafts: ShaftOffer, kind: String) -> int:
	if index < 1 or index >= level_count():
		return -1
	return shafts.seed_for(level_seed(index), kind)


func plan_hash() -> int:
	return hash([run_seed, level_seeds])


## The MurmurHash3 32-bit finaliser on a value 0..2^32 - 1.
static func fmix32(value: int) -> int:
	var h: int = value & MASK_32
	h ^= h >> 16
	h = _mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = _mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h


## `a * b mod 2^32` for values 0..2^32 - 1, in 16-bit halves so no product
## leaves 64-bit range (integer overflow is not something to lean on).
static func _mul32(a: int, b: int) -> int:
	var low: int = a * (b & 0xFFFF)
	var high: int = ((a * (b >> 16)) & 0xFFFF) << 16
	return (low + high) & MASK_32


static func _fold(value: int) -> int:
	return (value & MASK_32) ^ fmix32((value >> 32) & MASK_32)


func _draw() -> void:
	var base: int = _fold(run_seed)
	var count: int = min_levels + fmix32(base) % (max_levels - min_levels + 1)
	level_seeds.clear()
	for i: int in count:
		level_seeds.append(fmix32((base + (i + 1) * seed_salt) & MASK_32))


func _parse(text: String) -> String:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "top level must be a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	var values: Dictionary = {}
	for key: String in KEYS:
		if not data.has(key):
			return "missing key \"%s\"" % key
		var value: Variant = data[key]
		# JSON numbers may arrive as floats; a bool must not pass as 0 or 1.
		if typeof(value) == TYPE_INT:
			values[key] = value
		elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
			values[key] = int(value)
		else:
			return "key \"%s\" must be a whole number" % key
	min_levels = values["min_levels"]
	max_levels = values["max_levels"]
	seed_salt = values["seed_salt"]
	if min_levels < 1 or min_levels > max_levels:
		return "key \"min_levels\" is %d, must be 1 to max_levels (%d)" % [min_levels, max_levels]
	if max_levels > MOST_LEVELS:
		return "key \"max_levels\" is %d, must be at most %d" % [max_levels, MOST_LEVELS]
	if seed_salt < 1 or seed_salt > MASK_32 or seed_salt % 2 == 0:
		return "key \"seed_salt\" is %d, must be odd and 1 to %d" % [seed_salt, MASK_32]
	return ""
