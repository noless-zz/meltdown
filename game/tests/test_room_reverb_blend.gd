extends RefCounted

## The reverb blend (#1291, AUD-1): crossing into another room blends over the
## table's time rather than jumping; the first room of a level is heard at once.

const TUNNEL: Array[float] = [0.15, 0.7, 0.12]
const ROOM: Array[float] = [0.75, 0.35, 0.3]


static func _setting(values: Array[float]) -> ReverbSetting:
	return ReverbSetting.new(values[0], values[1], values[2])


func test_first_room_is_heard_at_once() -> String:
	var blend: RoomReverbBlend = RoomReverbBlend.new(1.0)
	var heard: ReverbSetting = blend.advance(_setting(ROOM), 0.0)
	return "" if heard.same_as(_setting(ROOM)) else "started on %s" % heard


func test_crossing_blends_rather_than_jumps() -> String:
	var blend: RoomReverbBlend = RoomReverbBlend.new(0.5)
	blend.advance(_setting(TUNNEL), 0.0)
	var last: ReverbSetting = blend.current
	var widest: float = _setting(TUNNEL).distance_to(_setting(ROOM))
	for tick: int in 30:
		var heard: ReverbSetting = blend.advance(_setting(ROOM), ShipState.TICK_DT)
		var moved: float = heard.distance_to(last)
		if moved > widest / 30.0 + 0.0001:
			return "moved %f in tick %d" % [moved, tick]
		if tick < 29 and heard.same_as(_setting(ROOM)):
			return "arrived at tick %d of 30" % tick
		last = heard
	return "" if last.same_as(_setting(ROOM)) else "after the blend time heard %s" % last


func test_turning_back_midway_blends_from_where_it_is() -> String:
	var blend: RoomReverbBlend = RoomReverbBlend.new(1.0)
	blend.advance(_setting(TUNNEL), 0.0)
	var midway: ReverbSetting = blend.advance(_setting(ROOM), 0.5)
	var back: ReverbSetting = blend.advance(_setting(TUNNEL), 0.1)
	if back.distance_to(midway) > 0.2:
		return "jumped from %s to %s turning back" % [midway, back]
	blend.advance(_setting(TUNNEL), 1.0)
	return "" if blend.current.same_as(_setting(TUNNEL)) else "never got back: %s" % blend.current


func test_no_box_keeps_the_blend_going() -> String:
	var blend: RoomReverbBlend = RoomReverbBlend.new(1.0)
	if blend.advance(null, 0.1) != null:
		return "a reverb before any room"
	blend.advance(_setting(TUNNEL), 0.0)
	blend.advance(_setting(ROOM), 0.25)
	var heard: ReverbSetting = blend.advance(null, 0.75)
	return "" if heard.same_as(_setting(ROOM)) else "a null target stopped the blend at %s" % heard


func test_no_time_holds_the_blend() -> String:
	var blend: RoomReverbBlend = RoomReverbBlend.new(1.0)
	blend.advance(_setting(TUNNEL), 0.0)
	var heard: ReverbSetting = blend.advance(_setting(ROOM), 0.0)
	return "" if heard.same_as(_setting(TUNNEL)) else "moved with no time passing: %s" % heard


func test_reset_hears_the_next_room_at_once() -> String:
	var blend: RoomReverbBlend = RoomReverbBlend.new(1.0)
	blend.advance(_setting(TUNNEL), 0.0)
	blend.reset()
	var heard: ReverbSetting = blend.advance(_setting(ROOM), 0.0)
	return "" if heard.same_as(_setting(ROOM)) else "after reset heard %s" % heard


func test_zero_blend_time_switches() -> String:
	var blend: RoomReverbBlend = RoomReverbBlend.new(0.0)
	blend.advance(_setting(TUNNEL), 0.0)
	var heard: ReverbSetting = blend.advance(_setting(ROOM), ShipState.TICK_DT)
	return "" if heard.same_as(_setting(ROOM)) else "blend 0 gave %s" % heard
