extends RefCounted

## The main scene's session carries a part catalogue built from the weapon data
## files, so a held part can be slotted in the headset (#320, SLV-1, CMB-1,
## ARC-4), and its replay records the catalogue and flies to the same hash
## (ARC-2, #267).

const WEAPON_DIR: String = "res://data/weapons/"
const WEAPON_IDS: Array[String] = ["arc_lance", "needle_gun", "pulse_cannon", "slug_thrower"]
const G2_FILE: String = "res://data/levels/g2_level.json"
const SCRATCH_DIR: String = "user://test_session_parts"
const FLIGHT_TICKS: int = 60


## Full forward thrust with a slow yaw and the primary held on every tick.
class FlySource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		var input: ShipInput = ShipInput.new(Vector3i(0, 0, -1000), Vector3i(0, 250, 0))
		input.fire_primary = true
		return input


func _main() -> Node:
	return (load("res://main.tscn") as PackedScene).instantiate()


func _write(dir: String, file_name: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_load_parts_reads_every_weapon_file_by_its_id() -> String:
	var parts: Dictionary[String, WeaponDef] = LocalSession.load_parts()
	var ids: Array[String] = []
	ids.assign(parts.keys())
	ids.sort()
	if ids != WEAPON_IDS:
		return "the catalogue holds %s, expected %s" % [ids, WEAPON_IDS]
	for id: String in WEAPON_IDS:
		var from_file: WeaponDef = WeaponDef.parse_json(
			FileAccess.get_file_as_string(WEAPON_DIR.path_join(id + ".json")))
		if parts[id].damage != from_file.damage \
				or parts[id].fire_interval_ticks != from_file.fire_interval_ticks:
			return "part %s does not match its data file" % id
	return ""


func test_load_parts_leaves_out_rejected_files_only() -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	_write(SCRATCH_DIR, "good_gun.json", FileAccess.get_file_as_string(WEAPON_DIR + "needle_gun.json"))
	_write(SCRATCH_DIR, "broken_gun.json", "{\"damage\": ")
	_write(SCRATCH_DIR, "Bad-Name.json", FileAccess.get_file_as_string(WEAPON_DIR + "needle_gun.json"))
	_write(SCRATCH_DIR, "notes.txt", "not a weapon")
	var parts: Dictionary[String, WeaponDef] = LocalSession.load_parts(SCRATCH_DIR)
	var ids: Array[String] = []
	ids.assign(parts.keys())
	if ids != ["good_gun"]:
		return "the catalogue holds %s, expected only good_gun" % [ids]
	return ""


func test_a_session_without_parts_has_no_catalogue() -> String:
	var session: LocalSession = LocalSession.new(1, FlySource.new())
	if not session.sim.part_ids().is_empty():
		return "a plain session has parts %s" % [session.sim.part_ids()]
	if not session.replay.parts.is_empty():
		return "a plain session's replay has parts"
	if session.replay.to_text().contains("\npart "):
		return "a plain session's replay text has part lines"
	return ""


func test_the_catalogue_is_set_before_the_first_tick_and_recorded() -> String:
	var session: LocalSession = LocalSession.new(1, FlySource.new(), null, null, [], null,
		LocalSession.load_parts())
	if session.sim.tick != 0:
		return "the session ticked before the catalogue was set"
	if session.sim.part_ids() != WEAPON_IDS:
		return "the simulation's catalogue is %s" % [session.sim.part_ids()]
	var recorded: Array[String] = []
	recorded.assign(session.replay.parts.keys())
	recorded.sort()
	if recorded != WEAPON_IDS:
		return "the replay records parts %s" % [recorded]
	return ""


func test_a_session_with_parts_replays_to_its_hash() -> String:
	var session: LocalSession = LocalSession.new(3, FlySource.new(), null, null, [], null,
		LocalSession.load_parts())
	for frame: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
	var replay: Replay = Replay.from_text(session.replay.to_text())
	if replay.error != "":
		return "saved replay does not read back: %s" % replay.error
	if replay.parts.size() != WEAPON_IDS.size():
		return "the read-back replay has %d parts" % replay.parts.size()
	var sim: Sim = replay.run()
	if sim == null:
		return "replay did not run: %s" % replay.run_error
	if sim.state_hash() != session.sim.state_hash():
		return "replay ends on %d, the session on %d" % [sim.state_hash(), session.sim.state_hash()]
	# The catalogue is part of the hash, so a run without it must differ;
	# otherwise this test would pass with the catalogue dropped.
	replay.parts = {}
	if replay.run().state_hash() == session.sim.state_hash():
		return "the hash does not depend on the catalogue"
	return ""


func test_a_level_session_has_the_catalogue() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE))
	var session: LocalSession = LocalSession.for_level(level)
	if session.sim.part_ids() != WEAPON_IDS:
		return "the level session's catalogue is %s" % [session.sim.part_ids()]
	if session.replay.parts.size() != WEAPON_IDS.size():
		return "the level session's replay records %d parts" % session.replay.parts.size()
	return ""


func test_the_main_scene_sessions_have_the_catalogue() -> String:
	var main: Node = _main()
	var tunnel: LocalSession = main.get("session")
	var tunnel_ids: Array[String] = tunnel.sim.part_ids()
	main.call("use_level", G2_FILE)
	var level: LocalSession = main.get("session")
	var level_ids: Array[String] = level.sim.part_ids()
	main.free()
	if tunnel_ids != WEAPON_IDS:
		return "the tunnel session's catalogue is %s" % [tunnel_ids]
	if level_ids != WEAPON_IDS:
		return "the level session's catalogue is %s" % [level_ids]
	return ""
