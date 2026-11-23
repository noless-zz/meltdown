extends RefCounted

## The cue player (#1290, AUD-1, ARC-1): headless, with the dummy audio
## driver, it plays nothing and does not fail; with sound on, each cue gets a
## positional source at its place and the pool never outgrows the cap. The
## combat wiring puts it in the world beside the bolts.


static func _ship() -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.primary_ids = ["pulse_cannon", ""]
	return ship


static func _fight() -> Array[SimEvent]:
	return [
		SimEvent.new(SimEvent.Kind.SHIP_HIT, 0, 5.0, Vector3.BACK),
		SimEvent.new(SimEvent.Kind.ROBOT_DESTROYED, 0, 0.0, Vector3.FORWARD),
		SimEvent.new(SimEvent.Kind.AFTERBURNER_STARTED),
	]


func test_headless_run_plays_nothing_and_does_not_fail() -> String:
	if SoundCues.audio_available():
		return ""  # Only meaningful under the dummy driver, as CI runs.
	var player: SoundCues = SoundCues.new()
	var played: Array[String] = player.feed(_fight(), [Projectile.new()], [_ship()] as Array[ShipState])
	var players: int = player.player_count()
	player.free()
	if not played.is_empty():
		return "played %s headless" % [played]
	return "" if players == 0 else "%d players made headless" % players


func test_sound_on_plays_each_cue_at_its_place() -> String:
	var player: SoundCues = SoundCues.new()
	player.enabled = true
	var played: Array[String] = player.feed(_fight(), [], [_ship()] as Array[ShipState])
	var result: String = ""
	if played != ["SHIP_HIT", "ROBOT_DESTROYED"]:
		result = "played %s; afterburner is silent" % [played]
	elif player.player_count() != 2:
		result = "%d players for 2 cues" % player.player_count()
	elif not (player.get_child(0) as AudioStreamPlayer3D).position.is_equal_approx(
			-Vector3.BACK * SoundCueEvents.SHOT_FROM_M):
		result = "the ship hit is at %s" % (player.get_child(0) as AudioStreamPlayer3D).position
	elif (player.get_child(0) as AudioStreamPlayer3D).stream == null:
		result = "no stream on the player"
	player.free()
	return result


func test_pool_never_outgrows_the_cap() -> String:
	var table: SoundCueTable = SoundCueTable.parse(
		'{"max_voices": 3, "cues": {"SHIP_HIT": {"sound": "res://data/audio/ship_hit.wav", '
		+ '"volume_db": 0, "pitch_min": 1, "pitch_max": 1}}}')
	var player: SoundCues = SoundCues.new(table)
	player.enabled = true
	var hits: Array[SimEvent] = []
	for index: int in 10:
		hits.append(SimEvent.new(SimEvent.Kind.SHIP_HIT, 0, 1.0, Vector3.BACK))
	var played: Array[String] = player.feed(hits, [], [_ship()] as Array[ShipState])
	var result: String = ""
	if played.size() != 10:
		result = "played %d of 10" % played.size()
	elif player.player_count() != 3 or player.voices.count() != 3:
		result = "%d players and %d voices for a cap of 3" % [player.player_count(), player.voices.count()]
	player.free()
	return result


func test_combat_wiring_puts_the_player_in_the_world() -> String:
	var world: Node3D = Node3D.new()
	var combat: CombatWiring = CombatWiring.new()
	combat.attach(world)
	var found: bool = combat.sound_cues != null and combat.sound_cues.get_parent() == world
	world.free()
	return "" if found else "no sound cue player under the world"
