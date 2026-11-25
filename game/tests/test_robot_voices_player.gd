extends RefCounted

## The robot voice player (#1363, AUD-2): a loop follows its robot, carries on
## while the same robots are heard, goes to the muffled bus behind a wall, and
## stops when its robot is destroyed or the level changes. No audio device is
## needed: the players are set but nothing is played.

const TABLE: String = """{"max_voices": 2, "reference_m": 2, "far_cutoff_hz": 2000,
	"muffle_cutoff_hz": 600, "voices": {
	"drone": {"sound": "res://data/audio/voice_drone.wav", "volume_db": -6, "pitch_min": 1.0,
		"pitch_max": 1.5, "range_m": 30, "muffle_db": -10},
	"hauler": {"sound": "res://data/audio/voice_hauler.wav", "volume_db": -3, "pitch_min": 0.9,
		"pitch_max": 1.1, "range_m": 50, "muffle_db": -8}}}"""


static func _robot(id: String, position: Vector3) -> RobotState:
	var def: RobotDef = RobotDef.new()
	def.id = id
	return RobotState.new(def, position)


static func _robots(list: Array) -> Array[RobotState]:
	var typed: Array[RobotState] = []
	typed.assign(list)
	return typed


static func _voices() -> RobotVoices:
	var voices: RobotVoices = RobotVoices.new(RobotVoiceTable.parse(TABLE))
	voices.enabled = false
	# The buses, as the game makes them; a bus name with no bus reads back as Master.
	var reverb: RoomReverb = RoomReverb.new()
	reverb.ensure_bus()
	reverb.free()
	voices.ensure_bus()
	return voices


func test_loop_follows_its_robot() -> String:
	var voices: RobotVoices = _voices()
	var drone: RobotState = _robot("drone", Vector3(5, 0, 0))
	voices.follow(_robots([drone]), Vector3.ZERO, null)
	var first: AudioStreamPlayer3D = voices.player(0)
	drone.position = Vector3(6, 1, 0)
	voices.follow(_robots([drone]), Vector3.ZERO, null)
	var why: String = ""
	if voices.player_count() != 1 or voices.player(0) != first:
		why = "a moving robot got a new player"
	elif first.position != Vector3(6, 1, 0):
		why = "the loop stayed at %s" % first.position
	elif first.stream == null or first.bus != RobotVoices.BUS:
		why = "the loop has no stream or is off the effects bus"
	voices.free()
	return why


func test_cap_holds_and_nearest_are_sounded() -> String:
	var voices: RobotVoices = _voices()
	var robots: Array[RobotState] = _robots([
		_robot("drone", Vector3(20, 0, 0)), _robot("hauler", Vector3(3, 0, 0)), _robot("drone", Vector3(4, 0, 0)),
	])
	var mixes: Array[RobotVoiceMix] = voices.follow(robots, Vector3.ZERO, null)
	var why: String = ""
	if voices.sounding() != 2 or mixes.size() != 2:
		why = "%d voices sounding; the cap is 2" % voices.sounding()
	elif mixes[0].robot_index != 1 or mixes[1].robot_index != 2:
		why = "the nearest were not chosen"
	voices.free()
	return why


func test_muffled_voice_goes_to_the_muffled_bus_quieter() -> String:
	var voices: RobotVoices = _voices()
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-10, -10, -10), Vector3(10, 10, 10)),
		BoxBounds.new(Vector3(8, -2, -2), Vector3(40, 2, 2))]
	var walls: BoxUnion = BoxUnion.new(boxes)
	voices.follow(_robots([_robot("drone", Vector3(25, 0, 0))]), Vector3(0, 8, 0), walls)
	var player: AudioStreamPlayer3D = voices.player(0)
	var why: String = ""
	if player.bus != RobotVoices.MUFFLED_BUS or not is_equal_approx(player.volume_db, -16.0):
		why = "behind a wall: bus %s at %.1f dB" % [player.bus, player.volume_db]
	voices.follow(_robots([_robot("drone", Vector3(5, 0, 0))]), Vector3(0, 8, 0), walls)
	if why == "" and (player.bus != RobotVoices.BUS or not is_equal_approx(player.volume_db, -6.0)):
		why = "in the open: bus %s at %.1f dB" % [player.bus, player.volume_db]
	voices.free()
	return why


func test_voice_stops_when_its_robot_is_destroyed() -> String:
	var voices: RobotVoices = _voices()
	var drone: RobotState = _robot("drone", Vector3(5, 0, 0))
	var hauler: RobotState = _robot("hauler", Vector3(8, 0, 0))
	voices.follow(_robots([drone, hauler]), Vector3.ZERO, null)
	drone.hull = 0.0  # Destroyed this tick: still listed until the tick ends.
	voices.follow(_robots([drone, hauler]), Vector3.ZERO, null)
	var why: String = ""
	if voices.sounding() != 1:
		why = "%d voices with the drone destroyed" % voices.sounding()
	voices.follow(_robots([hauler]), Vector3.ZERO, null)
	if why == "" and (voices.sounding() != 1 or voices.last_mix[0].type_id != "hauler"):
		why = "the hauler's voice did not carry on"
	voices.follow(_robots([]), Vector3.ZERO, null)
	if why == "" and voices.sounding() != 0:
		why = "voices left with no robots"
	voices.free()
	return why


func test_reset_stops_every_voice() -> String:
	var voices: RobotVoices = _voices()
	voices.follow(_robots([_robot("drone", Vector3(5, 0, 0)), _robot("hauler", Vector3(6, 0, 0))]), Vector3.ZERO, null)
	voices.reset()
	var why: String = "" if voices.sounding() == 0 and voices.last_mix.is_empty() else "voices left after reset"
	voices.free()
	return why


func test_shipped_table_is_used() -> String:
	var voices: RobotVoices = RobotVoices.new()
	var ok: bool = voices.table.error == "" and voices.table.voices.size() >= 6
	voices.free()
	return "" if ok else "the shipped table was not loaded"
