extends SceneTree

## Measures the thinnest wall between tunnels (`WallGap`) on a run of generated
## levels and prints how thin the walls get (#1240, GEN-3, GEN-5), so whether
## to enforce a minimum thickness is decided on evidence (owner's playtest
## #1225). Each seed's level is the one `--seed` flies, built by `SeedLevel`
## like `validate_seeds.gd` builds it. Not part of `run_tests.gd`:
##
##     godot --headless --path game -s res://tests/wall_gap_sweep.gd -- --seeds=100 --first=1
##
## Options: `--seeds=N` (default 100), `--first=S` (first seed, default 1).
## Prints one `MELTDOWN_WALL_GAP` line per seed (its gap, the two boxes and the
## axis), then `MELTDOWN_WALL_GAPS` with the minimum, the 5th percentile and the
## median of the per-seed gaps (nearest rank, over levels that have a facing
## pair) and the seeds whose gap is below `THIN_M`. A last
## `MELTDOWN_WALL_GAPS_JOINED` line gives the same with pairs joined through a
## doorway counted too (`WallGap`'s `count_joined`). A measurement, never judged:
## the exit code is 0 unless an option is wrong, the data files are broken or a
## level does not build.

## Gaps below this, in metres, are listed by seed.
const THIN_M: float = 1.0
const AXES: String = "xyz"


func _init() -> void:
	var options: Dictionary[String, int] = {"seeds": 100, "first": 1}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() != 2 or not options.has(parts[0]) or not parts[1].is_valid_int():
			printerr("unknown option ", argument, "; expected --seeds=N or --first=S")
			quit(2)
			return
		options[parts[0]] = parts[1].to_int()
	if options["seeds"] < 1:
		printerr("--seeds must be at least 1")
		quit(2)
		return
	var inputs: SeedLevel = SeedLevel.load_inputs()
	if inputs.error != "":
		printerr(inputs.error)
		quit(1)
		return
	var gaps: Dictionary[int, float] = {}
	var joined_gaps: Dictionary[int, float] = {}
	var broken: int = 0
	for level_seed: int in range(options["first"], options["first"] + options["seeds"]):
		var level: LevelDef = inputs.level_of(inputs.generate(level_seed))
		if level.error != "":
			printerr("seed %d: %s" % [level_seed, level.error])
			broken += 1
			continue
		var found: WallGap = WallGap.of_union(level.union)
		gaps[level_seed] = found.gap_m
		joined_gaps[level_seed] = WallGap.of_union(level.union, true).gap_m
		print("MELTDOWN_WALL_GAP ", JSON.stringify(_seed_line(level_seed, found, level.union.boxes.size())))
	print("MELTDOWN_WALL_GAPS ", JSON.stringify(summarize(gaps)))
	print("MELTDOWN_WALL_GAPS_JOINED ", JSON.stringify(summarize(joined_gaps)))
	quit(0 if broken == 0 else 1)


## The summary of per-seed gaps (`seed` to metres, `INF` for a level with no
## facing pair): "seeds", "measured" (levels with a pair), "no_pair", "min_m",
## "p5_m" and "median_m" (nearest rank over the measured; -1 with none), and
## "below_1m", the seeds under `THIN_M` in seed order.
static func summarize(gaps: Dictionary[int, float]) -> Dictionary:
	var measured: Array[float] = []
	var thin: Array[int] = []
	var seeds: Array[int] = []
	seeds.assign(gaps.keys())
	seeds.sort()
	for level_seed: int in seeds:
		var gap: float = gaps[level_seed]
		if gap == INF:
			continue
		measured.append(gap)
		if gap < THIN_M:
			thin.append(level_seed)
	measured.sort()
	return {"seeds": gaps.size(), "measured": measured.size(), "no_pair": gaps.size() - measured.size(),
			"min_m": _rank(measured, 0.0), "p5_m": _rank(measured, 0.05),
			"median_m": _rank(measured, 0.5), "below_1m": thin}


## The nearest-rank `share` percentile of `sorted`, rounded to the millimetre
## the levels are built in; the smallest for 0, -1 when empty.
static func _rank(sorted: Array[float], share: float) -> float:
	if sorted.is_empty():
		return -1.0
	var index: int = clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)
	return snappedf(sorted[index], 0.001)


static func _seed_line(level_seed: int, found: WallGap, box_count: int) -> Dictionary:
	if not found.has_pair():
		return {"seed": level_seed, "boxes": box_count, "gap_m": null}
	return {"seed": level_seed, "boxes": box_count, "gap_m": snappedf(found.gap_m, 0.001),
			"between": [found.first_box, found.second_box], "axis": AXES[found.axis]}
