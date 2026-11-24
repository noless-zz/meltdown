extends RefCounted

## The room reverb node (#1291, AUD-1): it makes the effects bus with a
## reverb once, sets the reverb from the room the ship is in, blends by
## simulation ticks, and the cues play on that bus. The combat wiring adds it
## beside the cues.


static func _walls() -> BoxUnion:
	return BoxUnion.new([
		BoxBounds.new(Vector3(-5, -5, -30), Vector3(5, 5, 0)),
		BoxBounds.new(Vector3(-12, -12, -52), Vector3(12, 12, -28)),
	] as Array[BoxBounds])


func test_bus_is_made_once_with_one_reverb() -> String:
	var reverb: RoomReverb = RoomReverb.new()
	var index: int = reverb.ensure_bus()
	var again: int = RoomReverb.new().ensure_bus()
	var result: String = ""
	if index < 0 or index != again:
		result = "bus %d then %d" % [index, again]
	elif AudioServer.get_bus_effect_count(index) != 1:
		result = "%d effects on the bus" % AudioServer.get_bus_effect_count(index)
	elif AudioServer.get_bus_send(index) != RoomReverb.SEND_TO:
		result = "the bus sends to %s" % AudioServer.get_bus_send(index)
	elif reverb.effect == null:
		result = "no effect kept"
	reverb.free()
	return result


func test_follow_sets_the_effect_and_blends_by_ticks() -> String:
	var reverb: RoomReverb = RoomReverb.new()
	reverb.ensure_bus()
	var table: RoomReverbTable = reverb.table
	var tunnel: ReverbSetting = table.setting_at(_walls(), Vector3(0, 0, -10))
	var room: ReverbSetting = table.setting_at(_walls(), Vector3(0, 0, -40))
	var result: String = ""
	reverb.follow(_walls(), Vector3(0, 0, -10), 100)
	if not is_equal_approx(reverb.effect.room_size, tunnel.room_size):
		result = "the tunnel set room_size %f" % reverb.effect.room_size
	var heard: ReverbSetting = reverb.follow(_walls(), Vector3(0, 0, -40), 101)
	if result == "" and (heard.same_as(room) or heard.same_as(tunnel)):
		result = "one tick into the room heard %s" % heard
	var ticks: int = ceili(table.blend_seconds * ShipState.TICK_RATE)
	heard = reverb.follow(_walls(), Vector3(0, 0, -40), 101 + ticks)
	if result == "" and not heard.same_as(room):
		result = "after the blend heard %s, not %s" % [heard, room]
	if result == "" and not is_equal_approx(reverb.effect.wet, room.wet):
		result = "the effect's wet is %f" % reverb.effect.wet
	reverb.free()
	return result


func test_reset_hears_the_new_level_at_once() -> String:
	var reverb: RoomReverb = RoomReverb.new()
	reverb.follow(_walls(), Vector3(0, 0, -10), 500)
	reverb.reset()
	var heard: ReverbSetting = reverb.follow(_walls(), Vector3(0, 0, -40), 0)
	var room: ReverbSetting = reverb.table.setting_at(_walls(), Vector3(0, 0, -40))
	reverb.free()
	return "" if heard.same_as(room) else "the new level started on %s" % heard


func test_cues_play_on_the_reverb_bus() -> String:
	return "" if SoundCues.AUDIO_BUS == RoomReverb.BUS else "cues play on %s" % SoundCues.AUDIO_BUS


func test_combat_wiring_adds_it_beside_the_cues() -> String:
	var world: Node3D = Node3D.new()
	var wiring: CombatWiring = CombatWiring.new()
	wiring.attach(world)
	var found: Node = world.get_node_or_null("RoomReverb")
	var result: String = ""
	if found == null or found != wiring.room_reverb:
		result = "no RoomReverb under the world"
	elif wiring.room_reverb.effect == null:
		result = "the bus was not made"
	world.free()
	return result
