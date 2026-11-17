extends RefCounted

## The same session must start the same way on every machine (ARC-1, ARC-2,
## MP-2, #381): the 90-tick G2 flight of the #340 devlog hashed differently in
## a Builder's sandbox and on CI, which in co-op would be a desync.
##
## The start was the same on both, and so was the ship's flight. What differed
## was the robots: `Vector3.angle_to` in `RobotState.turn_towards` returned
## 0.06978795 in the sandbox and 0.06978794 on CI for the same inputs on the
## first tick. Robots now take the angle from `StableAngle` (#381), so the
## whole flight's hash is pinned too.

const FLIGHT_TICKS: int = 90
const G2_FILE: String = "res://data/levels/g2_level.json"
const WEAPON_DIR: String = "res://data/weapons/"
## G2's session before the first tick, and its ship after the #340 flight.
## Both were measured in a Builder's sandbox (Intel Xeon) and on CI with
## Godot 4.7.2 and came out the same, so CI checks them on a second machine.
const G2_START_HASH: int = 4279815811
const G2_SHIP_HASH: int = 2896393452
## The whole simulation after the #340 flight, robots included. CI measured it
## with `angle_to` before #381; with `StableAngle` a Builder's sandbox, whose
## `atan2f` gave the other value, reaches it too.
const G2_FLIGHT_HASH: int = 2263984340
## The three values above are for G2 with its `debris` key taken out. Since
## #439 a session carries the level's debris, which joins the state hash, so G2
## as shipped starts and flies to these instead; only the debris term differs.
const G2_DEBRIS_START_HASH: int = 3715211062
const G2_DEBRIS_FLIGHT_HASH: int = 1112183472


## The #340 devlog's input: forward thrust with a slow yaw and pitch.
class FlySource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i(150, 250, 0))


func _g2() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE))


## G2 without its debris, which the pins from before #439 were taken on.
func _g2_without_debris() -> LevelDef:
	var level: LevelDef = _g2()
	level.debris = null
	return level


func test_g2_session_starts_at_the_pinned_hash() -> String:
	var session: LocalSession = LocalSession.for_level(_g2_without_debris(), 340, FlySource.new())
	if session.sim.state_hash() != G2_START_HASH:
		return "G2's session starts at %d, pinned %d" % [session.sim.state_hash(), G2_START_HASH]
	var with_debris: LocalSession = LocalSession.for_level(_g2(), 340, FlySource.new())
	if with_debris.sim.debris == null:
		return "G2's session has no debris"
	if with_debris.sim.state_hash() != G2_DEBRIS_START_HASH:
		return "G2 with its debris starts at %d, pinned %d" % [with_debris.sim.state_hash(),
			G2_DEBRIS_START_HASH]
	return ""


## The ship alone: its flight uses no robot turn, so it hashed the same on both
## machines even before #381.
func test_g2_flight_ship_hashes_to_the_pinned_value() -> String:
	var session: LocalSession = LocalSession.for_level(_g2(), 340, FlySource.new())
	for i: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
	if session.sim.tick != FLIGHT_TICKS:
		return "the session ran %d ticks" % session.sim.tick
	var ship_hash: int = session.sim.ships[0].state_hash()
	if ship_hash != G2_SHIP_HASH:
		return "G2's ship flew to %d, pinned %d" % [ship_hash, G2_SHIP_HASH]
	return ""


## Robots, projectiles and all: the hash a co-op client and host must agree on.
func test_g2_flight_whole_sim_hashes_to_the_pinned_value() -> String:
	var pins: Array[int] = [G2_FLIGHT_HASH, G2_DEBRIS_FLIGHT_HASH]
	var levels: Array[LevelDef] = [_g2_without_debris(), _g2()]
	for index: int in levels.size():
		var session: LocalSession = LocalSession.for_level(levels[index], 340, FlySource.new())
		if session.sim.robots.is_empty():
			return "G2 has no robots to turn"
		for i: int in FLIGHT_TICKS:
			session.advance(ShipState.TICK_DT)
		var sim_hash: int = session.sim.state_hash()
		if sim_hash != pins[index]:
			return "G2's flight (debris %s) hashed to %d, pinned %d" % [index == 1, sim_hash,
				pins[index]]
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
