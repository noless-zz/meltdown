extends SceneTree

## The thinnest rock between tunnels over a run of generated levels (#1240,
## GEN-3, GEN-5), so a wall-thickness rule can be decided on evidence. Not part
## of `run_tests.gd`; run it like `validate_seeds.gd`:
##
##     godot --headless --path game -s res://tests/wall_gap_sweep.gd -- --seeds=100
##
## Options: `--seeds=N` (default 100), `--first=S` (first seed, default 1).
## Prints each seed's thinnest wall, then the minimum, the 5th percentile and
## the median over the seeds, and the seeds below `THIN_M`. Each level is the
## generator's union for the seed with the shipped modules, as `--seed` flies it.

## Walls thinner than this are listed by seed, in metres.
const THIN_M: float = 1.0


func _init() -> void:
	var options: Dictionary[String, int] = {"seeds": 100, "first": 1}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() != 2 or not options.has(parts[0]) or not parts[1].is_valid_int():
			printerr("unknown option ", argument, "; expected --seeds=N or --first=S")
			quit(2)
			return
		options[parts[0]] = parts[1].to_int()
	var inputs: SeedLevel = SeedLevel.load_inputs()
	if inputs.error != "":
		printerr("level inputs rejected: ", inputs.error)
		quit(1)
		return
	var gaps: Array[float] = []
	var thin: Array[String] = []
	for level_seed: int in range(options["first"], options["first"] + options["seeds"]):
		var generator: MineGenerator = inputs.generate(level_seed)
		var found: Dictionary = WallGap.thinnest(generator.union)
		var gap: float = float(found["gap_m"])
		gaps.append(gap)
		print("seed %d: %s (boxes %d and %d of %d)" % [level_seed, _metres(gap), found["box_a"], found["box_b"],
			generator.union.boxes.size()])
		if gap < THIN_M:
			thin.append("%d (%s)" % [level_seed, _metres(gap)])
	gaps.sort()
	print("WALL_GAP seeds %d..%d: min %s, p5 %s, median %s; below %.1f m: %d seeds%s" % [options["first"],
		options["first"] + options["seeds"] - 1, _metres(gaps[0]), _metres(percentile(gaps, 0.05)),
		_metres(percentile(gaps, 0.5)), THIN_M, thin.size(), (": " + ", ".join(thin)) if not thin.is_empty() else ""])
	quit(0)


## The nearest-rank `fraction` percentile of the sorted `values`.
static func percentile(values: Array[float], fraction: float) -> float:
	var rank: int = clampi(ceili(fraction * values.size()) - 1, 0, values.size() - 1)
	return values[rank]


static func _metres(gap: float) -> String:
	return "none" if gap == INF else "%.2f m" % gap
