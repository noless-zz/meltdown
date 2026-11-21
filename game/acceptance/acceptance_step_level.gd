class_name AcceptanceStepLevel
extends RefCounted

## The level side of an acceptance step (DEV-6): building a generated level
## from the step's seed for its replay to fly (#460, GEN-1, GEN-2), and saying
## why a step's replay could not be flown. Kept apart from `AcceptanceRunner`,
## which drives the frames, so that file stays short.
##
## A seed step's level comes from `SeedLevel`, the loader `--seed=<n>` and the
## validator sweep use, with the shipped data files. Its replay holds only the
## inputs, so a change to a generator, robot or debris value that changes the
## seed's level changes the flight and fails the step's hash, rather than
## flying the old level kept in the replay.

## The ship data file the main scene flies with, as `main.gd` loads it.
const SHIP_FILE: String = SeedLevel.SHIP_FILE


## Builds seed `level_seed`, draws it in `main` in place of the test tunnel
## and gives `main` a session in it fed by `source`. `overrides` maps a data
## file's `res://` path to text used in its place, so a test can change one.
## Returns why the step cannot fly, or "".
static func fly_seed(main: Node, level_seed: int, replay: Replay, source: ReplayInputSource,
		overrides: Dictionary = {}) -> String:
	if replay.box_mins_mm.size() > 0 or replay.reactor != null or not replay.robots.is_empty() \
			or (replay.debris != null and replay.debris.size() > 0):
		return "seed %d: the replay carries a level of its own; a seed step builds it from the seed" \
			% level_seed
	var level: LevelDef = SeedLevel.load_level(level_seed, LevelSwitch.DEFAULTS_FILE, "", overrides)
	if level == null:
		return "seed %d: the level was rejected; the log says why" % level_seed
	LevelSwitch.show_level(main as Node3D, level)
	main.set("session", LocalSession.for_level(level, replay.run_seed, source,
		LocalSession.load_tuning(SHIP_FILE)))
	return ""


## Takes down an end screen and its fade left by the step before (#917), so
## the step's frames and screenshots show its scene. A step replaces the
## session without the restart press that would take them down in play, and
## a `SHIP DESTROYED` or `ESCAPED` screen otherwise stays up for every later
## step. View only: the session and its hash are untouched (ARC-3).
static func clear_end_screens(main: Node) -> void:
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	if destroyed == null:
		return
	destroyed.reset()
	var overlay: FadeOverlay = main.get("fade_overlay") as FadeOverlay
	if overlay != null:
		# The same sum `main.advance_frame` draws, with the end screens' part now 0.
		var reset_hold: ResetHold = main.get("reset_hold") as ResetHold
		var dev_menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring
		overlay.set_alpha(maxf(maxf(reset_hold.alpha if reset_hold != null else 0.0, destroyed.fade_alpha()),
			dev_menu.alpha if dev_menu != null else 0.0))


## The hash of everything `replay` records before its inputs: walls, start,
## reactor, debris, tuning, weapons, robots and parts, as the session set them
## up before the first tick. Those are copies the run never moves, so it reads
## the same at the end of the flight as at the start.
static func level_hash(replay: Replay) -> int:
	var text: String = replay.to_text()
	return text.substr(0, text.find("\ninputs\n")).hash()


## Why `step`'s replay could not be flown, or "". `source` is null when the
## replay could not be read or has more than one ship.
static func replay_problem(step: AcceptanceStep, source: ReplayInputSource) -> String:
	if step.replay_path == "":
		return ""
	if source == null:
		var replay: Replay = Replay.load_file(step.replay_path)
		if replay.error != "":
			return "replay %s: %s" % [step.replay_path, replay.error]
		return "replay %s: has %d ships; the scene flies one" % [step.replay_path, replay.ship_count]
	if source.overrun_ticks > 0:
		return "replay %s: flew %d ticks past its end" % [step.replay_path, source.overrun_ticks]
	return ""
