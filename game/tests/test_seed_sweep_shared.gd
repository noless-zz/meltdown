extends RefCounted

## The seed sweeps share generators through `SeedSweep.shared_generators`
## (#903, GEN-2, ARC-2): a shared generator is the one generating the seed
## afresh gives, the same object is handed to every sweep that asks, and
## `SeedSweep.run` reads the same levels and verdicts from it as without it.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const FIRST: int = 990
const COUNT: int = 10


func test_a_shared_generator_is_the_seed_generated_afresh() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var shared: Array[MineGenerator] = SeedSweep.shared_generators(FIRST, COUNT)
	if shared.size() != COUNT:
		return "%d generators for %d seeds" % [shared.size(), COUNT]
	for index: int in COUNT:
		var fresh: MineGenerator = MineGenerator.generate(FIRST + index, modules,
				SeedSweep.MODULE_COUNT, bridges)
		if shared[index].output_hash() != fresh.output_hash() or shared[index].note != fresh.note:
			return "seed %d: the shared generator differs from a fresh one" % (FIRST + index)
	var again: Array[MineGenerator] = SeedSweep.shared_generators(FIRST, COUNT)
	for index: int in COUNT:
		if again[index] != shared[index]:
			return "seed %d was generated again" % (FIRST + index)
	return ""


func test_building_a_level_leaves_a_shared_generator_as_it_was() -> String:
	var generator: MineGenerator = SeedSweep.shared_generators(FIRST, 1)[0]
	var before: int = generator.output_hash()
	var inputs: SeedLevel = SeedLevel.load_inputs()
	var first: String = _describe(inputs.level_of(generator))
	var second: String = _describe(inputs.level_of(generator))
	if generator.output_hash() != before:
		return "building a level changed output_hash"
	return "" if first == second else "the same shared generator built two different levels"


func test_the_sweep_gives_the_same_result_with_shared_generators() -> String:
	SeedSweep.shared_generators(FIRST, COUNT)
	var shared: Dictionary = SeedSweep.run(FIRST, COUNT)
	# Any override turns the sharing off; this one is the shipped text itself.
	var own: Dictionary = {SeedLevel.SHIP_FILE: SeedLevel.read_text(SeedLevel.SHIP_FILE)}
	var fresh: Dictionary = SeedSweep.run(FIRST, COUNT, SeedSweep.MODULE_COUNT,
			SeedSweep.KEPT_FAILURES, own)
	for key: String in ["passed", "failed", "short", "looped", "robots", "debris", "debris_held"]:
		if shared[key] != fresh[key]:
			return "%s: %s shared, %s fresh" % [key, shared[key], fresh[key]]
	if str(shared["by_check"]) != str(fresh["by_check"]) \
			or str(shared["debris_by_kind"]) != str(fresh["debris_by_kind"]):
		return "by check or kind differ: %s / %s" % [shared["by_check"], fresh["by_check"]]
	return ""


func _describe(level: LevelDef) -> String:
	var parts: Array[String] = [str(level.start_position_mm), str(level.union.boxes.size())]
	parts.append("" if level.reactor == null else level.reactor.to_json())
	for spawn: RobotSpawn in level.robots.spawns:
		parts.append(str(spawn.position_mm))
	parts.append("" if level.debris == null else level.debris.to_json())
	return "|".join(parts)
