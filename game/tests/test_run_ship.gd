extends RefCounted

## Run levels fly the fitted ship with the crew's benefits (#1057, CRF-4, CMB-1,
## CRW-1, RUN-7, ARC-2, MP-2): `LevelStart.session_for` builds the run's level
## from `RunShip`, which reads the scratch profile and fitting stores here, and
## a single level flown alone keeps the plain ship file.

const RUN_SEED: int = 12345
const PROFILE_PATH: String = "user://test_run_ship_profile.json"
const FITTING_PATH: String = "user://test_run_ship_fitting.json"
const SHIP_FILE: String = "res://data/ships/default_ship.json"


## Fires the primary weapon every tick, so a replay test exercises the weapon.
class FiringInput:
	extends ShipInputSource

	func next_input(_tick: int) -> ShipInput:
		var input: ShipInput = ShipInput.new()
		input.fire_primary = true
		return input


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


## Saves a profile with `crafted` and `shield_crew` shield technicians, and a
## fitting with `primary` in primary slot 1 and `utility` in the utility slots.
func _stores(crafted: Array[String], shield_crew: int, primary: String, utility: Array[String] = []) -> String:
	_clean()
	var profile: Profile = Profile.new()
	profile.crafted.assign(crafted)
	for index: int in shield_crew:
		profile.crew.append({"id": "crew-%d" % (index + 1), "role": "shield_tech"})
	var fitting: Fitting = Fitting.new()
	fitting.primary = [primary, ""]
	fitting.utility.assign(utility)
	var profiles: ProfileStore = ProfileStore.new(PROFILE_PATH)
	var fittings: FittingStore = FittingStore.new(FITTING_PATH)
	if not profiles.save(profile):
		return profiles.message
	if not fittings.save(fitting):
		return fittings.message
	return ""


## A `LevelStart` flying run `RUN_SEED` from the scratch stores, as `choose`
## starts one from the pilot's own files; no shaft choice, so an escape moves on.
func _level_start(comfort: ComfortWiring = null) -> LevelStart:
	var level_start: LevelStart = LevelStart.new(comfort)
	level_start.run = RunWiring.new(RUN_SEED, ProfileStore.new(PROFILE_PATH), Callable(), "", false)
	level_start.run.ship.fittings = FittingStore.new(FITTING_PATH)
	level_start.source = level_start.run.level_source()
	return level_start


static func _primary(session: LocalSession) -> String:
	return LevelStart.local_loadout(session).ids_of("primary")[0]


static func _plain() -> ShipTuning:
	return LocalSession.load_tuning(SHIP_FILE)


func test_a_fitted_weapon_flies_on_run_levels_one_and_two() -> String:
	var problem: String = _stores(["needle_gun"], 0, "needle_gun")
	if problem != "":
		return problem
	var level_start: LevelStart = _level_start()
	var world: Node3D = Node3D.new()
	var first: LocalSession = level_start.session_for(world, level_start.source, null)
	level_start.run.after_level(ExitRule.Outcome.ESCAPED, 100.0, {})
	var second: LocalSession = level_start.session_for(world, level_start.run.level_source(), null)
	world.free()
	_clean()
	if first == null or second == null:
		return "a run level was not built"
	if level_start.run.state.level_index != 1:
		return "the run is on level index %d after an escape" % level_start.run.state.level_index
	for session: LocalSession in [first, second]:
		if _primary(session) != "needle_gun" or session.sim.ships[0].primary_ids[0] != "needle_gun":
			return "primary slot 1 holds %s" % _primary(session)
	return ""


func test_two_shield_crew_raise_the_shield() -> String:
	var problem: String = _stores([], 2, "")
	if problem != "":
		return problem
	var level_start: LevelStart = _level_start()
	var raised: ShipTuning = level_start.run_tuning(level_start.source)
	_clean()
	var want: float = _plain().max_shield + 2.0 * 5.0  # Two shield technicians at 5 each (roles.json).
	if raised == null or raised.max_shield != want:
		return "max_shield %s, expected %s" % [raised.max_shield if raised != null else -1.0, want]
	return ""


func test_an_invalid_fitting_flies_the_ship_file_and_logs_one_note() -> String:
	var problem: String = _stores([], 0, "needle_gun")  # Fitted but never crafted.
	if problem != "":
		return problem
	var level_start: LevelStart = _level_start()
	var tuning: ShipTuning = level_start.run_tuning(level_start.source)
	level_start.run_tuning(level_start.source)  # A second level start logs nothing new.
	_clean()
	var notes: Array[String] = level_start.run.ship.notes
	if notes.size() != 1 or not notes[0].contains("not crafted"):
		return "notes %s" % [notes]
	if tuning == null or tuning.loadout.ids_of("primary")[0] != "pulse_cannon":
		return "the ship file's pulse cannon does not fly"
	if ReplayLines.tuning_text(tuning) != ReplayLines.tuning_text(_plain()):
		return "the feel values moved"
	return ""


func test_a_single_level_ignores_the_fitting() -> String:
	var problem: String = _stores(["needle_gun"], 2, "needle_gun")
	if problem != "":
		return problem
	var level_start: LevelStart = _level_start()
	var other: String = LevelSwitch.seed_source(31)
	var during_run: ShipTuning = level_start.run_tuning(other)
	var alone: LevelStart = LevelStart.new()
	alone.choose(other)
	var world: Node3D = Node3D.new()
	var session: LocalSession = alone.session_for(world, other, null)
	world.free()
	_clean()
	if during_run != null:
		return "a level the run does not fly got the fitted ship"
	if alone.run != null or session == null or _primary(session) != "pulse_cannon":
		return "--seed flies %s" % (_primary(session) if session != null else "nothing")
	if ReplayLines.tuning_text(session.replay.tuning) != ReplayLines.tuning_text(_plain()):
		return "--seed's feel values are not the ship file's"
	return ""


## With nothing crafted, fitted or crewed, the built ship is the ship file to
## the last digit, so a run that changes nothing keeps its hashes.
func test_an_empty_profile_and_fitting_fly_the_ship_file_exactly() -> String:
	_clean()
	var level_start: LevelStart = _level_start()
	var built: ShipTuning = level_start.run_tuning(level_start.source)
	level_start.run.ship.enabled = false
	var off: ShipTuning = level_start.run_tuning(level_start.source)
	var plain: ShipTuning = _plain()
	for tuning: ShipTuning in [built, off]:
		if tuning == null or ReplayLines.tuning_text(tuning) != ReplayLines.tuning_text(plain) \
				or ReplayLines.weapon_lines(tuning.loadout) != ReplayLines.weapon_lines(plain.loadout):
			return "the built ship differs from the ship file"
	if not level_start.run.ship.notes.is_empty():
		return "notes %s" % [level_start.run.ship.notes]
	return ""


## ARC-2: the replay's tuning and weapon lines carry the fitted ship, so the
## replay read back from text flies to the same hash.
func test_a_run_level_replay_rebuilds_the_fitted_ship() -> String:
	var problem: String = _stores(["needle_gun"], 2, "needle_gun")
	if problem != "":
		return problem
	var level_start: LevelStart = _level_start()
	var world: Node3D = Node3D.new()
	var session: LocalSession = level_start.session_for(world, level_start.source, FiringInput.new())
	world.free()
	_clean()
	for tick: int in 180:
		session.advance(ShipState.TICK_DT)
	var read: Replay = Replay.from_text(session.replay.to_text())
	if read.error != "":
		return read.error
	if read.loadout == null or read.loadout.ids_of("primary")[0] != "needle_gun" \
			or read.tuning.max_shield != _plain().max_shield + 10.0:
		return "the replay does not carry the fitted ship"
	var sim: Sim = read.run()
	if sim == null or sim.state_hash() != session.sim.state_hash():
		return "the replay flies to %s, the session ended at %d" % [
			sim.state_hash() if sim != null else read.run_error, session.sim.state_hash()]
	return ""


func test_the_fitted_loadout_is_handed_to_comfort() -> String:
	var problem: String = _stores(["look_aim"], 0, "", ["look_aim"])
	if problem != "":
		return problem
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var level_start: LevelStart = _level_start(comfort)
	var world: Node3D = Node3D.new()
	level_start.session_for(world, level_start.source, null)
	var fitted: bool = comfort.look_aim.module_fitted
	level_start.run.stop()
	level_start.session_for(world, LevelSwitch.seed_source(31), null)
	var plain: bool = comfort.look_aim.module_fitted
	world.free()
	_clean()
	if not fitted or plain:
		return "look-aim module fitted %s on the run level, %s on a level alone" % [fitted, plain]
	return ""
