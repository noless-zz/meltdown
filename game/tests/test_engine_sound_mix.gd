extends RefCounted

## The engine's levels (#1398, AUD-1, MP-2): thrust is read back from two ship
## copies one tick apart, the thrust layer's volume and pitch rise with thrust
## and speed, a ship at rest hears only the idle, and the engine fades in while
## flying and out when not.


static func _table() -> EngineSoundTable:
	return EngineSoundTable.load_file()


## A ship that has flown `ticks` ticks from rest with `thrust` along its nose,
## and its copy from the tick before.
static func _flown(thrust: float, ticks: int, afterburner: bool = false) -> Array[ShipState]:
	var ship: ShipState = ShipState.new()
	var before: ShipState = SessionSnapshots.ship(ship)
	for tick: int in ticks:
		before = SessionSnapshots.ship(ship)
		ship.step(Vector3(0.0, 0.0, -thrust), Vector3.ZERO, afterburner)
	return [before, SessionSnapshots.ship(ship)]


func test_thrust_is_read_back_from_two_ticks() -> String:
	for thrust: float in [0.0, 0.25, 0.5, 1.0]:
		var pair: Array[ShipState] = _flown(thrust, 20)
		var read: float = EngineSoundMix.thrust_of(pair[0], pair[1])
		if absf(read - thrust) > 0.01:
			return "thrust %.2f read back as %.3f" % [thrust, read]
	return ""


func test_thrust_at_top_speed_and_coasting() -> String:
	var held: Array[ShipState] = _flown(1.0, 600)
	if absf(EngineSoundMix.thrust_of(held[0], held[1]) - 1.0) > 0.01:
		return "full thrust held at top speed read as %.3f" % EngineSoundMix.thrust_of(held[0], held[1])
	var ship: ShipState = held[1]
	var before: ShipState = SessionSnapshots.ship(ship)
	ship.step(Vector3.ZERO, Vector3.ZERO)
	var coasting: float = EngineSoundMix.thrust_of(before, ship)
	return "" if coasting < 0.01 else "coasting read as %.3f thrust" % coasting


func test_afterburner_wreck_and_first_tick() -> String:
	var boosted: Array[ShipState] = _flown(1.0, 5, true)
	if EngineSoundMix.thrust_of(boosted[0], boosted[1]) != 1.0:
		return "the afterburner is not full thrust"
	var wreck: ShipState = ShipState.new()
	wreck.hull = 0.0
	wreck.velocity = Vector3(0.0, 0.0, -10.0)
	if EngineSoundMix.thrust_of(ShipState.new(), wreck) != 0.0:
		return "a wreck pushes"
	if EngineSoundMix.thrust_of(null, boosted[1]) != 1.0 or EngineSoundMix.thrust_of(null, ShipState.new()) != 0.0:
		return "with no tick before, only the afterburner counts"
	return "" if EngineSoundMix.thrust_of(null, null) == 0.0 else "no ship pushes"


func test_speed_is_a_share_of_boost_speed() -> String:
	var ship: ShipState = ShipState.new()
	ship.velocity = Vector3(0.0, 0.0, -ship.afterburner_max_speed / 2.0)
	if absf(EngineSoundMix.speed_of(ship) - 0.5) > 0.0001:
		return "half boost speed read as %.3f" % EngineSoundMix.speed_of(ship)
	ship.velocity = Vector3(0.0, 0.0, -1000.0)
	return "" if EngineSoundMix.speed_of(ship) == 1.0 and EngineSoundMix.speed_of(null) == 0.0 \
		else "speed is not held to 0..1"


func test_silent_when_stopped() -> String:
	var mix: EngineSoundMix = EngineSoundMix.new(_table())
	var pair: Array[ShipState] = _flown(0.0, 10)
	for frame: int in 120:
		mix.advance(true, EngineSoundMix.thrust_of(pair[0], pair[1]), EngineSoundMix.speed_of(pair[1]),
			ShipState.TICK_DT)
	if not mix.sounding() or mix.idle_db() != _table().idle_db:
		return "the idle is not at full in flight (%.1f dB)" % mix.idle_db()
	if mix.thrust_sounding():
		return "a ship at rest hears its thrust layer (drive %.4f)" % mix.drive
	for frame: int in 120:
		mix.advance(false, 1.0, 1.0, ShipState.TICK_DT)
	if mix.sounding() or mix.thrust_sounding():
		return "the engine still sounds once not flying"
	return "" if mix.idle_db() == EngineSoundMix.SILENT_DB else "a stopped engine is at %.1f dB" % mix.idle_db()


func test_volume_and_pitch_follow_thrust_and_speed() -> String:
	var table: EngineSoundTable = _table()
	var mix: EngineSoundMix = EngineSoundMix.new(table)
	var last_db: float = -INF
	var last_pitch: float = 0.0
	for level: float in [0.1, 0.4, 0.7, 1.0]:
		for frame: int in 120:
			mix.advance(true, level, level, ShipState.TICK_DT)
		if mix.thrust_db() <= last_db or mix.thrust_pitch() <= last_pitch:
			return "at %.1f the thrust layer is %.1f dB, pitch %.2f; not above %.1f dB, %.2f" \
				% [level, mix.thrust_db(), mix.thrust_pitch(), last_db, last_pitch]
		last_db = mix.thrust_db()
		last_pitch = mix.thrust_pitch()
	if absf(last_db - table.thrust_max_db) > 0.01 or absf(last_pitch - table.thrust_pitch_max) > 0.001:
		return "full drive gives %.1f dB, pitch %.2f" % [last_db, last_pitch]
	var thrust_only: float = mix.drive_for(1.0, 0.0)
	var speed_only: float = mix.drive_for(0.0, 1.0)
	if absf(thrust_only - table.thrust_weight) > 0.0001 or absf(speed_only - (1.0 - table.thrust_weight)) > 0.0001:
		return "thrust alone drives %.2f, speed alone %.2f" % [thrust_only, speed_only]
	return ""


func test_drive_is_smoothed_and_gain_fades() -> String:
	var table: EngineSoundTable = _table()
	var mix: EngineSoundMix = EngineSoundMix.new(table)
	mix.advance(true, 1.0, 1.0, ShipState.TICK_DT)
	if mix.drive <= 0.0 or mix.drive >= 0.5:
		return "one frame of full thrust jumped the drive to %.3f" % mix.drive
	if absf(mix.gain - ShipState.TICK_DT / table.fade_seconds) > 0.0001:
		return "one frame faded the engine to %.3f" % mix.gain
	mix.advance(true, 1.0, 1.0, table.fade_seconds)
	if mix.gain != 1.0 or mix.drive != 1.0:
		return "after the fade time gain is %.3f, drive %.3f" % [mix.gain, mix.drive]
	mix.advance(true, 1.0, 1.0, -5.0)
	return "" if mix.gain == 1.0 else "a negative frame time moved the gain"
