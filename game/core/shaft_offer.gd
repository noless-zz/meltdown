class_name ShaftOffer
extends RefCounted

## The shafts a player may take between levels, each with shown risks and
## rewards (RUN-1, CRF-7, #927), read from `data/run/shafts.json` so a new
## shaft is a data entry, not code (ARC-4). Core opens no files, so the caller
## hands the text to `build`.
##
## `risk` holds multipliers on the next level's robot count and alarm, and
## `reward` the weights of component tiers 1..3, which weigh the next level's
## component drops (`ComponentPickup`, #1000); the robot count multiplier is not
## wired yet. Draws use only `RunPlan.fmix32` and masked 32-bit
## arithmetic, never a random number generator (ARC-2, GEN-2):
##
## - An offer from input seed `s` starts at `h = fmix32(s + seed_salt)`; its size
##   is `offer_min + h % (offer_max - offer_min + 1)`. Each pick steps
##   `h = fmix32(h + seed_salt)` and takes `h % remaining` from the kinds not yet
##   offered, in file order, so one offer never repeats a kind.
## - The level reached through the kind at file position `k` from base seed `b`
##   has seed `fmix32(b + (k + 1) * seed_salt)`. The salt is odd and `fmix32` a
##   bijection, so different shafts give different seeds.

## Every key of the data file's top level and of one shaft entry.
const KEYS: Array[String] = ["offer_min", "offer_max", "seed_salt", "shafts"]
const SHAFT_KEYS: Array[String] = ["kind", "label", "risk", "reward"]
const RISK_KEYS: Array[String] = ["robot_count", "alarm"]
const REWARD_KEYS: Array[String] = ["tier_weights"]
## Component tiers run 1..3 (`ComponentDef.TIER_MAX`).
const TIERS: int = 3
const OFFER_FEWEST: int = 2
const OFFER_MOST: int = 3
const LABEL_MAX_LENGTH: int = 64
const MULTIPLIER_MAX: float = 10.0

## Fewest and most shafts in one offer, within 2..3 (RUN-1).
var offer_min: int = 2
var offer_max: int = 3
## Odd integer, 1..2^32 - 1, used by both mixes above.
var seed_salt: int = 1
## Shaft kinds in file order; the order is part of the seed mix.
var kinds: Array[String] = []
## Short original label per kind, shown to the player later.
var labels: Dictionary = {}
## Per kind: {"robot_count": float, "alarm": float}.
var risks: Dictionary = {}
## Per kind: weights of tiers 1..3, Array[float].
var rewards: Dictionary = {}
## Set by `build` when the text was rejected; empty otherwise, and then `kinds`
## is empty.
var error: String = ""


static func build(text: String) -> ShaftOffer:
	var offer: ShaftOffer = ShaftOffer.new()
	offer.error = offer._parse(text)
	if offer.error != "":
		offer.kinds.clear()
		offer.labels.clear()
		offer.risks.clear()
		offer.rewards.clear()
	return offer


## The kinds offered from input seed `input`, 2 or 3 of them, never repeated.
func draw(input: int) -> Array[String]:
	var offered: Array[String] = []
	if kinds.is_empty():
		return offered
	var h: int = RunPlan.fmix32((input + seed_salt) & RunPlan.MASK_32)
	var size: int = offer_min + h % (offer_max - offer_min + 1)
	var pool: Array[String] = kinds.duplicate()
	for i: int in size:
		h = RunPlan.fmix32((h + seed_salt) & RunPlan.MASK_32)
		var pick: int = h % pool.size()
		offered.append(pool[pick])
		pool.remove_at(pick)
	return offered


## Seed of the level reached through `kind` from base seed `base`; -1 for a kind
## the file does not have.
func seed_for(base: int, kind: String) -> int:
	var position: int = kinds.find(kind)
	if position < 0:
		return -1
	return RunPlan.fmix32((base + (position + 1) * seed_salt) & RunPlan.MASK_32)


func _parse(text: String) -> String:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "top level must be a JSON object"
	var data: Dictionary = json.data
	var message: String = _check_keys(data, KEYS, "")
	if message != "":
		return message
	for key: String in ["offer_min", "offer_max", "seed_salt"]:
		if not _is_whole(data[key]):
			return "key \"%s\" must be a whole number" % key
	offer_min = int(data["offer_min"])
	offer_max = int(data["offer_max"])
	seed_salt = int(data["seed_salt"])
	if offer_min < OFFER_FEWEST or offer_min > offer_max:
		return "key \"offer_min\" is %d, must be %d to offer_max (%d)" % [offer_min, OFFER_FEWEST, offer_max]
	if offer_max > OFFER_MOST:
		return "key \"offer_max\" is %d, must be at most %d" % [offer_max, OFFER_MOST]
	if seed_salt < 1 or seed_salt > RunPlan.MASK_32 or seed_salt % 2 == 0:
		return "key \"seed_salt\" is %d, must be odd and 1 to %d" % [seed_salt, RunPlan.MASK_32]
	if typeof(data["shafts"]) != TYPE_ARRAY:
		return "key \"shafts\" must be an array"
	var entries: Array = data["shafts"]
	for i: int in entries.size():
		message = _parse_shaft(entries[i], "shafts[%d]" % i)
		if message != "":
			return message
	if kinds.size() < offer_max:
		return "key \"shafts\" has %d kinds, offer_max needs %d" % [kinds.size(), offer_max]
	return ""


func _parse_shaft(entry: Variant, where: String) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "key \"%s\" must be an object" % where
	var message: String = _check_keys(entry, SHAFT_KEYS, where + ".")
	if message != "":
		return message
	message = ComponentDef.check_id(where + ".kind", entry["kind"])
	if message != "":
		return message
	var kind: String = entry["kind"]
	if kinds.has(kind):
		return "key \"%s.kind\" repeats \"%s\"" % [where, kind]
	var label: Variant = entry["label"]
	if typeof(label) != TYPE_STRING or (label as String).strip_edges() == "" \
			or (label as String).length() > LABEL_MAX_LENGTH:
		return "key \"%s.label\" must be text of 1 to %d characters" % [where, LABEL_MAX_LENGTH]
	if typeof(entry["risk"]) != TYPE_DICTIONARY:
		return "key \"%s.risk\" must be an object" % where
	var risk: Dictionary = entry["risk"]
	message = _check_keys(risk, RISK_KEYS, where + ".risk.")
	if message != "":
		return message
	var parsed_risk: Dictionary = {}
	for key: String in RISK_KEYS:
		var value: Variant = risk[key]
		if not _is_number(value) or float(value) <= 0.0 or float(value) > MULTIPLIER_MAX:
			return "key \"%s.risk.%s\" must be a number above 0 and at most %s" % [where, key, MULTIPLIER_MAX]
		parsed_risk[key] = float(value)
	if typeof(entry["reward"]) != TYPE_DICTIONARY:
		return "key \"%s.reward\" must be an object" % where
	var reward: Dictionary = entry["reward"]
	message = _check_keys(reward, REWARD_KEYS, where + ".reward.")
	if message != "":
		return message
	var weights: Variant = reward["tier_weights"]
	var bad: String = "key \"%s.reward.tier_weights\" must be %d numbers of 0 or more, not all 0" % [where, TIERS]
	if typeof(weights) != TYPE_ARRAY or (weights as Array).size() != TIERS:
		return bad
	var parsed_weights: Array[float] = []
	var total: float = 0.0
	for weight: Variant in weights:
		if not _is_number(weight) or float(weight) < 0.0:
			return bad
		parsed_weights.append(float(weight))
		total += float(weight)
	if total <= 0.0:
		return bad
	kinds.append(kind)
	labels[kind] = label
	risks[kind] = parsed_risk
	rewards[kind] = parsed_weights
	return ""


## An unknown or missing key in `data`, named with its path `prefix`.
static func _check_keys(data: Dictionary, keys: Array[String], prefix: String) -> String:
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not keys.has(key):
			return "unknown key \"%s%s\"" % [prefix, str(key)]
	for key: String in keys:
		if not data.has(key):
			return "missing key \"%s%s\"" % [prefix, key]
	return ""


## A finite JSON number; a bool must not pass as 0 or 1.
static func _is_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value)


static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value)
