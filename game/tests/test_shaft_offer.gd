extends RefCounted

## Shaft kinds from data and the seeded offer of two or three of them between
## levels (#927, RUN-1, CRF-7, ARC-4, ARC-2).

const SHAFTS: String = "res://data/run/shafts.json"
const RUN: String = "res://data/run/run.json"


func _shipped() -> ShaftOffer:
	return ShaftOffer.build(FileAccess.get_file_as_string(SHAFTS))


func _valid() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHAFTS))


func test_shipped_file_has_three_kinds() -> String:
	var shafts: ShaftOffer = _shipped()
	if shafts.error != "":
		return shafts.error
	var want: Array[String] = ["steady", "deep", "hot"]
	if shafts.kinds != want:
		return "shipped kinds %s" % shafts.kinds
	for kind: String in shafts.kinds:
		if shafts.labels[kind] == "" or shafts.risks[kind].size() != 2 \
				or shafts.rewards[kind].size() != ShaftOffer.TIERS:
			return "kind %s is not fully described" % kind
	return ""


func test_offers_are_deterministic_per_seed() -> String:
	var plan_text: String = FileAccess.get_file_as_string(RUN)
	for run_seed: int in [0, 7, -1, 123456789012]:
		var first: RunPlan = RunPlan.build(run_seed, plan_text)
		var second: RunPlan = RunPlan.build(run_seed, plan_text)
		for index: int in first.level_count():
			var a: Array[String] = first.offer_after(index, _shipped())
			var b: Array[String] = second.offer_after(index, _shipped())
			if a != b:
				return "run seed %d level %d offered %s then %s" % [run_seed, index, a, b]
	return ""


func test_thousand_runs_offer_two_or_three_distinct_shafts() -> String:
	var plan_text: String = FileAccess.get_file_as_string(RUN)
	var shafts: ShaftOffer = _shipped()
	var sizes: Dictionary = {}
	var seen_kinds: Dictionary = {}
	for run_seed: int in 1000:
		var plan: RunPlan = RunPlan.build(run_seed, plan_text)
		for index: int in plan.level_count():
			var offered: Array[String] = plan.offer_after(index, shafts)
			if index == plan.level_count() - 1:
				if not offered.is_empty():
					return "run seed %d offers shafts after its last level" % run_seed
				continue
			if offered.size() < 2 or offered.size() > 3:
				return "run seed %d level %d offers %d shafts" % [run_seed, index, offered.size()]
			var unique: Dictionary = {}
			for kind: String in offered:
				if unique.has(kind) or not shafts.kinds.has(kind):
					return "run seed %d level %d offers %s" % [run_seed, index, offered]
				unique[kind] = true
				seen_kinds[kind] = true
			sizes[offered.size()] = true
	if sizes.size() != 2:
		return "1,000 runs only ever offered %s shafts" % str(sizes.keys())
	if seen_kinds.size() != shafts.kinds.size():
		return "1,000 runs only ever offered %s" % str(seen_kinds.keys())
	return ""


## Worked out independently in Python with the same mix, so a change that would
## give another device or an older save other offers is caught (GEN-2).
func test_offers_and_seeds_are_pinned() -> String:
	var plan: RunPlan = RunPlan.build(12345, FileAccess.get_file_as_string(RUN))
	var shafts: ShaftOffer = _shipped()
	var expected: Array = [["deep", "hot", "steady"], ["hot", "deep", "steady"], ["deep", "hot"],
		["steady", "deep", "hot"]]
	for index: int in expected.size():
		var want: Array[String] = []
		want.assign(expected[index])
		if plan.offer_after(index, shafts) != want:
			return "level %d offers %s, expected %s" % [index, plan.offer_after(index, shafts), want]
	var seeds: Dictionary = {"steady": 3669958481, "deep": 320157332, "hot": 3500968792}
	for kind: String in seeds:
		if plan.level_seed_through(1, shafts, kind) != seeds[kind]:
			return "level 1 through %s has seed %d, expected %d" % [kind,
				plan.level_seed_through(1, shafts, kind), seeds[kind]]
	return ""


func test_different_shafts_give_different_seeds() -> String:
	var plan_text: String = FileAccess.get_file_as_string(RUN)
	var shafts: ShaftOffer = _shipped()
	for run_seed: int in 200:
		var plan: RunPlan = RunPlan.build(run_seed, plan_text)
		for index: int in range(1, plan.level_count()):
			var seen: Dictionary = {}
			for kind: String in shafts.kinds:
				var level_seed: int = plan.level_seed_through(index, shafts, kind)
				if seen.has(level_seed):
					return "run seed %d level %d: two shafts give seed %d" % [run_seed, index, level_seed]
				seen[level_seed] = true
	var any: RunPlan = RunPlan.build(1, plan_text)
	if any.level_seed_through(0, shafts, "steady") != -1 or any.level_seed_through(1, shafts, "nope") != -1:
		return "first level or unknown kind gave a seed"
	return ""


func test_bad_files_are_rejected_naming_the_key() -> String:
	var cases: Dictionary = {"[]": "top level must be a JSON object", "{": "invalid JSON"}
	var edits: Array = [
		["erase", "seed_salt", null, "missing key \"seed_salt\""],
		["set", "levels", 2, "unknown key \"levels\""],
		["set", "offer_min", 1, "key \"offer_min\" is 1"],
		["set", "offer_max", 4, "key \"offer_max\" is 4"],
		["set", "offer_min", 2.5, "key \"offer_min\" must be a whole number"],
		["set", "seed_salt", 8, "key \"seed_salt\" is 8"],
		["set", "shafts", {}, "key \"shafts\" must be an array"],
		["shaft", "kind", "Deep!", "key \"shafts[1].kind\" is \"Deep!\""],
		["shaft", "kind", "steady", "key \"shafts[1].kind\" repeats \"steady\""],
		["shaft", "label", "", "key \"shafts[1].label\" must be text"],
		["shaft", "colour", "red", "unknown key \"shafts[1].colour\""],
		["shaft_erase", "reward", null, "missing key \"shafts[1].reward\""],
		["shaft", "risk", {"robot_count": 1.0}, "missing key \"shafts[1].risk.alarm\""],
		["shaft", "risk", {"robot_count": 0, "alarm": 1}, "key \"shafts[1].risk.robot_count\" must be"],
		["shaft", "risk", {"robot_count": 1, "alarm": true}, "key \"shafts[1].risk.alarm\" must be"],
		["shaft", "reward", {"tier_weights": [1, 2]}, "key \"shafts[1].reward.tier_weights\" must be"],
		["shaft", "reward", {"tier_weights": [0, 0, 0]}, "key \"shafts[1].reward.tier_weights\" must be"],
		["shaft", "reward", {"weights": [1, 1, 1]}, "unknown key \"shafts[1].reward.weights\""],
	]
	for edit: Array in edits:
		var data: Dictionary = _valid()
		match edit[0]:
			"erase":
				data.erase(edit[1])
			"set":
				data[edit[1]] = edit[2]
			"shaft":
				data["shafts"][1][edit[1]] = edit[2]
			"shaft_erase":
				data["shafts"][1].erase(edit[1])
		cases[JSON.stringify(data)] = edit[3]
	var two: Dictionary = _valid()
	two["shafts"].pop_back()
	cases[JSON.stringify(two)] = "key \"shafts\" has 2 kinds, offer_max needs 3"
	for text: String in cases:
		var shafts: ShaftOffer = ShaftOffer.build(text)
		if not shafts.error.begins_with(cases[text]):
			return "%s gave error \"%s\", expected \"%s\"" % [text, shafts.error, cases[text]]
		if not shafts.kinds.is_empty() or not shafts.draw(1).is_empty():
			return "%s was rejected but still offers shafts" % text
	return ""
