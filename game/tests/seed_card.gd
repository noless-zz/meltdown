extends SceneTree

## One line per generated seed, saying what its level holds (#532, DEV-6,
## GEN-2, GEN-5, RUN-4, RUN-5): gate G3's human half flies "three unseen
## seeds", and without this the owner cannot tell which seeds have a loop, a
## blast door, fire or a long escape without flying many of them.
##
##     godot --headless --path game -s res://tests/seed_card.gd -- --seeds=200 --first=1
##     godot --headless --path game -s res://tests/seed_card.gd -- --seeds=200 --first=1 --pick=3
##
## Each level is built as the validator sweep builds it: `SeedLevel`'s inputs,
## generator and level (the loader `--seed` flies), checked by the validator and
## `seed_sweep.gd`'s `debris_route`, so a card describes the level the owner
## will fly. Without `--pick` it prints a `MELTDOWN_SEED_CARD` line per seed.
## With `--pick=N` it prints the cards of N seeds chosen to cover, between
## them, a loop, a door, a fire and the range's longest escape, then a
## `MELTDOWN_SEED_PICK` line; it exits 1 when they cannot cover all four.
## The functions are static so the unit test can call them without starting a
## second SceneTree.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const M3SeedPick := preload("res://tests/m3_seed_pick.gd")
const CARD_TAG: String = "MELTDOWN_SEED_CARD"
const PICK_TAG: String = "MELTDOWN_SEED_PICK"
## What a pick must cover between its seeds, in the order the pick line lists them.
const KINDS: Array[String] = ["loop", "door", "fire", "longest"]


## The card for `level_seed`, built from `inputs` as the sweep builds it:
## "seed", "modules" (placed), "loops", "robots", "spheres", "doors" and
## "fires" (debris entries of each kind), "escape_mm" (the shortest path from
## the reactor to the exit, `EscapePath.UNREACHABLE` without one), "countdown_ticks"
## (what `ReactorState.meltdown_ticks_for_path` gives for it, 0 without a
## reactor) and "valid" (the level built and passed the sweep's checks).
static func card(inputs: SeedLevel, level_seed: int) -> Dictionary:
	var generator: MineGenerator = inputs.generate(level_seed)
	var level: LevelDef = inputs.level_of(generator)
	var result: Dictionary = {"seed": level_seed, "modules": generator.placements.size(),
			"loops": generator.loops, "robots": level.robots.spawns.size(), "spheres": 0,
			"doors": 0, "fires": 0, "escape_mm": EscapePath.UNREACHABLE, "countdown_ticks": 0,
			"valid": false}
	if level.debris != null:
		for index: int in level.debris.size():
			var kind: String = "fires" if level.debris.is_fire(index) \
					else ("doors" if level.debris.is_box(index) else "spheres")
			result[kind] += 1
	if level.error != "" or level.reactor == null:
		return result
	# Where the ship is when the reactor dies (RUN-5), as the validator measures it.
	var path_mm: int = EscapePath.length_mm(level.union, level.reactor.position(),
			level.start_position())
	result["escape_mm"] = path_mm
	result["countdown_ticks"] = level.reactor.meltdown_ticks() if path_mm == EscapePath.UNREACHABLE \
			else level.reactor.meltdown_ticks_for_path(path_mm)
	var found: Array[String] = inputs.validate(level, generator)
	if found.is_empty() and level.debris != null:
		var held: Array[int] = []
		if SeedSweep.debris_route(level, inputs.tuning.radius, held) != "":
			found.append("debris_route")
	result["valid"] = found.is_empty()
	return result


## Cards for `first_seed` up to `first_seed + count - 1`, or one card holding
## only "error" when a data file is broken.
static func cards(first_seed: int, count: int) -> Array[Dictionary]:
	var inputs: SeedLevel = SeedLevel.load_inputs()
	var list: Array[Dictionary] = []
	if inputs.error != "":
		list.append({"error": inputs.error})
		return list
	for level_seed: int in range(first_seed, first_seed + count):
		list.append(card(inputs, level_seed))
	return list


## `MELTDOWN_SEED_CARD {"seed":s,...,"valid":true}`, keys in a fixed order and
## the escape and countdown to one decimal, so a line is the same on every machine.
static func line(seed_card: Dictionary) -> String:
	var escape_mm: int = seed_card["escape_mm"]
	var escape_m: String = "-1" if escape_mm == EscapePath.UNREACHABLE \
			else "%.1f" % (escape_mm / float(RobotSpawn.SCALE))
	return '%s {"seed":%d,"modules":%d,"loops":%d,"robots":%d,"spheres":%d,"doors":%d,"fires":%d,"escape_m":%s,"countdown_s":%.1f,"valid":%s}' % [
			CARD_TAG, seed_card["seed"], seed_card["modules"], seed_card["loops"],
			seed_card["robots"], seed_card["spheres"], seed_card["doors"], seed_card["fires"],
			escape_m, seed_card["countdown_ticks"] / float(ReactorState.TICKS_PER_SECOND),
			"true" if seed_card["valid"] else "false"]


## The kinds of `KINDS` that `seed_card` has; "longest" when its escape is
## `longest_mm`.
static func kinds_of(seed_card: Dictionary, longest_mm: int) -> Array[String]:
	var found: Array[String] = []
	if seed_card["loops"] > 0:
		found.append("loop")
	if seed_card["doors"] > 0:
		found.append("door")
	if seed_card["fires"] > 0:
		found.append("fire")
	if seed_card["escape_mm"] == longest_mm and longest_mm > 0:
		found.append("longest")
	return found


## Every seed named by a step of the suite at `path` (the m3 suite by default),
## so the pick can prefer seeds the owner has not watched the bot fly.
static func suite_seeds(path: String = M3SeedPick.SUITE_PATH) -> Array[int]:
	var seeds: Array[int] = []
	var data: Variant = JSON.parse_string(SeedLevel.read_text(path))
	if not data is Dictionary:
		return seeds
	for step: Variant in (data as Dictionary).get("steps", []):
		if step is Dictionary and (step as Dictionary).has("seed"):
			var level_seed: int = int(step["seed"])
			if not seeds.has(level_seed):
				seeds.append(level_seed)
	return seeds


## `count` seeds from the valid `seed_cards` that cover `KINDS` between them, as
## {"seeds": [...], "missing": [kinds the chosen seeds do not cover]}. The
## longest escape is the longest among the valid cards. Seeds in `avoid` (the
## suite's, which the owner has watched the bot fly) are left out unless the
## other seeds cannot cover all four kinds. Each pass is greedy: the seed
## covering most of what is still missing, on a tie a seed outside `avoid`, then
## the lowest seed. It depends only on the cards, so a range always gives the
## same pick.
static func pick(seed_cards: Array[Dictionary], avoid: Array[int], count: int = 3) -> Dictionary:
	var valid: Array[Dictionary] = []
	var longest_mm: int = 0
	for seed_card: Dictionary in seed_cards:
		if seed_card.get("valid", false):
			valid.append(seed_card)
			longest_mm = maxi(longest_mm, seed_card["escape_mm"])
	var unseen: Dictionary = _greedy(valid, longest_mm, avoid, true, count)
	if (unseen["missing"] as Array).is_empty():
		return unseen
	var any: Dictionary = _greedy(valid, longest_mm, avoid, false, count)
	return any if (any["missing"] as Array).size() < (unseen["missing"] as Array).size() else unseen


static func _greedy(valid: Array[Dictionary], longest_mm: int, avoid: Array[int],
		skip_avoided: bool, count: int) -> Dictionary:
	var missing: Array[String] = KINDS.duplicate()
	var chosen: Array[int] = []
	while chosen.size() < count:
		var best: Dictionary = {}
		var best_score: int = -1
		for seed_card: Dictionary in valid:
			var level_seed: int = seed_card["seed"]
			var avoided: bool = avoid.has(level_seed)
			if chosen.has(level_seed) or (avoided and skip_avoided):
				continue
			var covered: int = 0
			for kind: String in kinds_of(seed_card, longest_mm):
				if missing.has(kind):
					covered += 1
			# Coverage first, then an unseen seed, then the lowest seed.
			var score: int = covered * 2 + (0 if avoided else 1)
			if score > best_score or (score == best_score and level_seed < int(best["seed"])):
				best = seed_card
				best_score = score
		if best.is_empty():
			break
		chosen.append(int(best["seed"]))
		for kind: String in kinds_of(best, longest_mm):
			missing.erase(kind)
	return {"seeds": chosen, "missing": missing}


## `MELTDOWN_SEED_PICK {"seeds":[a,b,c],"missing":[]}`.
static func pick_line(picked: Dictionary) -> String:
	var seeds: Array[String] = []
	for level_seed: int in picked["seeds"]:
		seeds.append(str(level_seed))
	var missing: Array[String] = []
	for kind: String in picked["missing"]:
		missing.append('"%s"' % kind)
	return '%s {"seeds":[%s],"missing":[%s]}' % [PICK_TAG, ",".join(seeds), ",".join(missing)]


func _init() -> void:
	var options: Dictionary[String, int] = {"seeds": 200, "first": 1, "pick": 0}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() != 2 or not options.has(parts[0]) or not parts[1].is_valid_int():
			printerr("unknown option ", argument, "; expected --seeds=N, --first=S or --pick=N")
			quit(2)
			return
		options[parts[0]] = parts[1].to_int()
	if options["seeds"] < 1 or options["pick"] < 0:
		printerr("--seeds must be at least 1 and --pick at least 0")
		quit(2)
		return
	var list: Array[Dictionary] = cards(options["first"], options["seeds"])
	if list.size() == 1 and list[0].has("error"):
		printerr(list[0]["error"])
		quit(1)
		return
	if options["pick"] == 0:
		for seed_card: Dictionary in list:
			print(line(seed_card))
		quit(0)
		return
	var picked: Dictionary = pick(list, suite_seeds(), options["pick"])
	for level_seed: int in picked["seeds"]:
		print(line(list[level_seed - options["first"]]))
	print(pick_line(picked))
	quit(0 if (picked["missing"] as Array).is_empty() else 1)
