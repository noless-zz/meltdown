extends SceneTree

## Runs the generator and the level validator over a range of seeds and prints
## one summary line (#317, #357, GEN-3) with the failing seeds per check and how
## far the reactors are from the entrance (#924), for a nightly job with 10,000
## seeds:
##
##     godot --headless --path game -s res://tests/validate_seeds.gd -- --seeds=10000
##
## Options: `--seeds=N` (default 1000), `--first=S` (first seed, default 1),
## `--modules=M` (modules per level, default `SeedSweep.MODULE_COUNT`),
## `--keep=K` (failure messages to print, default `SeedSweep.KEPT_FAILURES`; 0
## prints every one, for the nightly job's summary, #358). The failure messages
## go to stderr. Exit code 0 only when every seed passed.

const SeedSweep := preload("res://tests/seed_sweep.gd")


func _init() -> void:
	var options: Dictionary[String, int] = {"seeds": 1000, "first": 1, "modules": SeedSweep.MODULE_COUNT,
			"keep": SeedSweep.KEPT_FAILURES}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() != 2 or not options.has(parts[0]) or not parts[1].is_valid_int():
			printerr("unknown option ", argument, "; expected --seeds=N, --first=S, --modules=M or --keep=K")
			quit(2)
			return
		options[parts[0]] = parts[1].to_int()
	if options["seeds"] < 1 or options["modules"] < 1 or options["keep"] < 0:
		printerr("--seeds and --modules must be at least 1, --keep at least 0")
		quit(2)
		return
	var result: Dictionary = SeedSweep.run(options["first"], options["seeds"], options["modules"], options["keep"])
	for message: String in result["failures"]:
		printerr(message)
	print(SeedSweep.summary(result))
	quit(0 if result["failed"] == 0 else 1)
