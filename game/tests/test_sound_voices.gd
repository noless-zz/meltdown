extends RefCounted

## The cap on simultaneous cues (#1290, AUD-1): never more voices than the
## table allows, the oldest quiet voice goes first, and with none quiet the
## oldest of all.


func test_cap_holds() -> String:
	var voices: SoundVoices = SoundVoices.new(4, -6.0)
	for index: int in 20:
		voices.start(-10.0 if index % 2 == 0 else 0.0)
		if voices.count() > 4:
			return "%d voices after %d starts" % [voices.count(), index + 1]
	return "" if voices.count() == 4 else "%d voices" % voices.count()


func test_oldest_quiet_voice_is_dropped_first() -> String:
	var voices: SoundVoices = SoundVoices.new(4, -6.0)
	var loud: int = voices.start(0.0)[0]
	var quiet_old: int = voices.start(-10.0)[0]
	var quiet_new: int = voices.start(-8.0)[0]
	var loud_two: int = voices.start(2.0)[0]
	var started: Array[int] = voices.start(0.0)
	if started[1] != quiet_old:
		return "dropped %d, expected the oldest quiet %d" % [started[1], quiet_old]
	if voices.numbers() != [loud, quiet_new, loud_two, started[0]]:
		return "voices left %s" % [voices.numbers()]
	return ""


func test_oldest_voice_goes_when_none_is_quiet() -> String:
	var voices: SoundVoices = SoundVoices.new(2, -6.0)
	var first: int = voices.start(0.0)[0]
	voices.start(0.0)
	var started: Array[int] = voices.start(0.0)
	return "" if started[1] == first else "dropped %d, expected %d" % [started[1], first]


func test_finished_voices_free_their_place() -> String:
	var voices: SoundVoices = SoundVoices.new(2, -6.0)
	var first: int = voices.start(0.0)[0]
	voices.start(0.0)
	voices.finish(first)
	voices.finish(12345)
	var started: Array[int] = voices.start(0.0)
	return "" if started[1] == -1 and voices.count() == 2 else "dropped %d with a free place" % started[1]


func test_shipped_cap_is_used() -> String:
	var player: SoundCues = SoundCues.new()
	var cap: int = SoundCueTable.load_file().max_voices
	var ok: bool = player.voices.max_voices == cap
	player.free()
	return "" if ok else "the player's cap is not the table's %d" % cap
