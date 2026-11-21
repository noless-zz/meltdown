extends RefCounted

## A chosen shaft's tier weights shape the component drop roll (#1000, CRF-7,
## RUN-1, ARC-2): each line's chance is scaled by its kind's tier weight over
## the mean weight, `[1, 1, 1]` rolls as no weights, the weights join the hash
## only when set, a weighted run level replays to the same hash, and the run
## hands the chosen shaft's weights to its level.

const PickupTests := preload("res://tests/test_component_pickup.gd")

const RUN_SEED: int = 12345
const DEATHS: int = 500
## One line per tier, all at the same chance, so only the weights tell them apart.
const TABLE: String = "[{\"id\": \"scrap_alloy\", \"chance\": 0.3, \"count\": [1, 1]}, {\"id\": \"circuit_shards\", \"chance\": 0.3, \"count\": [1, 1]}, {\"id\": \"core_glass\", \"chance\": 0.3, \"count\": [1, 1]}]"
const TIERS: Dictionary = {"scrap_alloy": 1, "cell_salts": 1, "circuit_shards": 2, "core_glass": 3}


static func weighted(weights: Array) -> ComponentPickup:
	var rules: ComponentPickup = PickupTests.rules()
	var problem: String = rules.set_tier_weights(weights, TIERS)
	assert(problem == "", problem)
	return rules


## Items of each tier, [tier 1, tier 2, tier 3], over the same `DEATHS` robots.
static func tier_counts(rules: ComponentPickup) -> Array[int]:
	var def: RobotDef = PickupTests.robot_def(TABLE)
	var counts: Array[int] = [0, 0, 0]
	for serial: int in DEATHS:
		for item: ComponentItem in ComponentPickup.roll(def, RUN_SEED, serial, Vector3.ZERO, rules):
			counts[TIERS[item.kind_id] - 1] += item.count
	return counts


## Every robot's heaps, one line per robot, over the same `DEATHS` robots.
static func all_rolls(rules: ComponentPickup) -> Array[String]:
	var def: RobotDef = PickupTests.robot_def(TABLE)
	var rolls: Array[String] = []
	for serial: int in DEATHS:
		rolls.append(",".join(PickupTests.heaps(ComponentPickup.roll(def, RUN_SEED, serial, Vector3.ZERO, rules))))
	return rolls


func test_lean_and_rich_weights_shift_the_tiers() -> String:
	var lean: Array[int] = tier_counts(weighted([6, 3, 1]))
	var rich: Array[int] = tier_counts(weighted([2, 3, 5]))
	var plain: Array[int] = tier_counts(null)
	print("Meltdown: %d deaths, tier 1/2/3 items: none %s, [6, 3, 1] %s, [2, 3, 5] %s" % [
		DEATHS, plain, lean, rich])
	if lean[0] <= rich[0]:
		return "[6, 3, 1] dropped %d tier-1 items, [2, 3, 5] %d" % [lean[0], rich[0]]
	if rich[2] <= lean[2]:
		return "[2, 3, 5] dropped %d tier-3 items, [6, 3, 1] %d" % [rich[2], lean[2]]
	return ""


func test_the_chance_is_scaled_by_weight_over_mean_and_capped() -> String:
	var drop: ComponentDrop = PickupTests.robot_def(TABLE).components[2]
	var rules: ComponentPickup = weighted([2, 3, 5])
	# Tier 3, weight 5, mean 10 / 3: 0.3 * 1.5.
	if not is_equal_approx(rules.chance_of(drop), 0.45):
		return "core_glass rolls %f under [2, 3, 5], expected 0.45" % rules.chance_of(drop)
	if weighted([0, 0, 1]).chance_of(drop) != 0.9:
		return "[0, 0, 1] gives tier 3 %f, expected 0.9" % weighted([0, 0, 1]).chance_of(drop)
	var certain: ComponentDrop = PickupTests.robot_def(PickupTests.CERTAIN).components[0]
	if weighted([6, 3, 1]).chance_of(certain) != 1.0:
		return "a certain tier-1 line went above 1.0"
	if weighted([0, 3, 1]).chance_of(certain) != 0.0:
		return "a tier weighted 0 still drops"
	var unknown: ComponentPickup = PickupTests.rules()
	unknown.set_tier_weights([6, 3, 1], {})
	if unknown.chance_of(drop) != drop.chance:
		return "a kind with no known tier changed its chance"
	return ""


func test_even_weights_roll_as_no_weights() -> String:
	var plain: Array[String] = all_rolls(null)
	if all_rolls(weighted([1, 1, 1])) != plain or all_rolls(weighted([4, 4, 4])) != plain:
		return "even weights changed a roll"
	if all_rolls(PickupTests.rules()) != plain:
		return "unweighted rules changed a roll"
	return ""


func test_a_weighted_roll_is_seeded_per_robot() -> String:
	var rules: ComponentPickup = weighted([2, 3, 5])
	var def: RobotDef = PickupTests.robot_def(TABLE)
	var forward: Array[String] = []
	for serial: int in 50:
		forward.append(",".join(PickupTests.heaps(ComponentPickup.roll(def, RUN_SEED, serial, Vector3.ZERO, rules))))
	for serial: int in range(49, -1, -1):
		var again: String = ",".join(PickupTests.heaps(ComponentPickup.roll(def, RUN_SEED, serial, Vector3.ZERO, rules)))
		if again != forward[serial]:
			return "robot %d rolled %s, then %s" % [serial, forward[serial], again]
	return ""


func test_invalid_weights_are_errors_naming_the_value() -> String:
	for bad: Array in [[], [1, 2], [1, 2, 3, 4], [0, 0, 0], [-1, 2, 3], [1.5, 1, 1], [true, 1, 1], ["1", 1, 1]]:
		var rules: ComponentPickup = PickupTests.rules()
		var problem: String = rules.set_tier_weights(bad, TIERS)
		if problem == "" or not problem.contains(JSON.stringify(bad)):
			return "weights %s gave \"%s\"" % [bad, problem]
		if not rules.tier_weights.is_empty():
			return "weights %s were kept" % [bad]
	var tiers: ComponentPickup = PickupTests.rules()
	var problem: String = tiers.set_tier_weights([1, 2, 3], {"core_glass": 4})
	if not problem.contains("core_glass") or not tiers.tier_weights.is_empty():
		return "tier 4 gave \"%s\"" % problem
	if PickupTests.rules().set_tier_weights([6.0, 3.0, 1.0], TIERS) != "":
		return "whole floats, as JSON reads them, were refused"
	return ""


func test_weights_join_the_hash_only_when_set() -> String:
	if PickupTests.rules().values_hash() != hash(["pickup_reach", 2.5]):
		return "unweighted rules changed their hash, so pinned replays would break"
	if weighted([6, 3, 1]).values_hash() == PickupTests.rules().values_hash():
		return "weights do not join the hash"
	if weighted([6, 3, 1]).values_hash() != weighted([6, 3, 1]).values_hash():
		return "the same weights hash differently"
	if weighted([6, 3, 1]).values_hash() == weighted([2, 3, 5]).values_hash():
		return "different weights hash the same"
	return ""


func test_same_seed_weights_and_inputs_give_the_same_hash() -> String:
	var hashes: Array[int] = []
	for weights: Array in [[2, 3, 5], [2, 3, 5], [6, 3, 1]]:
		var sim: Sim = Sim.new(RUN_SEED, 1)
		sim.set_component_rules(weighted(weights))
		for i: int in 8:
			sim.spawn_robot(PickupTests.robot_def(TABLE), Vector3(i * 3.0, 0, -30), Basis.IDENTITY)
		for i: int in 8:
			PickupTests.kill(sim, 0)
			PickupTests.idle(sim)
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "the same seed, weights and inputs gave %d and %d" % [hashes[0], hashes[1]]
	if hashes[0] == hashes[2]:
		return "other weights gave the same hash"
	return ""


## Level 2 of a run after a chosen shaft, as `LevelStart` builds it.
func _level_two(pick: int) -> Array:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, func() -> int: return 77)
	if not run.level_reward().is_empty():
		return [null, "level 1 has weights %s" % [run.level_reward()]]
	var offered: Array[String] = run.escape_for_choice({})
	if offered.size() <= pick or not run.choose(offered[pick]):
		return [null, "could not choose shaft %d of %s" % [pick, offered]]
	var level_start: LevelStart = LevelStart.new()
	level_start.run = run
	var world: Node3D = Node3D.new()
	var session: LocalSession = level_start.session_for(world, run.level_source(), null)
	world.free()
	return [session, run]


func test_the_run_hands_the_chosen_shaft_weights_to_its_level() -> String:
	var got: Array = _level_two(1)
	if got[0] == null:
		return str(got[1])
	var session: LocalSession = got[0]
	var run: RunWiring = got[1]
	var want: Array[float] = run.state.shafts.rewards[run.state.current_shaft()]
	var rules: ComponentPickup = session.sim.component_rules
	if rules == null or rules.tier_weights.size() != 3 or float(rules.tier_weights[0]) != want[0] \
			or float(rules.tier_weights[2]) != want[2]:
		return "level 2 rolls with %s, the shaft gives %s" % [
			"no rules" if rules == null else str(rules.tier_weights), want]
	if rules.kind_tiers.get("core_glass", 0) != 3 or rules.kind_tiers.get("scrap_alloy", 0) != 1:
		return "kind tiers %s do not match the kind files" % [rules.kind_tiers]
	var world: Node3D = Node3D.new()
	var alone: LocalSession = LevelStart.level_session(world, run.level_source(), null)
	world.free()
	if alone.sim.component_rules != null:
		return "the same level flown alone with --seed has component rules"
	return ""


func test_a_weighted_run_level_replays_to_the_same_hash() -> String:
	var got: Array = _level_two(2)
	if got[0] == null:
		return str(got[1])
	var session: LocalSession = got[0]
	for i: int in 120:
		session.advance(ShipState.TICK_DT)
	var text: String = session.replay.to_text()
	if not text.contains("\"tier_weights\":[") or not text.contains("\"kind_tiers\":{"):
		return "the replay does not carry the weights"
	var replay: Replay = Replay.from_text(text)
	if replay.error != "":
		return replay.error
	if replay.component_rules.values_hash() != session.sim.component_rules.values_hash():
		return "the replay reads back other rules"
	var sim: Sim = replay.run()
	if sim == null or sim.state_hash() != session.sim.state_hash():
		return "the replay ends on %s, the flight on %d" % [
			"nothing" if sim == null else str(sim.state_hash()), session.sim.state_hash()]
	return ""
