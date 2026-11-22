extends RefCounted

## The game reads the aim data files at level start (#1137, CMB-7, CMB-8,
## ARC-4, ARC-1, MP-2): a scratch file's values reach the simulation, a broken
## one logs its path and keeps the defaults, the shipped files load cleanly, and
## the shipped values fly the same hash as before. The values stay out of the
## session's replay, so every pinned level hash is unchanged.

const DIR: String = "user://test_aim_data"


func _write(name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path: String = DIR + "/" + name
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func test_a_scratch_aim_assist_file_reaches_the_sim() -> String:
	var path: String = _write("wide_assist.json", "{\"cone_degrees\": 10, \"range_m\": 60}")
	var session: LocalSession = AimData.apply(LocalSession.new(), AimData.LOOK_AIM_PATH, path)
	if session.sim.aim_assist.cone_degrees != 10.0:
		return "aim assist cone is %s, want 10" % session.sim.aim_assist.cone_degrees
	return ""


func test_a_scratch_look_aim_file_reaches_the_sim() -> String:
	var path: String = _write("wide_look.json",
		"{\"cone_degrees\": 40, \"gimbal_degrees_per_second\": 200}")
	var session: LocalSession = AimData.apply(LocalSession.new(), path, AimData.AIM_ASSIST_PATH)
	if session.sim.look_aim.cone_degrees != 40.0:
		return "look-aim cone is %s, want 40" % session.sim.look_aim.cone_degrees
	if session.sim.look_aim.gimbal_degrees_per_second != 200.0:
		return "look-aim gimbal is %s, want 200" % session.sim.look_aim.gimbal_degrees_per_second
	return ""


func test_a_broken_file_logs_its_path_and_keeps_the_defaults() -> String:
	var path: String = _write("broken_assist.json", "{\"cone_degrees\": \"wide\", \"range_m\": 60}")
	AimData.last_log = ""
	var session: LocalSession = AimData.apply(LocalSession.new(), AimData.LOOK_AIM_PATH, path)
	if session.sim.aim_assist.cone_degrees != 6.0:
		return "aim assist cone is %s after a broken file, want 6" % session.sim.aim_assist.cone_degrees
	if not AimData.last_log.begins_with(AimData.LOG_PREFIX) or not AimData.last_log.contains(path) \
			or not AimData.last_log.contains("cone_degrees"):
		return "the log line '%s' does not name the file and key" % AimData.last_log
	return ""


func test_a_missing_file_logs_its_path_and_keeps_the_defaults() -> String:
	var path: String = DIR + "/no_such_look_aim.json"
	AimData.last_log = ""
	var session: LocalSession = AimData.apply(LocalSession.new(), path, AimData.AIM_ASSIST_PATH)
	if session.sim.look_aim.cone_degrees != LookAim.new().cone_degrees:
		return "look-aim cone moved after a missing file"
	if not AimData.last_log.contains(path):
		return "the log line '%s' does not name the file" % AimData.last_log
	return ""


func test_the_shipped_files_load_with_no_error() -> String:
	AimData.last_log = ""
	if AimData.load_look_aim(AimData.LOOK_AIM_PATH) == null:
		return "look_aim.json was rejected: " + AimData.last_log
	if AimData.load_aim_assist(AimData.AIM_ASSIST_PATH) == null:
		return "aim_assist.json was rejected: " + AimData.last_log
	return "" if AimData.last_log == "" else "loading logged '%s'" % AimData.last_log


func test_the_tunnel_session_flies_the_shipped_values() -> String:
	var session: LocalSession = LevelStart.tunnel_session(LatestInputSource.new())
	var aim: LookAim = AimData.load_look_aim(AimData.LOOK_AIM_PATH)
	if session.sim.look_aim.values_hash() != aim.values_hash():
		return "the tunnel's look-aim is not the file's"
	if session.sim.aim_assist.cone_degrees != AimData.load_aim_assist(AimData.AIM_ASSIST_PATH).cone_degrees:
		return "the tunnel's aim assist is not the file's"
	return ""


func test_a_level_session_flies_the_shipped_values() -> String:
	var world: Node3D = Node3D.new()
	var session: LocalSession = LevelStart.level_session(world, "seed:31", null)
	world.free()
	if session == null:
		return "seed:31 built no session"
	if session.sim.look_aim.values_hash() != AimData.load_look_aim(AimData.LOOK_AIM_PATH).values_hash() \
			or session.sim.aim_assist.range_m != AimData.load_aim_assist(AimData.AIM_ASSIST_PATH).range_m:
		return "the level session did not take the aim data files"
	return ""


## The shipped files hold the simulation's defaults, so a session that reads
## them steps to the same hash as one that does not (pinned hashes unchanged).
func test_the_shipped_values_keep_the_hash() -> String:
	var plain: LocalSession = LocalSession.new(7)
	var read: LocalSession = AimData.apply(LocalSession.new(7))
	for i: int in 30:
		plain.advance(1.0 / 60.0)
		read.advance(1.0 / 60.0)
	if read.replay.look_aim != null:
		return "the aim data went into the replay, which moves pinned level hashes"
	if plain.sim.state_hash() != read.sim.state_hash():
		return "reading the shipped aim files changed the hash"
	if read.sim.look_aim.values_hash() != LookAim.new().values_hash() \
			or read.sim.aim_assist.cone_degrees != AimAssist.new().cone_degrees:
		return "the shipped files no longer hold the defaults"
	return ""
