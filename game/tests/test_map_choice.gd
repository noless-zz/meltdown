extends RefCounted

## The map's place and turn settings (#1321, MAP-1): the defaults are the map
## as it was, both choices are saved and read back without one clobbering the
## other, an older install with no file gets the defaults, a bad file or value
## is ignored with a warning, and the dev menu's two rows show and save them.

const PATH: String = "user://test_map_choice.json"


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	MapChoice.current_place = MapChoice.PLACE_HAND
	MapChoice.current_turn = MapChoice.TURN_FIXED


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_an_install_without_the_file_gets_the_map_as_it_was() -> String:
	_clean()
	MapChoice.current_place = MapChoice.PLACE_COCKPIT
	var store: MapChoice = MapChoice.from_launch(PATH)
	var got: Array[String] = [store.place(), store.turn(), MapChoice.current_place, MapChoice.current_turn]
	_clean()
	if got != [MapChoice.PLACE_HAND, MapChoice.TURN_FIXED, MapChoice.PLACE_HAND, MapChoice.TURN_FIXED]:
		return "no file gave %s" % [got]
	if not store.warnings.is_empty():
		return "a missing file warned: %s" % [store.warnings]
	return ""


func test_both_choices_are_saved_and_read_back() -> String:
	_clean()
	var place_store: MapChoice = MapChoice.from_launch(PATH)
	var turn_store: MapChoice = MapChoice.from_launch(PATH)
	if not place_store.choose_place(MapChoice.PLACE_COCKPIT):
		return "the cockpit place was refused"
	# A second store, as the menu keeps, must not write the old place back.
	if not turn_store.choose_turn(MapChoice.TURN_FOLLOWS):
		return "the following turn was refused"
	MapChoice.current_place = MapChoice.PLACE_HAND
	MapChoice.current_turn = MapChoice.TURN_FIXED
	var read: MapChoice = MapChoice.from_launch(PATH)
	var got: Array[String] = [read.place(), read.turn(), MapChoice.current_place, MapChoice.current_turn]
	_clean()
	if got != [MapChoice.PLACE_COCKPIT, MapChoice.TURN_FOLLOWS, MapChoice.PLACE_COCKPIT, MapChoice.TURN_FOLLOWS]:
		return "read back %s" % [got]
	return ""


func test_unknown_values_are_ignored_with_a_warning() -> String:
	_clean()
	var store: MapChoice = MapChoice.from_launch(PATH)
	var taken: bool = store.choose_place("dash") or store.choose_turn("spin")
	var warned: int = store.warnings.size()
	var exists: bool = FileAccess.file_exists(PATH)
	_clean()
	if taken or warned != 2 or exists:
		return "taken %s, %d warnings, file written %s" % [taken, warned, exists]
	return ""


func test_a_broken_file_gives_the_defaults_with_a_warning() -> String:
	for text: String in ["not json", "[]", "{\"place\": \"cockpit\"}",
			"{\"place\": \"cockpit\", \"turn\": \"spin\"}",
			"{\"place\": \"cockpit\", \"turn\": \"fixed\", \"zoom\": 2}"]:
		_clean()
		_write(text)
		var store: MapChoice = MapChoice.from_launch(PATH)
		var got: Array[String] = [store.place(), store.turn()]
		var warned: int = store.warnings.size()
		_clean()
		if got != [MapChoice.PLACE_HAND, MapChoice.TURN_FIXED] or warned != 1:
			return "%s gave %s with %d warnings" % [text, got, warned]
	return ""


func test_the_menu_rows_show_the_choice_and_save_it() -> String:
	_clean()
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var model: DevMenuModel = DevMenuModel.new(spec, [])
	var entry: DevMenuMap = DevMenuMap.new()
	entry.store = MapChoice.new(PATH)
	MapChoice.current_place = MapChoice.PLACE_COCKPIT
	entry.show_on(model)
	var shown: Array[String] = [model.value_text(DevMenuSpec.KIND_MAP_PLACE),
		model.value_text(DevMenuSpec.KIND_MAP_TURN)]
	if shown != [spec.map_cockpit_text, spec.map_fixed_text]:
		_clean()
		return "the rows show %s" % [shown]
	model.value(DevMenuSpec.KIND_MAP_TURN).step(1)
	var result: String = model.value(DevMenuSpec.KIND_MAP_TURN).confirmed()
	if not entry.takes(result):
		_clean()
		return "the entry does not take %s" % result
	entry.choose(result)
	var read: MapChoice = MapChoice.from_launch(PATH)
	var got: Array[String] = [read.place(), read.turn()]
	_clean()
	if got != [MapChoice.PLACE_COCKPIT, MapChoice.TURN_FOLLOWS]:
		return "choosing %s saved %s" % [result, got]
	return ""


func test_the_display_section_lists_the_two_rows_after_the_corner() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	for section: Dictionary in spec.sections:
		if section["label"] == "Display":
			var kinds: Array = section["kinds"]
			# Rows added after them (Render scale, #1417) do not move them.
			if kinds.slice(0, 3) != [DevMenuSpec.KIND_CORNER, DevMenuSpec.KIND_MAP_PLACE, DevMenuSpec.KIND_MAP_TURN]:
				return "the Display section lists %s" % [kinds]
			for row: String in ["Map place: " + spec.map_hand_text, "Map place: " + spec.map_cockpit_text,
					"Map turn: " + spec.map_fixed_text, "Map turn: " + spec.map_follows_text]:
				if row.length() > spec.max_row_chars:
					return "\"%s\" is longer than a row's %d characters" % [row, spec.max_row_chars]
			return ""
	return "no Display section in %s" % [spec.sections]
