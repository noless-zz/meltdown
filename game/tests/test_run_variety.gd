extends RefCounted

## Different run seeds give different runs (#1140, RUN-1, GEN-2, ARC-2, DEV-6):
## the part of gate G4's "three runs feel different" a test can measure. It
## checks level counts, level-1 seeds, the level-1 mines and the shaft offers
## after level 1, from the shipped `data/run/` files. Generation only, no
## flight: the mine is `MineGenerator` through `SeedLevel`, the one loader the
## game flies, so a plan that always drew the same levels would fail here.

const RUN: String = "res://data/run/run.json"
const SHAFTS: String = "res://data/run/shafts.json"
## The three runs the gate compares.
const GATE_SEEDS: Array[int] = [1, 2, 3]
## Run seeds 1 to this many for the spread check.
const SPREAD_SEEDS: int = 20

## Data files read once per file, not once per test (generation dominates).
var _inputs: SeedLevel = null
var _shafts: ShaftOffer = null
var _run_text: String = ""


func _setup() -> String:
	if _inputs == null:
		_run_text = FileAccess.get_file_as_string(RUN)
		_shafts = ShaftOffer.build(FileAccess.get_file_as_string(SHAFTS))
		_inputs = SeedLevel.load_inputs()
	if _shafts.error != "":
		return "shafts.json: %s" % _shafts.error
	return _inputs.error


func _plan(run_seed: int) -> RunPlan:
	return RunPlan.build(run_seed, _run_text)


## The first level of a run is flown from `level_seed(0)` (no shaft into it).
func _first_mine(plan: RunPlan) -> MineGenerator:
	return _inputs.generate(plan.level_seed(0))


## The sorted, unique module ids the level-1 mine was built from.
static func _module_set(generator: MineGenerator) -> Array[String]:
	var ids: Array[String] = []
	for placement: ModulePlacement in generator.placements:
		if not ids.has(placement.module_id):
			ids.append(placement.module_id)
	ids.sort()
	return ids


func test_three_gate_seeds_give_three_runs() -> String:
	var problem: String = _setup()
	if problem != "":
		return problem
	var first_seeds: Dictionary = {}
	var mine_hashes: Dictionary = {}
	var offers: Dictionary = {}
	for run_seed: int in GATE_SEEDS:
		var plan: RunPlan = _plan(run_seed)
		if plan.error != "":
			return "run seed %d: %s" % [run_seed, plan.error]
		var count: int = plan.level_count()
		if count < 3 or count > 5:
			return "run seed %d has %d levels, RUN-1 wants 3 to 5" % [run_seed, count]
		first_seeds[plan.level_seed(0)] = run_seed
		var mine: MineGenerator = _first_mine(plan)
		if mine.placements.is_empty():
			return "run seed %d: level 1 generated no modules (%s)" % [run_seed, mine.note]
		mine_hashes[mine.output_hash()] = run_seed
		var offer: Array[String] = plan.offer_after(0, _shafts)
		if offer.is_empty():
			return "run seed %d offers no shaft after level 1" % run_seed
		offers[str(offer)] = run_seed
		print("  run seed %d: %d levels, level-1 seed %d, level-1 mine %d modules %s, offer %s" % [
				run_seed, count, plan.level_seed(0), mine.placements.size(),
				str(_module_set(mine)), str(offer)])
	if first_seeds.size() != GATE_SEEDS.size():
		return "run seeds %s share a level-1 seed" % str(GATE_SEEDS)
	if mine_hashes.size() != GATE_SEEDS.size():
		return "run seeds %s share a level-1 mine" % str(GATE_SEEDS)
	if offers.size() < 2:
		return "run seeds %s all offer the same shafts after level 1: %s" % [
				str(GATE_SEEDS), str(offers.keys())]
	return ""


func test_same_seed_gives_same_run_and_mine() -> String:
	var problem: String = _setup()
	if problem != "":
		return problem
	for run_seed: int in GATE_SEEDS:
		var first: RunPlan = _plan(run_seed)
		var second: RunPlan = _plan(run_seed)
		if first.plan_hash() != second.plan_hash():
			return "run seed %d gave plan hashes %d then %d" % [
					run_seed, first.plan_hash(), second.plan_hash()]
		var mine_a: int = _first_mine(first).output_hash()
		var mine_b: int = _first_mine(second).output_hash()
		if mine_a != mine_b:
			return "run seed %d gave level-1 mines %d then %d" % [run_seed, mine_a, mine_b]
	return ""


func test_twenty_seeds_spread_counts_and_modules() -> String:
	var problem: String = _setup()
	if problem != "":
		return problem
	var level_counts: Dictionary = {}
	var module_sets: Dictionary = {}
	# Informational: kinds offered regardless of order, for the gate to quote.
	var offer_sets: Dictionary = {}
	for run_seed: int in range(1, SPREAD_SEEDS + 1):
		var plan: RunPlan = _plan(run_seed)
		if plan.error != "":
			return "run seed %d: %s" % [run_seed, plan.error]
		var count: int = plan.level_count()
		level_counts[count] = int(level_counts.get(count, 0)) + 1
		var key: String = str(_module_set(_first_mine(plan)))
		module_sets[key] = int(module_sets.get(key, 0)) + 1
		var kinds: Array[String] = plan.offer_after(0, _shafts)
		kinds.sort()
		offer_sets[str(kinds)] = int(offer_sets.get(str(kinds), 0)) + 1
	var counts: Array = level_counts.keys()
	counts.sort()
	var lines: Array[String] = []
	for count: Variant in counts:
		lines.append("%d levels: %d runs" % [count, level_counts[count]])
	print("  run seeds 1-%d: %s; %d distinct level-1 module sets; shafts after level 1: %s" % [
			SPREAD_SEEDS, ", ".join(lines), module_sets.size(), str(offer_sets)])
	if level_counts.size() < 2:
		return "run seeds 1-%d all have %s levels" % [SPREAD_SEEDS, str(counts)]
	if module_sets.size() < 2:
		return "run seeds 1-%d all build level 1 from %s" % [SPREAD_SEEDS, str(module_sets.keys())]
	return ""
