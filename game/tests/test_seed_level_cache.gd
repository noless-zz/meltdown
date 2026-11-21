extends RefCounted

## The seed sweeps share built levels through `SeedLevelCache` (#956, GEN-2,
## ARC-2): a shared level is the one building the seed afresh gives, the same
## object is handed to every sweep that asks, `SeedSweep.run` gives the same
## verdicts with shared levels as without, and no sweep that ran before this
## file changed a level it was handed. The file name sorts after every sweep
## that shares levels except `test_sweep_reactor_distance.gd`, which only reads them.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const FIRST: int = 990
const COUNT: int = 10


func test_no_sweep_changed_a_shared_level() -> String:
	var changed: Array[String] = SeedLevelCache.changed_levels()
	if not changed.is_empty():
		return "%d shared levels changed after they were built, first %s" % [changed.size(), changed[0]]
	print("  shared levels checked unchanged: %d shipped, %d without fires" % [
			SeedLevelCache.level_count(SeedLevelCache.SHIPPED),
			SeedLevelCache.level_count(SeedLevelCache.WITHOUT_FIRES)])
	return ""


func test_a_shared_level_is_the_seed_built_afresh() -> String:
	var inputs: SeedLevel = SeedLevel.load_inputs()
	for level_seed: int in range(FIRST, FIRST + COUNT):
		var fresh: LevelDef = inputs.level_of(inputs.generate(level_seed))
		var shared: LevelDef = SeedLevelCache.level(level_seed)
		if SeedLevelCache.fingerprint(shared) != SeedLevelCache.fingerprint(fresh):
			return "seed %d: the shared level differs from one built afresh" % level_seed
		if SeedLevelCache.level(level_seed) != shared:
			return "seed %d was built again" % level_seed
	return ""


## The level without fires is what the doors sweep built before #956: the
## shipped file with its `fires` section left out, read afresh.
func test_a_shared_level_without_fires_is_the_seed_built_afresh() -> String:
	var data: Dictionary = JSON.parse_string(SeedLevel.read_text(SeedLevel.DEBRIS_FILE))
	data.erase(DebrisPlan.FIRES_KEY)
	var plan: DebrisPlan = DebrisPlan.parse_json(JSON.stringify(data))
	var inputs: SeedLevel = SeedLevel.load_inputs()
	var fires: int = 0
	for level_seed: int in range(FIRST, FIRST + COUNT):
		var fresh: LevelDef = inputs.generate(level_seed).to_level_def(inputs.reactor_plan,
				inputs.tuning.radius, inputs.robot_plan, plan)
		var shared: LevelDef = SeedLevelCache.level(level_seed, SeedLevelCache.WITHOUT_FIRES)
		if SeedLevelCache.fingerprint(shared) != SeedLevelCache.fingerprint(fresh):
			return "seed %d: the shared level without fires differs from one built afresh" % level_seed
		var debris: MeltdownDebris = shared.debris
		for index: int in 0 if debris == null else debris.size():
			if debris.is_fire(index):
				fires += 1
	return "" if fires == 0 else "%d fires in levels without fires" % fires


func test_building_leaves_the_shared_generator_as_generated() -> String:
	for level_seed: int in range(FIRST, FIRST + COUNT):
		SeedLevelCache.level(level_seed)
		SeedLevelCache.level(level_seed, SeedLevelCache.WITHOUT_FIRES)
		if SeedLevelCache.generator(level_seed).output_hash() != SeedLevelCache.generated_hash(level_seed):
			return "seed %d: building changed output_hash" % level_seed
	return ""


func test_the_sweep_gives_the_same_result_with_shared_levels() -> String:
	for level_seed: int in range(FIRST, FIRST + COUNT):
		SeedLevelCache.level(level_seed)
	var shared: Dictionary = SeedSweep.run(FIRST, COUNT)
	# Any override turns the sharing off; this one is the shipped text itself.
	var own: Dictionary = {SeedLevel.SHIP_FILE: SeedLevel.read_text(SeedLevel.SHIP_FILE)}
	var fresh: Dictionary = SeedSweep.run(FIRST, COUNT, SeedSweep.MODULE_COUNT,
			SeedSweep.KEPT_FAILURES, own)
	for key: String in ["passed", "failed", "short", "looped", "robots", "debris", "debris_held"]:
		if shared[key] != fresh[key]:
			return "%s: %s shared, %s fresh" % [key, shared[key], fresh[key]]
	if str(shared["by_check"]) != str(fresh["by_check"]) \
			or str(shared["debris_by_kind"]) != str(fresh["debris_by_kind"]) \
			or str(shared["reactor_distance"]) != str(fresh["reactor_distance"]):
		return "by check, kind or distance differ: %s / %s" % [shared["by_check"], fresh["by_check"]]
	return ""
