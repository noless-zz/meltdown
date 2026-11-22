class_name SessionLoader
extends RefCounted

## Builds a `LocalSession`'s simulation and replay from data: the walls, the
## ship's tuning and loadout, the robots, the part catalogue and a level's
## boxes, start pose, reactor and debris (MP-3, ARC-4, #1156). The host and the
## dedicated server need this without `LocalSession`'s local fixed tick.
##
## Nothing here reads the clock, nodes or input devices (ARC-1). Every value
## goes into the replay before the sim takes it back, so a replay of the session
## meets the same walls, ship and robots (ARC-2).


## Gives `session` its replay and sim. `bounds` are the walls the ship flies
## inside, or null for open space. `tuning` gives every ship its feel values
## before the first tick; null, or a tuning whose `error` is set, flies the
## built-in defaults. A tuning whose loadout has been resolved (see
## `LocalSession.load_tuning`) starts the ship armed, and the weapons are
## recorded in the replay (CMB-1, ARC-2). `robots` (see
## `LocalSession.load_spawns`) are spawned before the first tick and recorded in
## the replay too, so a replay starts with the same robots (CMB-3). `loadout`,
## when given, replaces the tuning's: a replay read from text carries its
## weapons resolved on their own lines, not in its tuning, and flying it again
## needs them (DEV-6). `parts` (see `LocalSession.load_parts`) is the part
## catalogue a held part is slotted from; it is set before the first tick and
## recorded in the replay (SLV-1, #267).
static func build(session: LocalSession, run_seed: int, bounds: BoxBounds, tuning: ShipTuning,
		robots: Array[RobotSpawn], loadout: ShipLoadout,
		parts: Dictionary[String, WeaponDef]) -> void:
	var replay: Replay = Replay.new(run_seed, 1)
	session.replay = replay
	if bounds != null:
		replay.set_box(SessionSnapshots.to_mm(bounds.min_corner),
				SessionSnapshots.to_mm(bounds.max_corner))
	if tuning != null and tuning.error == "":
		replay.tuning = tuning
	# The walls are taken back from the replay, rounded to its whole
	# millimetres, so that running the replay meets exactly the same walls.
	# The tuning goes through the replay too, so a replay flies the same ship.
	var sim: Sim = Sim.new(run_seed, 1, replay.bounds())
	session.sim = sim
	replay.apply_tuning(sim)
	if loadout == null and replay.tuning != null:
		loadout = replay.tuning.loadout
	if loadout != null and loadout.is_armed():
		replay.loadout = loadout
		sim.equip(replay.loadout)
	if RobotSpawn.spawn_all(sim, robots):
		replay.robots = robots.duplicate()
	parts = SpawnLoader.with_loadout_weapons(parts, replay.loadout)
	var parts_problem: String = sim.set_parts(parts)
	if parts_problem == "":
		replay.parts = parts.duplicate()
	else:
		print("Meltdown: part catalogue rejected (%s); parts cannot be slotted" % parts_problem)


## A session in `level`'s walls (GEN-5): every box goes into the replay, so a
## replay meets the same walls (ARC-2), the ship starts at the level's start
## pose, and the level's robots are resolved and armed from `robot_dir` and
## `robot_weapon_dir` as `LocalSession.load_spawns` does (CMB-3, #269, #291,
## #612). Its part catalogue is every weapon in `weapon_dir`, so parts the
## robots drop can be slotted (SLV-1, #320). The level's start pose is written
## to the replay's start line and the ship is placed from what the line reads
## back, so a level that does not start at the origin facing -z replays to the
## same hash (#340). The level's reactor, if any, is armed on the sim and
## recorded in the replay before the first tick, so the main scene flies with it
## (RUN-2, #332), and so is its debris (RUN-4, #439). `level` must have parsed
## without an error.
static func for_level(level: LevelDef, run_seed: int = 0, input_source: ShipInputSource = null,
		tuning: ShipTuning = null, robot_dir: String = SpawnLoader.ROBOT_DIR,
		weapon_dir: String = SpawnLoader.WEAPON_DIR,
		robot_weapon_dir: String = SpawnLoader.ROBOT_WEAPON_DIR) -> LocalSession:
	var robots: Array[RobotSpawn] = SpawnLoader.resolve_list(level.robots, "in the level",
		robot_dir, robot_weapon_dir)
	var session: LocalSession = LocalSession.new(run_seed, input_source, null, tuning, robots,
		null, SpawnLoader.load_parts(weapon_dir))
	session.use_salvage_rules(SpawnLoader.load_salvage_rules())
	var mins: Array[Vector3i] = []
	var maxs: Array[Vector3i] = []
	for box: BoxBounds in level.union.boxes:
		mins.append(SessionSnapshots.to_mm(box.min_corner))
		maxs.append(SessionSnapshots.to_mm(box.max_corner))
	session.replay.set_boxes(mins, maxs)
	# Taken back from the replay, rounded like the single-box walls in `build`.
	session.sim.set_walls(session.replay.walls())
	# Taken back from the replay too: its millimetres and thousandths are what a
	# replay starts from, and an unrounded live pose would drift away from it.
	session.replay.set_start_pose(0, level.start_position(), level.start_facing())
	ReplayStartLine.apply(session.replay, session.sim)
	# Separate copies, so the live run's damage never reaches the copy a
	# replay starts from (RUN-2, ARC-2, #332).
	if level.reactor != null:
		session.replay.reactor = level.reactor.fresh_copy()
		session.sim.set_reactor(level.reactor.fresh_copy())
	if level.debris != null and level.debris.size() > 0:
		session.replay.debris = level.debris.fresh_copy()
		session.sim.set_debris(level.debris.fresh_copy())
	session.reset_ship_snapshots()
	return session
