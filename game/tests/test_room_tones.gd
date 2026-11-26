extends RefCounted

## The room tones node and its wiring (#1399, AUD-1, ARC-1, MP-2): headless
## with audio disabled it plays nothing while the mix is followed; a rejected
## table stays silent; the wiring plays the G2 level's first space in flight,
## the hangar at the base, starts a new level from silence, and following the
## tones leaves the simulation's hash as it was.

const G2: String = "res://data/levels/g2_level.json"


static func _g2_session() -> LocalSession:
	return LocalSession.for_level(LevelSwitch.load_level(G2), 0, null,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))


func test_headless_plays_nothing_and_follows_the_mix() -> String:
	var tones: RoomTones = RoomTones.new()
	var result: String = ""
	if tones.enabled != SoundCues.audio_available():
		result = "enabled is %s under the %s driver" % [tones.enabled, AudioServer.get_driver_name()]
	tones.enabled = false  # As headless; on a machine with sound too.
	var heard: Array[String] = tones.follow(MusicMix.Mood.HUB, null, Vector3.ZERO, null, 2.0)
	if result == "" and str(heard) != str([RoomToneTable.HANGAR]):
		result = "the mix gave %s" % [heard]
	if result == "" and (tones.playing_count() != 0 or tones.get_child_count() != 0):
		result = "%d players made" % tones.get_child_count()
	tones.free()
	return result


func test_rejected_table_plays_nothing() -> String:
	var tones: RoomTones = RoomTones.new(RoomToneTable.parse("{}"))
	var heard: Array[String] = tones.follow(MusicMix.Mood.HUB, null, Vector3.ZERO, null, 2.0)
	tones.free()
	return "" if heard.is_empty() else "a rejected table sounds %s" % [heard]


func test_wiring_plays_the_space_then_the_hangar_and_reads_only() -> String:
	var flown: LocalSession = _g2_session()
	var plain: LocalSession = _g2_session()
	var world: Node3D = Node3D.new()
	var wiring: MusicWiring = MusicWiring.new()
	wiring.attach(world)
	var result: String = "" if wiring.room_tones != null and wiring.room_tones.get_parent() == world \
		else "the room tones are not under the world"
	wiring.room_tones.enabled = false
	wiring.engine.enabled = false
	wiring.player.enabled = false
	var start: String = wiring.room_tones.table.space_at(flown.sim.walls, flown.current_ship().position)
	for frame: int in 90:
		flown.advance(ShipState.TICK_DT)
		plain.advance(ShipState.TICK_DT)
		wiring.update(flown, false, ShipState.TICK_DT)
	if result == "" and (start == "" or wiring.room_tones.mix.gains.get(start, 0.0) != 1.0):
		result = "the start box's tone %s is not full: %s" % [start, wiring.room_tones.mix.gains]
	for frame: int in 90:
		flown.advance(ShipState.TICK_DT)
		plain.advance(ShipState.TICK_DT)
		wiring.update(flown, true, ShipState.TICK_DT)
	if result == "" and str(wiring.room_tones.mix.sounding()) != str([RoomToneTable.HANGAR]):
		result = "at the base heard %s" % [wiring.room_tones.mix.sounding()]
	if result == "" and flown.sim.state_hash() != plain.sim.state_hash():
		result = "the hash moved with the room tones followed"
	world.free()
	return result


func test_new_level_starts_the_tones_from_silence() -> String:
	var session: LocalSession = _g2_session()
	var world: Node3D = Node3D.new()
	var wiring: MusicWiring = MusicWiring.new()
	wiring.attach(world)
	wiring.room_tones.enabled = false
	for frame: int in 90:
		session.advance(ShipState.TICK_DT)
		wiring.update(session, false, ShipState.TICK_DT)
	var next: LocalSession = _g2_session()
	next.advance(ShipState.TICK_DT)
	wiring.update(next, false, 0.0)
	var result: String = "" if wiring.room_tones.mix.sounding().is_empty() \
		else "a new level kept %s" % [wiring.room_tones.mix.sounding()]
	world.free()
	return result
