extends RefCounted

## A run as a chain of 3 to 5 levels from one run seed (#926, RUN-1, GEN-2, ARC-2).

const SHIPPED: String = "res://data/run/run.json"


func _shipped() -> String:
	return FileAccess.get_file_as_string(SHIPPED)


func _valid() -> Dictionary:
	return {"min_levels": 3, "max_levels": 5, "seed_salt": 2654435769}


func test_shipped_file_gives_three_to_five_levels() -> String:
	var plan: RunPlan = RunPlan.build(0, _shipped())
	if plan.error != "":
		return plan.error
	if plan.min_levels != 3 or plan.max_levels != 5:
		return "shipped file says %d to %d levels" % [plan.min_levels, plan.max_levels]
	return ""


func test_thousand_seeds_have_three_to_five_distinct_levels() -> String:
	var text: String = _shipped()
	var counts: Dictionary = {}
	for run_seed: int in 1000:
		var plan: RunPlan = RunPlan.build(run_seed, text)
		if plan.error != "":
			return plan.error
		var count: int = plan.level_count()
		if count < 3 or count > 5:
			return "run seed %d has %d levels" % [run_seed, count]
		counts[count] = true
		var seen: Dictionary = {}
		for index: int in count:
			var level_seed: int = plan.level_seed(index)
			if seen.has(level_seed):
				return "run seed %d repeats level seed %d" % [run_seed, level_seed]
			seen[level_seed] = true
			if plan.depth(index) != index + 1:
				return "level %d has depth %d" % [index, plan.depth(index)]
	if counts.size() != 3:
		return "1,000 run seeds only ever gave %s levels" % str(counts.keys())
	return ""


func test_same_seed_gives_same_plan() -> String:
	var text: String = _shipped()
	for run_seed: int in [0, 7, -1, 123456789012]:
		var first: RunPlan = RunPlan.build(run_seed, text)
		var second: RunPlan = RunPlan.build(run_seed, text)
		if first.level_seeds != second.level_seeds or first.plan_hash() != second.plan_hash():
			return "run seed %d gave %s then %s" % [run_seed, first.level_seeds, second.level_seeds]
	if RunPlan.build(1, text).plan_hash() == RunPlan.build(2, text).plan_hash():
		return "run seeds 1 and 2 share a plan"
	return ""


## Pinned values, worked out independently, so a change to the mix that would
## give other devices or older saves different levels is caught (GEN-2).
func test_plans_are_pinned() -> String:
	var text: String = _shipped()
	var expected: Dictionary = {
		0: [2462723854, 1020716019, 454327756],
		1: [2527132011, 314344336, 2535364964, 2041432039],
		12345: [1200724404, 818072533, 996137225, 2397394836, 4079075752],
		-1: [1447812726, 167562728, 3596535537],
	}
	for run_seed: int in expected:
		var plan: RunPlan = RunPlan.build(run_seed, text)
		var want: Array[int] = []
		want.assign(expected[run_seed])
		if plan.level_seeds != want:
			return "run seed %d gave %s, expected %s" % [run_seed, plan.level_seeds, want]
	return ""


func test_fmix32_matches_reference() -> String:
	# MurmurHash3 fmix32 reference values.
	var cases: Dictionary = {0: 0, 1: 1364076727, 0xFFFFFFFF: 2180083513}
	for value: int in cases:
		if RunPlan.fmix32(value) != cases[value]:
			return "fmix32(%d) is %d, expected %d" % [value, RunPlan.fmix32(value), cases[value]]
	return ""


func test_bad_files_are_rejected_naming_the_key() -> String:
	var cases: Dictionary = {
		"[]": "top level must be a JSON object",
		"{": "invalid JSON",
	}
	var missing: Dictionary = _valid()
	missing.erase("seed_salt")
	cases[JSON.stringify(missing)] = "missing key \"seed_salt\""
	var unknown: Dictionary = _valid()
	unknown["levels"] = 4
	cases[JSON.stringify(unknown)] = "unknown key \"levels\""
	var fraction: Dictionary = _valid()
	fraction["min_levels"] = 3.5
	cases[JSON.stringify(fraction)] = "key \"min_levels\" must be a whole number"
	var flag: Dictionary = _valid()
	flag["max_levels"] = true
	cases[JSON.stringify(flag)] = "key \"max_levels\" must be a whole number"
	var reversed: Dictionary = _valid()
	reversed["min_levels"] = 6
	cases[JSON.stringify(reversed)] = "key \"min_levels\" is 6"
	var zero: Dictionary = _valid()
	zero["min_levels"] = 0
	cases[JSON.stringify(zero)] = "key \"min_levels\" is 0"
	var many: Dictionary = _valid()
	many["max_levels"] = 17
	cases[JSON.stringify(many)] = "key \"max_levels\" is 17"
	var even: Dictionary = _valid()
	even["seed_salt"] = 4
	cases[JSON.stringify(even)] = "key \"seed_salt\" is 4"
	for text: String in cases:
		var plan: RunPlan = RunPlan.build(5, text)
		if not plan.error.begins_with(cases[text]):
			return "%s gave error \"%s\", expected \"%s\"" % [text, plan.error, cases[text]]
		if plan.level_count() != 0:
			return "%s was rejected but still planned %d levels" % [text, plan.level_count()]
	return ""


func test_one_level_bounds_are_allowed() -> String:
	var plan: RunPlan = RunPlan.build(9, JSON.stringify({"min_levels": 1, "max_levels": 1,
		"seed_salt": 1}))
	if plan.error != "" or plan.level_count() != 1:
		return "1 to 1 levels gave %d levels, error \"%s\"" % [plan.level_count(), plan.error]
	return ""
