extends RefCounted

## The seed card (#532, DEV-6, GEN-2, GEN-5, RUN-4, RUN-5): a card says what
## `MineGenerator` and the debris plan give for its seed, its line has the
## agreed shape, and `--pick` covers a loop, a door, a fire and the longest
## escape on seeds 1..200 while skipping the m3 suite's seeds, the same way
## every time. With `--fair` (#547) a seed the bot loses is never picked.

const SeedCard := preload("res://tests/seed_card.gd")
const SeedSweepRef := preload("res://tests/seed_sweep.gd")
const PICK_FIRST: int = 1
const PICK_SEEDS: int = 200
## Seeds whose cards are checked against a level built without the card.
const CHECKED_SEEDS: Array[int] = [1, 3, 5, 26, 40]


static func _card(level_seed: int, loops: int, doors: int, fires: int, escape_mm: int,
		valid: bool = true) -> Dictionary:
	return {"seed": level_seed, "modules": 10, "loops": loops, "robots": 0, "spheres": 0,
			"doors": doors, "fires": fires, "escape_mm": escape_mm, "countdown_ticks": 0,
			"valid": valid}


func test_card_matches_the_generator_and_the_debris_plan() -> String:
	var inputs: SeedLevel = SeedLevel.load_inputs()
	if inputs.error != "":
		return inputs.error
	var modules: Array[ModuleDef] = SeedSweepRef.load_modules()
	var bridges: LoopBridges = SeedSweepRef.load_loop_bridges()
	var radius: float = SeedSweepRef.ship_radius()
	for level_seed: int in CHECKED_SEEDS:
		var seed_card: Dictionary = SeedCard.card(inputs, level_seed)
		# Built here from the loaders, not through `SeedLevel.generate`.
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules,
				SeedSweepRef.MODULE_COUNT, bridges)
		var level: LevelDef = generator.to_level_def(SeedSweepRef.load_reactor_plan(), radius,
				SeedSweepRef.load_robot_plan(), SeedSweepRef.load_debris_plan())
		var spheres: int = 0
		var doors: int = 0
		var fires: int = 0
		for index: int in level.debris.size():
			if level.debris.is_fire(index):
				fires += 1
			elif index < level.debris.sizes_mm.size() and level.debris.sizes_mm[index] != Vector3i.ZERO:
				doors += 1
			else:
				spheres += 1
		var path_mm: int = EscapePath.length_mm(level.union, level.reactor.position(),
				level.start_position())
		var expected: Dictionary = {"seed": level_seed, "modules": generator.placements.size(),
				"loops": generator.loops, "robots": level.robots.spawns.size(), "spheres": spheres,
				"doors": doors, "fires": fires, "escape_mm": path_mm,
				"countdown_ticks": level.reactor.meltdown_ticks_for_path(path_mm), "valid": true}
		for key: String in expected:
			if seed_card.get(key) != expected[key]:
				return "seed %d: %s is %s, expected %s" % [level_seed, key, seed_card.get(key),
						expected[key]]
		if spheres + doors + fires == 0:
			return "seed %d placed no debris, so the counts check nothing" % level_seed
	return ""


func test_line_has_the_agreed_shape() -> String:
	var seed_card: Dictionary = _card(7, 1, 2, 1, 127_449)
	seed_card["robots"] = 4
	seed_card["spheres"] = 5
	seed_card["countdown_ticks"] = 3330
	var expected: String = 'MELTDOWN_SEED_CARD {"seed":7,"modules":10,"loops":1,"robots":4,"spheres":5,"doors":2,"fires":1,"escape_m":127.4,"countdown_s":55.5,"valid":true}'
	var got: String = SeedCard.line(seed_card)
	if got != expected:
		return "line is %s" % got
	var data: Variant = JSON.parse_string(got.trim_prefix(SeedCard.CARD_TAG + " "))
	if not data is Dictionary or (data as Dictionary).keys() != ["seed", "modules", "loops",
			"robots", "spheres", "doors", "fires", "escape_m", "countdown_s", "valid"]:
		return "line does not read back as the agreed keys: %s" % got
	return ""


func test_pick_covers_the_four_kinds_and_prefers_unseen_seeds() -> String:
	# Seed 2 has everything but is the suite's; 3, 4 and 5 cover it between them.
	var cards: Array[Dictionary] = [_card(1, 0, 0, 0, 50_000), _card(2, 1, 1, 1, 90_000),
			_card(3, 1, 1, 0, 60_000), _card(4, 0, 0, 1, 70_000), _card(5, 0, 0, 0, 90_000),
			_card(6, 1, 1, 1, 200_000, false)]
	var picked: Dictionary = SeedCard.pick(cards, [2] as Array[int], 3)
	if picked["seeds"] != [3, 4, 5] or not (picked["missing"] as Array).is_empty():
		return "picked %s" % SeedCard.pick_line(picked)
	# Without the suite seed's being avoided, it covers three kinds at once.
	picked = SeedCard.pick(cards, [] as Array[int], 3)
	if (picked["seeds"] as Array)[0] != 2:
		return "without avoiding seed 2 picked %s" % SeedCard.pick_line(picked)
	if SeedCard.pick_line(picked) != SeedCard.pick_line(SeedCard.pick(cards, [] as Array[int], 3)):
		return "the same cards gave different picks"
	# No valid seed with a door: the pick says so.
	picked = SeedCard.pick([_card(1, 1, 0, 1, 10_000)] as Array[Dictionary], [] as Array[int], 3)
	if picked["seeds"] != [1] or picked["missing"] != ["door"]:
		return "a range without doors picked %s" % SeedCard.pick_line(picked)
	return ""


## A flyer that loses `lost` and escapes the rest at tick 1000 + seed,
## counting its calls in `calls`.
static func _flyer(lost: Array[int], calls: Array[int]) -> Callable:
	return func(level_seed: int) -> Dictionary:
		calls.append(level_seed)
		return {"escaped": not lost.has(level_seed), "tick": 1000 + level_seed}


func test_fair_pick_skips_seeds_the_bot_loses() -> String:
	# Seeds 3, 4 and 5 cover everything; with 3 lost, 7 is the next best for loop and door.
	var cards: Array[Dictionary] = [_card(1, 0, 0, 0, 50_000), _card(2, 1, 1, 1, 90_000),
			_card(3, 1, 1, 0, 60_000), _card(4, 0, 0, 1, 70_000), _card(5, 0, 0, 0, 90_000),
			_card(6, 1, 1, 1, 200_000, false), _card(7, 1, 1, 0, 40_000)]
	var calls: Array[int] = []
	var picked: Dictionary = SeedCard.pick(cards, [2] as Array[int], 3, true,
			_flyer([3] as Array[int], calls))
	if picked["seeds"] != [7, 4, 5] or not (picked["missing"] as Array).is_empty():
		return "fair pick with seed 3 lost picked %s" % SeedCard.pick_line(picked)
	if not picked.get("fair", false) or picked["escape_ticks"] != {7: 1007, 4: 1004, 5: 1005}:
		return "fair pick reports %s and ticks %s" % [picked.get("fair"), picked.get("escape_ticks")]
	if SeedCard.pick_line(picked) != 'MELTDOWN_SEED_PICK {"seeds":[7,4,5],"missing":[],"fair":true}':
		return "fair pick line is %s" % SeedCard.pick_line(picked)
	if calls.has(1) or calls.has(6):
		return "flew seeds the pick was not about to take: %s" % [calls]
	for level_seed: int in calls:
		if calls.count(level_seed) > 1:
			return "flew seed %d twice: %s" % [level_seed, calls]
	# Both 90 m escapes lost: the longest the bot gets out of (seed 4's) counts.
	picked = SeedCard.pick(cards, [2] as Array[int], 3, true, _flyer([2, 5] as Array[int], calls))
	if picked["seeds"] != [3, 4, 1] or not (picked["missing"] as Array).is_empty():
		return "fair pick with 2 and 5 lost picked %s" % SeedCard.pick_line(picked)
	# Every door seed lost: the pick names the door as missing.
	picked = SeedCard.pick(cards, [] as Array[int], 3, true, _flyer([2, 3, 7] as Array[int], calls))
	if not (picked["missing"] as Array).has("door") or (picked["seeds"] as Array).has(2):
		return "fair pick without a fair door picked %s" % SeedCard.pick_line(picked)
	return ""


func test_without_fair_the_flyer_is_never_called_and_lines_are_unchanged() -> String:
	var cards: Array[Dictionary] = [_card(3, 1, 1, 0, 60_000), _card(4, 0, 0, 1, 70_000),
			_card(5, 0, 0, 0, 90_000)]
	var calls: Array[int] = []
	var picked: Dictionary = SeedCard.pick(cards, [] as Array[int], 3, false,
			_flyer([3] as Array[int], calls))
	if not calls.is_empty():
		return "the flyer was called without --fair: %s" % [calls]
	if SeedCard.pick_line(picked) != 'MELTDOWN_SEED_PICK {"seeds":[3,4,5],"missing":[]}':
		return "pick line without --fair is %s" % SeedCard.pick_line(picked)
	if picked.has("fair") or picked.has("escape_ticks"):
		return "a pick without --fair has fair fields: %s" % picked
	var seed_card: Dictionary = _card(7, 1, 2, 1, 127_449)
	var plain: String = SeedCard.line(seed_card)
	seed_card["escape_tick"] = 4321
	var expected: String = plain.trim_suffix("}") + ',"bot":"escaped","escape_tick":4321}'
	if SeedCard.line(seed_card) != expected:
		return "fair card line is %s" % SeedCard.line(seed_card)
	return ""


func test_pick_on_seeds_1_to_200_covers_all_and_skips_the_m3_seeds() -> String:
	var suite: Array[int] = SeedCard.suite_seeds()
	if suite.is_empty():
		return "no seeds read from the m3 suite"
	var cards: Array[Dictionary] = SeedCard.cards(PICK_FIRST, PICK_SEEDS)
	if cards.size() != PICK_SEEDS:
		return "%d cards for %d seeds: %s" % [cards.size(), PICK_SEEDS, cards[0]]
	var picked: Dictionary = SeedCard.pick(cards, suite, 3)
	print("  %s" % SeedCard.pick_line(picked))
	var seeds: Array = picked["seeds"]
	if seeds.size() != 3 or not (picked["missing"] as Array).is_empty():
		return "picked %s" % SeedCard.pick_line(picked)
	var longest_mm: int = 0
	for seed_card: Dictionary in cards:
		if seed_card["valid"]:
			longest_mm = maxi(longest_mm, seed_card["escape_mm"])
	var covered: Array[String] = []
	for level_seed: int in seeds:
		if suite.has(level_seed):
			return "picked the m3 suite's seed %d" % level_seed
		var seed_card: Dictionary = cards[level_seed - PICK_FIRST]
		if not seed_card["valid"]:
			return "picked invalid seed %d" % level_seed
		for kind: String in SeedCard.kinds_of(seed_card, longest_mm):
			if not covered.has(kind):
				covered.append(kind)
	for kind: String in SeedCard.KINDS:
		if not covered.has(kind):
			return "%s not covered by %s" % [kind, SeedCard.pick_line(picked)]
	var again: Dictionary = SeedCard.pick(SeedCard.cards(PICK_FIRST, PICK_SEEDS), suite, 3)
	if SeedCard.pick_line(again) != SeedCard.pick_line(picked):
		return "the same range picked %s, then %s" % [SeedCard.pick_line(picked),
				SeedCard.pick_line(again)]
	return ""
