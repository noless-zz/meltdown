extends RefCounted

## The music's mix (#1303, AUD-3): the layers by alarm level below, at and
## above each threshold; the meltdown overrides the alarm layers; the hub and
## the end screens; and every change blends over the table's time.


static func _table() -> MusicTable:
	var table: MusicTable = MusicTable.parse(JSON.stringify({
		"volume_db": -10.0, "crossfade_seconds": 2.0, "meltdown_seconds": 0.5, "end_fade_seconds": 1.0,
		"layers": [
			{"id": "calm", "plays": "run", "from_alarm": 0.0, "sound": "res://a.wav"},
			{"id": "low", "plays": "run", "from_alarm": 0.4, "sound": "res://b.wav", "volume_db": -4.0},
			{"id": "high", "plays": "run", "from_alarm": 0.8, "sound": "res://c.wav"},
			{"id": "melt", "plays": "meltdown", "sound": "res://d.wav"},
			{"id": "home", "plays": "hub", "sound": "res://e.wav"},
		],
	}))
	assert(table.error == "", table.error)
	return table


static func _on(wanted: Dictionary[String, float]) -> Array[String]:
	var on: Array[String] = []
	for id: String in wanted:
		if wanted[id] == 1.0:
			on.append(id)
		elif wanted[id] != 0.0:
			on.append("%s=%f" % [id, wanted[id]])
	return on


func test_layers_by_alarm_around_each_threshold() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	var cases: Array = [
		[0.0, ["calm"]], [0.39, ["calm"]], [0.4, ["calm", "low"]], [0.41, ["calm", "low"]],
		[0.79, ["calm", "low"]], [0.8, ["calm", "low", "high"]], [1.0, ["calm", "low", "high"]],
	]
	for row: Array in cases:
		var on: Array[String] = _on(mix.targets(MusicMix.Mood.RUN, row[0]))
		if str(on) != str(row[1]):
			return "alarm %.2f plays %s, not %s" % [row[0], on, row[1]]
	return ""


func test_meltdown_overrides_the_alarm_layers() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	for alarm: float in [0.0, 0.5, 1.0]:
		var on: Array[String] = _on(mix.targets(MusicMix.Mood.MELTDOWN, alarm))
		if str(on) != str(["melt"]):
			return "meltdown at alarm %.1f plays %s" % [alarm, on]
	return ""


func test_hub_end_and_silent_moods() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	if str(_on(mix.targets(MusicMix.Mood.HUB, 1.0))) != str(["home"]):
		return "the hub plays %s" % [_on(mix.targets(MusicMix.Mood.HUB, 1.0))]
	for mood: MusicMix.Mood in [MusicMix.Mood.ENDED, MusicMix.Mood.SILENT]:
		if not _on(mix.targets(mood, 1.0)).is_empty():
			return "mood %d plays %s" % [mood, _on(mix.targets(mood, 1.0))]
	return ""


func test_crossfade_blends_over_the_set_time() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	mix.advance(MusicMix.Mood.RUN, 0.0, 1.0)
	if not is_equal_approx(mix.gains["calm"], 0.5):
		return "calm at %f after half the crossfade" % mix.gains["calm"]
	mix.advance(MusicMix.Mood.RUN, 0.0, 1.0)
	if mix.gains["calm"] != 1.0:
		return "calm at %f after the crossfade" % mix.gains["calm"]
	# The alarm rises: the low layer joins over the crossfade, by small steps.
	var last: float = 0.0
	for tick: int in 120:
		mix.advance(MusicMix.Mood.RUN, 0.5, ShipState.TICK_DT)
		if mix.gains["low"] - last > ShipState.TICK_DT / 2.0 + 0.0001:
			return "low jumped from %f to %f" % [last, mix.gains["low"]]
		last = mix.gains["low"]
	if not is_equal_approx(last, 1.0) or mix.gains["calm"] != 1.0 or mix.gains["high"] != 0.0:
		return "after 2 s: %s" % [mix.gains]
	return ""


func test_meltdown_takes_over_within_its_time() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	mix.advance(MusicMix.Mood.RUN, 1.0, 5.0)
	if str(mix.sounding()) != str(["calm", "low", "high"]):
		return "before: %s" % [mix.sounding()]
	mix.advance(MusicMix.Mood.MELTDOWN, 1.0, 0.25)
	if not is_equal_approx(mix.gains["melt"], 0.5) or not is_equal_approx(mix.gains["calm"], 0.5):
		return "half way: %s" % [mix.gains]
	mix.advance(MusicMix.Mood.MELTDOWN, 1.0, 0.25)
	return "" if str(mix.sounding()) == str(["melt"]) and mix.gains["melt"] == 1.0 else "after: %s" % [mix.gains]


func test_end_screen_fades_everything_out() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	mix.advance(MusicMix.Mood.MELTDOWN, 0.0, 1.0)
	mix.advance(MusicMix.Mood.ENDED, 0.0, 0.5)
	if not is_equal_approx(mix.gains["melt"], 0.5):
		return "half way through the end fade: %f" % mix.gains["melt"]
	mix.advance(MusicMix.Mood.ENDED, 0.0, 0.5)
	return "" if mix.sounding().is_empty() else "still sounding: %s" % [mix.sounding()]


func test_volume_adds_music_layer_and_gain() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	var low: MusicLayer = mix.table.layer("low")
	if not is_equal_approx(mix.volume_db(low, 1.0), -14.0):
		return "full low at %f dB" % mix.volume_db(low, 1.0)
	if not is_equal_approx(mix.volume_db(low, 0.5), -14.0 + linear_to_db(0.5)):
		return "half low at %f dB" % mix.volume_db(low, 0.5)
	return "" if mix.volume_db(low, 0.0) == -80.0 else "silent low at %f dB" % mix.volume_db(low, 0.0)


func test_reset_silences() -> String:
	var mix: MusicMix = MusicMix.new(_table())
	mix.advance(MusicMix.Mood.HUB, 0.0, 10.0)
	mix.reset()
	return "" if mix.sounding().is_empty() and mix.mood == MusicMix.Mood.SILENT else "not reset"
