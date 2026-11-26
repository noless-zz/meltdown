extends RefCounted

## The music player and its wiring (#1303, AUD-3, ARC-1, MP-2): headless with
## audio disabled it plays nothing and does not fail, while the mix is still
## followed; the mood comes from the session (hub, flight, meltdown, end); and
## following the music leaves the simulation's hash as it was.

const G2: String = "res://data/levels/g2_level.json"


static func _g2_session() -> LocalSession:
	return LocalSession.for_level(LevelSwitch.load_level(G2), 0, null,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))


func test_headless_plays_nothing_and_follows_the_mix() -> String:
	var player: MusicPlayer = MusicPlayer.new()
	var result: String = ""
	if player.enabled != SoundCues.audio_available():
		result = "enabled is %s under the %s driver" % [player.enabled, AudioServer.get_driver_name()]
	player.enabled = false  # As headless; on a machine with sound too.
	var sounding: Array[String] = player.follow(MusicMix.Mood.RUN, 0.0, 10.0)
	if result == "" and str(sounding) != str(["calm"]):
		result = "the mix gave %s" % [sounding]
	if result == "" and (player.playing_count() != 0 or player.get_child_count() != 0):
		result = "%d players made" % player.get_child_count()
	player.free()
	return result


func test_rejected_table_plays_nothing() -> String:
	var table: MusicTable = MusicTable.parse("{}")
	var player: MusicPlayer = MusicPlayer.new(table)
	var sounding: Array[String] = player.follow(MusicMix.Mood.RUN, 1.0, 5.0)
	player.free()
	return "" if sounding.is_empty() else "a rejected table sounds %s" % [sounding]


func test_mood_follows_the_session() -> String:
	var session: LocalSession = _g2_session()
	if MusicWiring.mood(session, true) != MusicMix.Mood.HUB:
		return "the hub is not the hub mood"
	if MusicWiring.mood(session, false) != MusicMix.Mood.RUN:
		return "a fresh level is not a flight"
	session.sim.reactor.destroyed = true
	session.sim.reactor.meltdown_ticks_left = 30 * ReactorState.TICKS_PER_SECOND
	if MusicWiring.mood(session, false) != MusicMix.Mood.MELTDOWN:
		return "a destroyed reactor is not the meltdown"
	session.sim.ships[0].escaped = true
	if MusicWiring.mood(session, false) != MusicMix.Mood.ENDED:
		return "an escape is not the end"
	return "" if MusicWiring.alarm_level(session) == 0.0 else "an alarm on a level flown without one"


func test_destroyed_ship_and_no_reactor() -> String:
	if MusicWiring.mood_of(ExitRule.Outcome.LOST, null) != MusicMix.Mood.ENDED:
		return "a lost ship is not the end"
	if MusicWiring.mood_of(ExitRule.Outcome.RUNNING, null) != MusicMix.Mood.RUN:
		return "a level with no reactor is not a flight"
	var reactor: ReactorState = ReactorState.new()
	return "" if MusicWiring.mood_of(ExitRule.Outcome.RUNNING, reactor) == MusicMix.Mood.RUN \
		else "a live reactor is not a flight"


func test_wiring_reads_only() -> String:
	var flown: LocalSession = _g2_session()
	var plain: LocalSession = _g2_session()
	var world: Node3D = Node3D.new()
	var wiring: MusicWiring = MusicWiring.new()
	wiring.attach(world)
	wiring.attach(world)
	# The music player, the pilot's engine (#1398) and the room tones (#1399).
	var result: String = "" if world.get_child_count() == 3 else "%d children" % world.get_child_count()
	for frame: int in 120:
		flown.advance(ShipState.TICK_DT)
		plain.advance(ShipState.TICK_DT)
		wiring.update(flown, frame >= 100, ShipState.TICK_DT)
	if result == "" and flown.sim.state_hash() != plain.sim.state_hash():
		result = "the hash moved with the music followed"
	if result == "" and wiring.player.mix.mood != MusicMix.Mood.HUB:
		result = "the hub was not followed"
	world.free()
	return result
