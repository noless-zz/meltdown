extends RefCounted

## The home base stations' sound table (#1401, AUD-1, CRW-2, ARC-4, NAM-3):
## the shipped file reads, a bad one names its field, each hub action maps to
## its sound, a frame's state change picks the right one, and a sound cannot
## repeat inside its gap.

static func _table() -> HubSoundTable:
	return HubSoundTable.load_file()


static func _state(in_use: String, highlighted: int, line: int) -> Dictionary:
	return {"in_use": in_use, "highlighted": highlighted, "line": line}


func test_the_shipped_table_reads_and_every_sound_exists() -> String:
	var table: HubSoundTable = _table()
	if table.error != "":
		return table.error
	for sound_name: String in ["point", "select", "back", "refused", "crafted", "mounted", "unmounted", "launch"]:
		if not table.sounds.has(sound_name):
			return "no %s sound" % sound_name
		var path: String = table.sounds[sound_name]["sound"]
		if not ResourceLoader.exists(path):
			return "%s plays %s, which does not exist" % [sound_name, path]
		if float(table.sounds[sound_name]["volume_db"]) > -6.0:
			return "%s is at %s dB; station sounds stay soft" % [sound_name, table.sounds[sound_name]["volume_db"]]
	if float(table.sounds["point"]["min_gap_s"]) <= 0.0:
		return "pointing has no repeat gap, so scrolling would tick on every row"
	return ""


func test_a_bad_table_names_its_field() -> String:
	var good: String = FileAccess.get_file_as_string(HubSoundTable.DEFAULT_FILE)
	var cases: Dictionary[String, String] = {
		"[]": "not a JSON object",
		good.replace("\"voices\": 4", "\"voices\": 0"): "voices",
		good.replace("\"min_gap_s\": 0.09", "\"min_gap_s\": -1"): "sounds.point.min_gap_s",
		good.replace("\"refused\": {", "\"refusedx\": {"): "sounds.refused is missing",
		good.replace("\"craft\": \"crafted\"", "\"craft\": \"fanfare\""): "pressed.craft",
		good.replace("res://data/audio/hub_back.wav", "hub_back.wav"): "sounds.back.sound",
	}
	for text: String in cases:
		var table: HubSoundTable = HubSoundTable.parse(text)
		if table.error.find(cases[text]) < 0:
			return "expected an error naming %s, got '%s'" % [cases[text], table.error]
		if not table.sounds.is_empty():
			return "a rejected table kept its sounds"
	return ""


func test_each_hub_action_plays_its_sound() -> String:
	var table: HubSoundTable = _table()
	var cases: Array[Array] = [
		[{"action": "craft", "id": "arc_lance"}, "crafted"],
		[{"action": "fit", "slot": "primary[0]", "id": "arc_lance"}, "mounted"],
		[{"action": "move", "slot": "primary[1]", "id": "arc_lance"}, "mounted"],
		[{"action": "fit", "slot": "primary[0]", "id": ""}, "unmounted"],
		[{"action": "strip"}, "unmounted"],
		[{"action": "launch"}, "launch"],
		[{"action": "resume"}, "launch"],
		[{"action": "slot", "slot": "primary[0]"}, "select"],
		[{}, "select"],
	]
	for case: Array in cases:
		var got: String = table.pressed_sound(case[0])
		if got != case[1]:
			return "%s plays %s, expected %s" % [case[0], got, case[1]]
	return ""


func test_a_frame_picks_point_select_back_refused_or_nothing() -> String:
	var table: HubSoundTable = _table()
	var choosing: Dictionary = _state("", 2, 1)
	var in_craft: Dictionary = _state("craft", 2, 1)
	var cases: Array[Array] = [
		[choosing, _state("", 3, 1), DevMenuModel.RIGHT, {}, "point"],
		[choosing, _state("", 3, 1), "", {}, "point"],  # The aim moved the highlight.
		[choosing, in_craft, DevMenuModel.CONFIRM, {}, "select"],
		[in_craft, _state("craft", 2, 2), DevMenuModel.DOWN, {}, "point"],
		[in_craft, in_craft, DevMenuModel.UP, {}, ""],  # Already at the top row.
		[in_craft, choosing, DevMenuModel.LEFT, {}, "back"],
		[_state("fit", 3, 4), _state("fit", 3, 2), DevMenuModel.LEFT, {}, "back"],  # Back to the ship.
		[in_craft, in_craft, DevMenuModel.CONFIRM, {"pressed": {"action": "craft", "id": "x"}, "reason": "needs 3 scrap"}, "refused"],
		[in_craft, _state("craft", 2, 3), DevMenuModel.CONFIRM, {"pressed": {"action": "craft", "id": "x"}, "reason": ""}, "crafted"],
		[in_craft, in_craft, "", {}, ""],
	]
	for case: Array in cases:
		var got: String = table.event(case[0], case[1], case[2], case[3])
		if got != case[4]:
			return "%s -> %s on %s %s gave '%s', expected '%s'" % [case[0], case[1], case[2], case[3], got, case[4]]
	return ""


func test_a_sound_waits_out_its_gap_and_others_do_not() -> String:
	var table: HubSoundTable = _table()
	var gap: float = float(table.sounds["point"]["min_gap_s"])
	if not table.due("point", -INF, 0.0):
		return "a sound never played is held back"
	if table.due("point", 1.0, 1.0 + gap * 0.5):
		return "point repeats inside its gap"
	if not table.due("point", 1.0, 1.0 + gap):
		return "point is held back after its gap"
	if table.due("fanfare", -INF, 0.0):
		return "an unknown sound is due"
	return ""

