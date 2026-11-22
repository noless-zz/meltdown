class_name StartChoice
extends RefCounted

## Where a start of the game lands (#1171, CRW-2, PLT-2, RUN-8): the hub, now
## that runs start there, or straight into flight. A normal start, with no
## launch switch naming what to fly and the first-launch flight test already
## done (CMF-4), opens the hub on a new run before any level flies. `--run`,
## `--level`, `--seed`, `--acceptance=<suite>`, their intent extras and the
## first launch's flight test fly at once, as before, so every acceptance suite,
## replay and pinned hash is unchanged.
##
## The start-up hub is the hub between runs: its new run takes a fresh seed as
## a run after a loss does, its launch flies the fitted ship, a suspended run
## shows its resume row, and the view comes up through the end screen's fade
## (CMF-8). The ship is held behind it as between runs. It sits beside
## `main.gd` because it reads the launch arguments and joins `HubWiring` to
## `LevelStart`; it never writes simulation state (MP-2).

const HUB: String = "hub"
const FLIGHT: String = "flight"
## Launch arguments that name what to fly; any one of them flies at once.
const FLIGHT_ARGS: Array[String] = [LevelSwitch.ARG_PREFIX, LevelSwitch.SEED_ARG_PREFIX,
	LevelSwitch.RUN_ARG_PREFIX, AcceptanceRunner.ARG_PREFIX]
## The headset's intent extras for the same switches.
const FLIGHT_EXTRAS: Array[String] = [LevelSwitch.INTENT_EXTRA, LevelSwitch.SEED_INTENT_EXTRA,
	LevelSwitch.RUN_INTENT_EXTRA, AcceptanceRunner.INTENT_EXTRA]
const LOG_PREFIX: String = "Meltdown:"


## `HUB` or `FLIGHT` for user arguments `user_args`, the intent extras'
## values `extras` (by extra name; a missing or blank one is not given) and
## whether the first-launch flight test is done. A switch given with a bad
## value still flies, as it did before (the tunnel, with the value printed).
static func choose(user_args: PackedStringArray, extras: Dictionary, flight_test_done: bool) -> String:
	if not flight_test_done:
		return FLIGHT
	for arg: String in user_args:
		for prefix: String in FLIGHT_ARGS:
			if arg.begins_with(prefix):
				return FLIGHT
	for extra: String in FLIGHT_EXTRAS:
		if str(extras.get(extra, "")).strip_edges() != "":
			return FLIGHT
	return HUB


## `choose` for this launch: its user arguments, the headset's intent extras
## and the comfort choice saved at `choice_path`.
static func from_launch(choice_path: String = ComfortChoice.DEFAULT_PATH) -> String:
	var runtime: Object = InstallerProbe.android_runtime()
	var extras: Dictionary = {}
	if runtime != null:
		for extra: String in FLIGHT_EXTRAS:
			extras[extra] = InstallerProbe.intent_extra(runtime, extra)
	var choice: ComfortChoice = ComfortChoice.new()
	choice.load_from(choice_path)
	return choose(OS.get_cmdline_user_args(), extras, not choice.first_launch())


## Whether `host`, the main scene, opens in the hub. A scene outside the tree
## is a unit test calling `_ready` by hand, not a start of the game: it flies,
## so those tests never depend on the machine's saved comfort choice.
static func opens_hub(host: Node) -> bool:
	return host.is_inside_tree() and from_launch() == HUB


## What `LevelStart.choose` takes: `requested` (`LevelSwitch.requested_path`)
## when the start flies, or a new run, `run:<seed>`, when it opens the hub,
## with the seed from `pick_seed` (`LevelSwitch.random_seed` when not given)
## as a run after a loss picks it.
static func source(hub: bool, requested: String, pick_seed: Callable = Callable()) -> String:
	if not hub:
		return requested
	var picked: int = int(pick_seed.call()) if pick_seed.is_valid() else LevelSwitch.random_seed()
	print("%s the app opens in the hub, new run with seed %d" % [LOG_PREFIX, picked])
	return LevelSwitch.RUN_PREFIX + str(picked)


## Opens `hub` on the run `level_start` chose, dark, with the end screen left
## as a restart press leaves it, so the ship is held while the hub is open and
## its launch or resume fades the view in as between runs. False, opening
## nothing, without an active run or when the hub file is rejected; the run's
## first level then flies at once.
static func open_hub(hub: HubWiring, level_start: LevelStart, destroyed: DestroyedWiring) -> bool:
	if level_start.run == null or not level_start.run.active():
		return false
	hub.level_start = level_start
	if not hub.open_for(level_start.run):
		return false
	destroyed.sequence.state = DestroyedSequence.State.RESTARTED
	destroyed.sequence.elapsed = 0.0
	return true
