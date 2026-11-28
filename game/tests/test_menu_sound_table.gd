extends RefCounted

## The development menu's sound table (#1457, AUD-1, ARC-4): the shipped file
## reads, a bad field is named and silences the menu, and the event logic
## picks open, point, change, confirm, refused and back from the menu's state.

const C: String = DevMenuModel.CONFIRM


static func _shipped() -> MenuSoundTable:
	return MenuSoundTable.load_file()


static func _open(section: int, row: int, text: String) -> Dictionary:
	return {"open": true, "section": section, "row": row, "text": text}


func test_the_shipped_file_reads_with_every_needed_sound() -> String:
	var table: MenuSoundTable = _shipped()
	if table.error != "":
		return "the shipped menu sounds were rejected: %s" % table.error
	for name: String in MenuSoundTable.NEEDED:
		if not table.sounds.has(name):
			return "no %s sound" % name
	for name: String in table.sounds:
		var path: String = table.sounds[name]["sound"]
		if not ResourceLoader.exists(path):
			return "%s names %s, which does not exist" % [name, path]
		if not path.get_file().begins_with("hub_"):
			return "%s uses %s, not one of the base's hub_*.wav" % [name, path]
	return ""


func test_an_unknown_field_is_named_and_the_menu_stays_silent() -> String:
	var table: MenuSoundTable = MenuSoundTable.parse(FileAccess.get_file_as_string(MenuSoundTable.DEFAULT_FILE)
		.replace("\"voices\"", "\"voice_count\": 2, \"voices\""))
	if not table.error.contains("voice_count") or not table.sounds.is_empty():
		return "an unknown root field gave error %s with %d sounds" % [table.error, table.sounds.size()]
	var row: MenuSoundTable = MenuSoundTable.parse(
		'{"voices": 1, "sounds": {"open": {"sound": "res://a.wav", "volume_db": 0, "min_gap_s": 0, "loud": 1}}}')
	if not row.error.contains("sounds.open.loud"):
		return "an unknown sound field gave error %s" % row.error
	return ""


func test_a_missing_sound_or_bad_confirmed_entry_is_named() -> String:
	var text: String = FileAccess.get_file_as_string(MenuSoundTable.DEFAULT_FILE)
	var no_refused: MenuSoundTable = MenuSoundTable.parse(text.replace("\"refused\":", "\"refusal\":"))
	if no_refused.error != "sounds.refused is missing":
		return "a missing refused sound gave %s" % no_refused.error
	var bad_link: MenuSoundTable = MenuSoundTable.parse(text.replace("\"restart\": \"launch\"", "\"restart\": \"boom\""))
	if not bad_link.error.contains("confirmed.restart") or not bad_link.error.contains("boom"):
		return "a confirmed entry naming no sound gave %s" % bad_link.error
	var bad_gap: MenuSoundTable = MenuSoundTable.parse(text.replace("\"min_gap_s\": 0.09", "\"min_gap_s\": -1"))
	if not bad_gap.error.contains("sounds.point.min_gap_s"):
		return "a negative gap gave %s" % bad_gap.error
	return ""


func test_point_plays_only_when_the_highlight_moves() -> String:
	var table: MenuSoundTable = _shipped()
	var at: Dictionary = _open(-1, 0, "Comfort")
	if table.event(at, _open(-1, 1, "Controls"), [DevMenuModel.DOWN], "") != MenuSoundTable.POINT:
		return "a step down was not point"
	if table.event(at, _open(-1, 1, "Controls"), [], "") != "":
		return "a highlight moved by the menu itself (no press) made a sound"
	if table.event(at, at, [], "") != "":
		return "an idle frame made a sound"
	return ""


func test_a_value_change_and_a_confirm_have_their_sounds() -> String:
	var table: MenuSoundTable = _shipped()
	var before: Dictionary = _open(1, 4, "Panel corner: < bottom left >")
	var after: Dictionary = _open(1, 4, "Panel corner: < bottom right >")
	if table.event(before, after, [DevMenuModel.RIGHT], "") != MenuSoundTable.CHANGE:
		return "a value step was not change"
	if table.event(before, before, [C], "corner:bottom_left") != MenuSoundTable.CONFIRM:
		return "a confirmed setting was not confirm"
	if table.event(_open(-1, -2, "Comfort"), _open(0, 2, "Comfort: < 1 >"), [C], "") != MenuSoundTable.CONFIRM:
		return "opening a section was not confirm"
	if table.event(_open(0, -1, "Back"), _open(-1, -2, "Comfort"), [C], "") != MenuSoundTable.BACK:
		return "the Back row was not back"
	if table.event(_open(2, 13, "Return to base"), _open(2, 13, "Sure? Return"), [C], "") != MenuSoundTable.CONFIRM:
		return "arming Return to base was not confirm"
	return ""


func test_a_refused_press_and_named_results() -> String:
	var table: MenuSoundTable = _shipped()
	var close_row: Dictionary = _open(-1, 19, "Close")
	if table.event(close_row, close_row, [DevMenuModel.RIGHT], "") != MenuSoundTable.REFUSED:
		return "right on a row with no value was not refused"
	if table.event(close_row, {"open": false}, [C], "close") != MenuSoundTable.BACK:
		return "the Close entry was not back"
	if table.event(_open(2, 12, "Restart level"), {"open": false}, [C], "restart") != "launch":
		return "Restart level did not play its named sound"
	if table.event(_open(2, 11, "Level"), {"open": false}, [C], "level:seed:7") != "launch":
		return "a level pick did not play its named sound"
	return ""


func test_open_and_close_without_a_press() -> String:
	var table: MenuSoundTable = _shipped()
	if table.event({"open": false}, _open(-1, -2, "Comfort"), [], "") != MenuSoundTable.OPEN:
		return "opening was not open"
	if table.event(_open(-1, -2, "Comfort"), {"open": false}, [], "") != MenuSoundTable.BACK:
		return "closing was not back"
	if table.event({"open": false}, {"open": false}, [C], "") != "":
		return "a press with the menu closed made a sound"
	return ""


func test_the_gap_holds_back_a_repeat_of_the_same_sound_only() -> String:
	var table: MenuSoundTable = _shipped()
	var gap: float = float(table.sounds[MenuSoundTable.POINT]["min_gap_s"])
	if not table.due(MenuSoundTable.POINT, -INF, 0.0):
		return "a sound never played was held back"
	if table.due(MenuSoundTable.POINT, 1.0, 1.0 + gap * 0.5):
		return "point repeated inside its gap"
	if not table.due(MenuSoundTable.POINT, 1.0, 1.0 + gap):
		return "point was held back after its gap"
	if table.due("thunder", -INF, 5.0):
		return "a sound not in the table was due"
	return ""


func test_pressed_counts_a_press_once() -> String:
	var held: Dictionary = {DevMenuModel.DOWN: true, C: false}
	var down: Array[String] = MenuSoundTable.pressed({}, held)
	if down.size() != 1 or down[0] != DevMenuModel.DOWN:
		return "a new press was %s" % [down]
	if not MenuSoundTable.pressed(held, held).is_empty():
		return "a held action counted again"
	return ""
