class_name LevelStart
extends RefCounted

## Builds the main scene's session for what the launch flies: the test tunnel,
## a level file (#291) or a generated seed (#382), and builds it again from its
## start when the destroyed ship's pilot restarts (#616). Split out of
## `main.gd` to keep it under 300 lines.
##
## It sits beside `main.gd` because it joins the `net/` session to the level
## drawing. A restart is a new session; nothing is written into the old one (MP-2).

## Where the test tunnel sits relative to the simulation origin, where the ship starts:
## 1 m below, the ship's radius, so the first tick does not push it off the floor.
const TUNNEL_OFFSET: Vector3 = Vector3(0.0, -1.0, 0.0)
## The ship's feel values, tuned after headset sessions without code changes.
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
const ROBOT_SPAWNS_PATH: String = "res://data/levels/test_tunnel_robots.json"  # (#228)

## What this launch flies, from `LevelSwitch.requested_path`: a level file
## path, `seed:<n>`, or "" for the test tunnel. Kept so a restart flies the
## same level, and a `--seed=random` pick is not drawn again.
var source: String = ""
## The run `--run=<n>` flies (#989), or null when the launch flies one level.
var run: RunWiring = null
## Told each new session's ship loadout (CMB-8, #1050), so a fitted look-aim
## module takes effect; null in tests that need no comfort.
var comfort: ComfortWiring = null


func _init(p_comfort: ComfortWiring = null) -> void:
	comfort = p_comfort


## The test tunnel's session: inside the walls the tunnel is drawn around
## (FLT-3), with the tuning file's values or, if it is rejected, the defaults,
## the tunnel's robots, and every weapon file as a part a held part can be
## slotted from (#320), picked up and pulled as the salvage file says (#600).
static func tunnel_session(input: ShipInputSource) -> LocalSession:
	return LocalSession.new(0, input, TestTunnel.interior_box(TUNNEL_OFFSET),
		LocalSession.load_tuning(SHIP_TUNING_PATH), LocalSession.load_spawns(ROBOT_SPAWNS_PATH),
		null, LocalSession.load_parts()).use_salvage_rules(SpawnLoader.load_salvage_rules())


## The session for the level file or seed at `path`, from the level's start
## with its robots, with the level drawn under `world` where the tunnel was;
## null, drawing nothing, for "" or a rejected file.
## `rules`, when given, turns component drops and miner rescue on (#1028).
## `tuning`, when given, is the ship flown in place of the ship file's (#1057).
static func level_session(world: Node3D, path: String, input: ShipInputSource,
		rules: RunLevelRules = null, tuning: ShipTuning = null) -> LocalSession:
	var level: LevelDef = LevelSwitch.load_level(path) if path != "" else null
	if level == null:
		return null
	var session: LocalSession = LocalSession.for_level(level, 0, input,
		tuning if tuning != null else LocalSession.load_tuning(SHIP_TUNING_PATH))
	if rules != null:
		rules.install(session, level)
	LevelSwitch.show_level(world, level)
	return session


## `level_session` for `path`, with drops and rescue on when `path` is the
## level the run flies now (#1028): a level flown alone keeps them off. The
## run's level flies the fitted ship too (`run_tuning`, #1057), and its loadout
## is the one handed to the comfort wiring.
func session_for(world: Node3D, path: String, input: ShipInputSource) -> LocalSession:
	return hand_loadout(level_session(world, path, input, run_rules(path), run_tuning(path)))


## The ship a session for `path` flies (#1057, CRF-4, CRW-1): the run's fitted
## ship (`RunShip`) when the run flies `path` now, otherwise null, which flies
## the plain ship file, so `--level`, `--seed` and the tunnel never move.
func run_tuning(path: String) -> ShipTuning:
	if run == null or not run.active() or path != run.level_source():
		return null
	return run.ship.tuning_for(run.profile, run.roles)


## The launch's start (#1050): `session_for(path)`, or, for "" or a rejected
## file, `kept` (the test tunnel's session) with its loadout handed too, so a
## ship file launched straight into the tunnel still fits its modules.
func start_or_keep(world: Node3D, path: String, input: ShipInputSource,
		kept: LocalSession) -> LocalSession:
	var fresh: LocalSession = session_for(world, path, input)
	return fresh if fresh != null else hand_loadout(kept)


## The local ship's loadout in `session` (CMB-8, #1050): the one the session
## equipped, else its ship file's; an empty loadout without either, so a module
## from an earlier level never sticks. The caller only reads it (MP-2).
static func local_loadout(session: LocalSession) -> ShipLoadout:
	if session == null:
		return ShipLoadout.new()
	if session.replay.loadout != null:
		return session.replay.loadout
	return session.replay.tuning.loadout if session.replay.tuning != null else ShipLoadout.new()


## Hands `session`'s local loadout to `comfort`, if any, and returns `session`.
## Every start goes through here: launch, restart, a dev menu level switch and
## a run's next level. A null session hands nothing; the session kept is unchanged.
func hand_loadout(session: LocalSession) -> LocalSession:
	if comfort != null and session != null:
		comfort.set_loadout(local_loadout(session))
	return session


## The rules a session for `path` gets: the data files' when the run flies
## `path` now and has `RunWiring.level_rules` on, otherwise null. Drops are
## weighted by the run's chosen shaft (`RunWiring.level_reward`, #1000).
func run_rules(path: String) -> RunLevelRules:
	if run == null or not run.active() or not run.level_rules or path != run.level_source():
		return null
	return RunLevelRules.load_files(RunLevelRules.COMPONENTS_DIR, RunLevelRules.RESCUE_FILE,
		run.level_reward())


## Takes what the launch asks to fly (`LevelSwitch.requested_path`). A run,
## `run:<n>`, starts a `RunWiring` whose current level becomes `source`; its
## levels fly the fitting saved by the hub.
## Returns the run, or null for a single level.
func choose(p_source: String, profiles: ProfileStore = null) -> RunWiring:
	source = p_source
	run = null
	if p_source.begins_with(LevelSwitch.RUN_PREFIX):
		run = RunWiring.new(LevelSwitch.seed_from(p_source.substr(LevelSwitch.RUN_PREFIX.length())),
			profiles if profiles != null else ProfileStore.new())
		run.ship.fittings = FittingStore.new()  # The hub's fitting, beside the profile (#1057).
		source = run.level_source()
	return run


## A new session for `source` from its start: the level again, or the tunnel,
## drawn again in place of any level drawn before (#795). With a run, `ended`
## (the session the restart replaces) moves it on first (#989): an escape or a
## lost ship flies the run's next level or a new run. A `source` the dev menu
## changed leaves the run; one the shaft panel's escape moved on does not.
func fresh_session(world: Node3D, input: ShipInputSource, ended: LocalSession = null) -> LocalSession:
	if run != null and run.active() and ended != null:
		if source != run.level_source() and not run.escape_taken:  # A shaft choice moved it on (#990).
			run.stop()
		elif RunWiring.ends_level(ended.sim.outcome(), ended.current_ship().hull):
			source = run.after_session(ended)
	var session: LocalSession = session_for(world, source, input)
	if session != null:
		return session
	LevelSwitch.show_tunnel(world, TUNNEL_OFFSET)
	return hand_loadout(tunnel_session(input))


## The seed digits and level name the status panel names `p_source` by
## (#747): `seed:31` is ["31", ""], a level file is ["", its file name without
## `_level.json`, upper-cased, so `g2` is "G2"], and the tunnel is ["", ""]. A
## scaled run level (#1011) is named by its seed alone: `seed:31:robots=1.3` is ["31", ""].
## Level files carry no name of their own yet.
static func shown_level(p_source: String) -> PackedStringArray:
	if p_source == "":
		return PackedStringArray(["", ""])
	if p_source.begins_with(LevelSwitch.SEED_PREFIX):
		var digits: String = p_source.substr(LevelSwitch.SEED_PREFIX.length())
		return PackedStringArray([digits.get_slice(LevelSwitch.ROBOTS_SUFFIX, 0), ""])
	return PackedStringArray(["", p_source.get_file().trim_suffix(LevelSwitch.LEVEL_SUFFIX).to_upper()])
