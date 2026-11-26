extends RefCounted

## The pilot's engine as a node and as wired (#1398, AUD-1, ARC-1, MP-2):
## headless it plays nothing yet follows the mix; it sits at the ship's pose
## with its players below and behind the seat on the effects bus; the
## afterburner starts a burst; it goes quiet at the base and on end screens;
## and following it leaves the simulation's hash as it was.

const G2: String = "res://data/levels/g2_level.json"


static func _g2_session() -> LocalSession:
	return LocalSession.for_level(LevelSwitch.load_level(G2), 0, null,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))


func test_headless_plays_nothing_and_follows_the_mix() -> String:
	var engine: EngineSound = EngineSound.new()
	var result: String = ""
	if engine.enabled != SoundCues.audio_available():
		result = "enabled is %s under the %s driver" % [engine.enabled, AudioServer.get_driver_name()]
	engine.enabled = false  # As headless; on a machine with sound too.
	var ship: ShipState = ShipState.new()
	var none: Array[SimEvent] = []
	for frame: int in 60:
		engine.follow(ship, ship, Transform3D.IDENTITY, none, true, ShipState.TICK_DT)
	if result == "" and (not engine.mix.sounding() or engine.mix.gain != 1.0):
		result = "the mix did not fade in (gain %.2f)" % engine.mix.gain
	if result == "" and engine.playing_count() != 0:
		result = "%d players sound while disabled" % engine.playing_count()
	engine.free()
	return result


func test_players_sit_behind_the_seat_on_the_effects_bus() -> String:
	var reverb: RoomReverb = RoomReverb.new()
	reverb.ensure_bus()  # As `CombatWiring.attach` does before the music and engine.
	reverb.free()
	var engine: EngineSound = EngineSound.new()
	engine.enabled = false
	var result: String = ""
	for which: String in ["idle", "thrust", "burst"]:
		var player: AudioStreamPlayer3D = engine.player(which)
		if player == null or player.stream == null:
			result = "the %s player has no sound" % which
		elif player.bus != RoomReverb.BUS or player.position != engine.table.offset:
			result = "the %s player is on %s at %s" % [which, player.bus, player.position]
		elif player.attenuation_model != AudioStreamPlayer3D.ATTENUATION_DISABLED:
			result = "the %s player fades with distance from its own pilot" % which
		if result != "":
			break
	var pose: Transform3D = Transform3D(Basis(Vector3.UP, 1.0), Vector3(3.0, 4.0, 5.0))
	var none: Array[SimEvent] = []
	engine.follow(ShipState.new(), ShipState.new(), pose, none, true, ShipState.TICK_DT)
	if result == "" and engine.transform != pose:
		result = "the engine is not at the ship's pose"
	engine.free()
	return result


func test_afterburner_starts_a_burst_only_in_flight() -> String:
	var engine: EngineSound = EngineSound.new()
	engine.enabled = false
	var ship: ShipState = ShipState.new()
	var boost: Array[SimEvent] = [SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, 0)]
	var other: Array[SimEvent] = [SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED, 1),
		SimEvent.new(SimEvent.Kind.AFTERBURNER_STOPPED, 0)]
	engine.follow(ship, ship, Transform3D.IDENTITY, boost, true, ShipState.TICK_DT)
	engine.follow(ship, ship, Transform3D.IDENTITY, other, true, ShipState.TICK_DT)
	engine.follow(ship, ship, Transform3D.IDENTITY, boost, false, ShipState.TICK_DT)
	var bursts: int = engine.bursts
	engine.free()
	return "" if bursts == 1 else "%d bursts; expected 1, from the local ship in flight" % bursts


func test_rejected_table_stays_silent() -> String:
	var engine: EngineSound = EngineSound.new(EngineSoundTable.parse("{}"))
	engine.enabled = false
	var ship: ShipState = ShipState.new()
	var none: Array[SimEvent] = []
	for frame: int in 60:
		engine.follow(ship, ship, Transform3D.IDENTITY, none, true, ShipState.TICK_DT)
	var sounding: bool = engine.mix.sounding()
	engine.free()
	return "" if not sounding else "a rejected table sounds"


func test_wiring_follows_flight_and_base_and_reads_only() -> String:
	var flown: LocalSession = _g2_session()
	var plain: LocalSession = _g2_session()
	var world: Node3D = Node3D.new()
	var wiring: MusicWiring = MusicWiring.new()
	wiring.attach(world)
	var result: String = "" if wiring.engine != null and wiring.engine.get_parent() == world \
		else "the engine is not under the world"
	wiring.engine.enabled = false
	for frame: int in 60:
		flown.advance(ShipState.TICK_DT)
		plain.advance(ShipState.TICK_DT)
		wiring.update(flown, false, ShipState.TICK_DT)
	if result == "" and not wiring.engine.mix.sounding():
		result = "the engine is silent in flight"
	for frame: int in 60:
		flown.advance(ShipState.TICK_DT)
		plain.advance(ShipState.TICK_DT)
		wiring.update(flown, true, ShipState.TICK_DT)
	if result == "" and wiring.engine.mix.sounding():
		result = "the engine still sounds at the base"
	if result == "" and flown.sim.state_hash() != plain.sim.state_hash():
		result = "the hash moved with the engine followed"
	world.free()
	return result


func test_engine_stops_on_end_screens_and_restarts_on_a_new_level() -> String:
	var session: LocalSession = _g2_session()
	var world: Node3D = Node3D.new()
	var wiring: MusicWiring = MusicWiring.new()
	wiring.attach(world)
	wiring.engine.enabled = false
	for frame: int in 60:
		session.advance(ShipState.TICK_DT)
		wiring.update(session, false, ShipState.TICK_DT)
	session.sim.ships[0].escaped = true
	for frame: int in 60:
		wiring.update(session, false, ShipState.TICK_DT)
	var result: String = "" if not wiring.engine.mix.sounding() else "the engine sounds on the end screen"
	var next: LocalSession = _g2_session()
	next.advance(ShipState.TICK_DT)
	wiring.engine.mix.gain = 1.0
	wiring.update(next, false, 0.0)
	if result == "" and wiring.engine.mix.gain != 0.0:
		result = "a new level did not start the engine from silence"
	world.free()
	return result
