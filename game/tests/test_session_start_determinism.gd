extends RefCounted

## The same session must start the same way on every machine (ARC-1, ARC-2,
## MP-2, #381): the 90-tick G2 flight of the #340 devlog hashed differently in
## a Builder's sandbox and on CI, which in co-op would be a desync.

const FLIGHT_TICKS: int = 90
const G2_FILE: String = "res://data/levels/g2_level.json"
const WEAPON_DIR: String = "res://data/weapons/"
## The #340 flight's hash, measured locally on Godot 4.7.2 and pinned so CI
## checks it on a second machine.
const G2_FLIGHT_HASH: int = 818969652


## The #340 devlog's input: forward thrust with a slow yaw and pitch.
class FlySource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i(150, 250, 0))


func _g2() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE))


## What a failing run prints, so two machines can be compared piece by piece.
func _breakdown(session: LocalSession, trail: PackedStringArray) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("listing %s" % DirAccess.get_files_at(WEAPON_DIR))
	for id: String in session.sim.part_ids():
		lines.append("part %s %d" % [id, session.sim.part(id).values_hash()])
	for robot: RobotState in session.sim.robots:
		lines.append("robot %d" % robot.state_hash())
	lines.append_array(trail)
	return "; ".join(lines)


func test_g2_flight_hashes_to_the_pinned_value() -> String:
	var session: LocalSession = LocalSession.for_level(_g2(), 340, FlySource.new())
	var trail: PackedStringArray = PackedStringArray()
	trail.append("tick 0 %d ship %d" % [session.sim.state_hash(),
		session.sim.ships[0].state_hash()])
	for i: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
		if session.sim.tick % 15 == 0:
			trail.append("tick %d %d ship %d" % [session.sim.tick, session.sim.state_hash(),
				session.sim.ships[0].state_hash()])
	if session.sim.tick != FLIGHT_TICKS:
		return "the session ran %d ticks" % session.sim.tick
	if session.sim.state_hash() != G2_FLIGHT_HASH:
		return "G2 flew to %d, pinned %d (%s)" % [session.sim.state_hash(), G2_FLIGHT_HASH,
			_breakdown(session, trail)]
	return ""


## Flies the #340 input for 90 ticks in open space with `parts` as the catalogue.
func _fly_parts(parts: Dictionary[String, WeaponDef]) -> int:
	var session: LocalSession = LocalSession.new(381, FlySource.new(), null, null, [], null, parts)
	for i: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
	return session.sim.state_hash()


func test_listing_order_does_not_change_the_catalogue() -> String:
	var names: PackedStringArray = DirAccess.get_files_at(WEAPON_DIR)
	if names.size() < 2:
		return "only %d weapon files to reorder" % names.size()
	var reversed: PackedStringArray = names.duplicate()
	reversed.reverse()
	var forward: Dictionary[String, WeaponDef] = SpawnLoader.parts_from_files(WEAPON_DIR, names)
	var backward: Dictionary[String, WeaponDef] = SpawnLoader.parts_from_files(WEAPON_DIR, reversed)
	if forward.keys() != backward.keys():
		return "the catalogue's order follows the listing: %s and %s" % [forward.keys(),
			backward.keys()]
	var sorted_keys: Array = forward.keys().duplicate()
	sorted_keys.sort()
	if forward.keys() != sorted_keys:
		return "the catalogue is not in id order: %s" % forward.keys()
	for id: String in forward:
		if forward[id].values_hash() != backward[id].values_hash():
			return "part %s differs between the two orders" % id
	var hashes: Array[int] = [_fly_parts(forward), _fly_parts(backward)]
	if hashes[0] != hashes[1]:
		return "the two orders fly to %d and %d" % [hashes[0], hashes[1]]
	return ""


func test_load_parts_reads_the_whole_folder() -> String:
	var loaded: Dictionary[String, WeaponDef] = SpawnLoader.load_parts(WEAPON_DIR)
	var names: PackedStringArray = DirAccess.get_files_at(WEAPON_DIR)
	var built: Dictionary[String, WeaponDef] = SpawnLoader.parts_from_files(WEAPON_DIR, names)
	if loaded.keys() != built.keys():
		return "load_parts gave %s, the listing %s" % [loaded.keys(), built.keys()]
	if loaded.is_empty():
		return "no parts loaded"
	return ""
