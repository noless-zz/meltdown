extends RefCounted

## The room tones' mix (#1399, AUD-1): on a hand-made level of a narrow
## tunnel into a wide room, the tone follows the box, a change crossfades
## over the table's second with no jump, the reactor adds a pulse near it, the
## meltdown takes over from every space, the base hears the hangar and an end
## screen fades everything out.

const TUNNEL_POINT: Vector3 = Vector3(0, 0, -10)
const ROOM_POINT: Vector3 = Vector3(0, 0, -50)


static func _table() -> RoomToneTable:
	return RoomToneTable.parse(JSON.stringify({
		"fade_seconds": 1.0,
		"spaces": [
			{"id": "tunnel", "from_span_m": 0.0, "sound": "res://a.wav", "volume_db": -38.0},
			{"id": "room", "from_span_m": 10.0, "sound": "res://b.wav", "volume_db": -36.0},
		],
		"reactor": {"sound": "res://c.wav", "volume_db": -35.0, "near_m": 30.0, "full_m": 10.0},
		"meltdown": {"sound": "res://d.wav", "volume_db": -32.0},
		"hangar": {"sound": "res://e.wav", "volume_db": -38.0},
	}))


static func _walls() -> BoxUnion:
	return BoxUnion.new([BoxBounds.new(Vector3(-3, -3, -40), Vector3(3, 3, 0)),
		BoxBounds.new(Vector3(-10, -10, -60), Vector3(10, 10, -40))] as Array[BoxBounds])


static func _reactor(position: Vector3) -> ReactorState:
	return ReactorState.parse({"position": [position.x, position.y, position.z], "radius": 2.0,
		"hull": 100.0, "meltdown_seconds": 60.0})


## Follows `mix` for `ticks` ticks at `point`; returns the largest one-tick gain change.
static func _fly(mix: RoomToneMix, mood: MusicMix.Mood, point: Vector3, reactor: ReactorState,
		ticks: int) -> float:
	var largest: float = 0.0
	for tick: int in ticks:
		var before: Dictionary[String, float] = mix.gains.duplicate()
		mix.follow(mood, _walls(), point, reactor, ShipState.TICK_DT)
		for id: String in before:
			largest = maxf(largest, absf(mix.gains[id] - before[id]))
	return largest


func test_tone_follows_the_box() -> String:
	var mix: RoomToneMix = RoomToneMix.new(_table())
	_fly(mix, MusicMix.Mood.RUN, TUNNEL_POINT, null, 70)
	if str(mix.sounding()) != str(["tunnel"]) or mix.gains["tunnel"] != 1.0:
		return "in the tunnel heard %s" % [mix.gains]
	_fly(mix, MusicMix.Mood.RUN, ROOM_POINT, null, 70)
	if str(mix.sounding()) != str(["room"]) or mix.gains["room"] != 1.0:
		return "in the room heard %s" % [mix.gains]
	return "" if is_equal_approx(mix.db("room"), -36.0) else "the room at %.1f dB" % mix.db("room")


func test_change_of_box_crossfades_over_a_second() -> String:
	var mix: RoomToneMix = RoomToneMix.new(_table())
	_fly(mix, MusicMix.Mood.RUN, TUNNEL_POINT, null, 70)
	var largest: float = _fly(mix, MusicMix.Mood.RUN, ROOM_POINT, null, 30)
	if not is_equal_approx(mix.gains["tunnel"], 0.5) or not is_equal_approx(mix.gains["room"], 0.5):
		return "half way through heard %s" % [mix.gains]
	largest = maxf(largest, _fly(mix, MusicMix.Mood.RUN, ROOM_POINT, null, 30))
	if mix.gains["room"] != 1.0 or mix.gains["tunnel"] != 0.0:
		return "after a second heard %s" % [mix.gains]
	return "" if largest <= ShipState.TICK_DT + 0.0001 else "a gain jumped %.3f in a tick" % largest


func test_outside_every_box_keeps_the_bed() -> String:
	var mix: RoomToneMix = RoomToneMix.new(_table())
	_fly(mix, MusicMix.Mood.RUN, TUNNEL_POINT, null, 70)
	_fly(mix, MusicMix.Mood.RUN, Vector3(0, 80, 0), null, 70)
	return "" if mix.bed == "tunnel" and mix.gains["tunnel"] == 1.0 else "outside heard %s" % [mix.gains]


func test_reactor_adds_a_pulse_near_it() -> String:
	var mix: RoomToneMix = RoomToneMix.new(_table())
	_fly(mix, MusicMix.Mood.RUN, ROOM_POINT, _reactor(Vector3(0, 0, -100)), 70)
	if mix.gains["reactor"] != 0.0:
		return "50 m away the pulse is at %.2f" % mix.gains["reactor"]
	_fly(mix, MusicMix.Mood.RUN, ROOM_POINT, _reactor(Vector3(0, 0, -70)), 70)
	if not is_equal_approx(mix.gains["reactor"], 0.5) or mix.gains["room"] != 1.0:
		return "20 m away heard %s" % [mix.gains]
	var gone: ReactorState = _reactor(Vector3(0, 0, -55))
	gone.destroyed = true
	_fly(mix, MusicMix.Mood.MELTDOWN, ROOM_POINT, gone, 70)
	return "" if mix.gains["reactor"] == 0.0 else "the pulse stays after the meltdown"


func test_meltdown_takes_over_from_every_space() -> String:
	var mix: RoomToneMix = RoomToneMix.new(_table())
	_fly(mix, MusicMix.Mood.RUN, TUNNEL_POINT, null, 70)
	var largest: float = _fly(mix, MusicMix.Mood.MELTDOWN, TUNNEL_POINT, null, 61)
	if str(mix.sounding()) != str(["meltdown"]) or mix.gains["meltdown"] != 1.0:
		return "a second into the meltdown heard %s" % [mix.gains]
	_fly(mix, MusicMix.Mood.MELTDOWN, ROOM_POINT, null, 70)
	if str(mix.sounding()) != str(["meltdown"]):
		return "the meltdown gave way to %s" % [mix.sounding()]
	return "" if largest <= ShipState.TICK_DT + 0.0001 else "the meltdown jumped %.3f in a tick" % largest


func test_base_hears_the_hangar_and_an_end_fades_out() -> String:
	var mix: RoomToneMix = RoomToneMix.new(_table())
	_fly(mix, MusicMix.Mood.HUB, TUNNEL_POINT, null, 70)
	if str(mix.sounding()) != str(["hangar"]):
		return "at the base heard %s" % [mix.sounding()]
	_fly(mix, MusicMix.Mood.RUN, TUNNEL_POINT, null, 70)
	_fly(mix, MusicMix.Mood.ENDED, TUNNEL_POINT, null, 61)
	return "" if mix.sounding().is_empty() and mix.db("tunnel") == -INF else "after the end heard %s" % [mix.gains]


func test_reset_silences_at_once() -> String:
	var mix: RoomToneMix = RoomToneMix.new(_table())
	_fly(mix, MusicMix.Mood.RUN, TUNNEL_POINT, null, 70)
	mix.reset()
	if not mix.sounding().is_empty():
		return "reset left %s" % [mix.sounding()]
	_fly(mix, MusicMix.Mood.RUN, ROOM_POINT, null, 1)
	return "" if is_equal_approx(mix.gains["room"], ShipState.TICK_DT) else "the room did not fade in"


func test_rejected_table_has_no_layers() -> String:
	var mix: RoomToneMix = RoomToneMix.new(RoomToneTable.parse("{}"))
	var heard: Array[String] = mix.follow(MusicMix.Mood.RUN, _walls(), TUNNEL_POINT, null, 1.0)
	return "" if heard.is_empty() else "a rejected table sounds %s" % [heard]
