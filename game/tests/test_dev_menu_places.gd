extends RefCounted

## Where each dev menu entry shows (#1450, ARC-4, CRW-2, CMF-6): the shipped
## `dev_menu.json` names the places of every entry, the base, shaft choice and
## end screens get the settings but not Level, Restart level, Flight test or
## Return to base, a section with nothing for the place is left out, and the
## `places` key is checked when the file is read.

const MENU_FILE: String = "res://xr/dev_menu.json"
const MINE_ONLY: Array[String] = [DevMenuSpec.KIND_LEVEL, DevMenuSpec.KIND_RESTART,
	DevMenuSpec.KIND_RETURN, DevMenuSpec.KIND_FLIGHT_TEST]
## What the issue asks the menu to offer away from the mine; no sound or quit entry exists yet.
const AWAY_KINDS: Array[String] = [DevMenuSpec.KIND_UPDATE, DevMenuSpec.KIND_COMFORT,
	DevMenuSpec.KIND_BREAK, DevMenuSpec.KIND_REFRESH, DevMenuSpec.KIND_SWIVEL,
	DevMenuSpec.KIND_AUTO_LEVEL, DevMenuSpec.KIND_FOVEATION, DevMenuSpec.KIND_MAP_PLACE,
	DevMenuSpec.KIND_MAP_TURN, DevMenuSpec.KIND_CORNER, DevMenuSpec.KIND_CHECKLIST,
	DevMenuSpec.KIND_CLOSE]


static func _entry(spec: DevMenuSpec, kind: String) -> Dictionary:
	for entry: Dictionary in spec.entries:
		if entry["kind"] == kind:
			return entry
	return {}


func test_every_shipped_entry_names_its_places() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MENU_FILE))
	for entry: Dictionary in data["entries"]:
		if not entry.has(DevMenuPlaces.KEY):
			return "entry %s names no places" % entry["kind"]
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	return "" if spec.error == "" else "the shipped menu was refused: %s" % spec.error


func test_the_shipped_base_shaft_and_end_lists() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	for place: String in [DevMenuPlaces.BASE, DevMenuPlaces.SHAFT, DevMenuPlaces.END]:
		for kind: String in AWAY_KINDS:
			if not DevMenuPlaces.shows(_entry(spec, kind), place):
				return "%s does not show at %s" % [kind, place]
		for kind: String in MINE_ONLY:
			if DevMenuPlaces.shows(_entry(spec, kind), place):
				return "%s shows at %s" % [kind, place]
	for entry: Dictionary in spec.entries:
		if not DevMenuPlaces.shows(entry, DevMenuPlaces.MINE):
			return "%s does not show in the mine" % entry["kind"]
	return ""


func test_places_are_checked_when_read() -> String:
	var cases: Dictionary = {
		'"places": []': "non-empty",
		'"places": "base"': "non-empty",
		'"places": ["hangar"]': "hangar",
		'"places": ["base", "base"]': "twice",
	}
	for places: String in cases:
		var text: String = '{"entries": [{"kind": "close", "label": "Close", %s}], "corners": ["centre"]}' % places
		var spec: DevMenuSpec = DevMenuSpec.parse(text)
		if not spec.error.contains(cases[places]):
			return "%s gave \"%s\"" % [places, spec.error]
	var plain: DevMenuSpec = DevMenuSpec.parse('{"entries": [{"kind": "close", "label": "Close"}], "corners": ["centre"]}')
	if plain.error != "" or not DevMenuPlaces.shows(plain.entries[0], DevMenuPlaces.SHAFT):
		return "an entry without places is not shown everywhere: %s" % plain.error
	var extra: DevMenuSpec = DevMenuSpec.parse('{"entries": [{"kind": "close", "label": "Close", "x": 1}], "corners": ["centre"]}')
	return "" if extra.error.contains("exactly") else "an unknown entry key was read: %s" % extra.error


func test_at_the_base_the_mine_section_and_its_entries_are_left_out() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.load_file(), [])
	model.place = DevMenuPlaces.BASE
	model.open("centre", "")
	var shown: Array[String] = []
	for row: int in model.rows.rows():
		shown.append(DevMenu.row_text(model, row, false))
	if shown.has("Mine") or not shown.has("Comfort"):
		return "the base's top list is %s" % [shown]
	for step: int in 30:  # Every row the stick reaches, sections walked in.
		model.press({DevMenuModel.DOWN: true})
		model.press({})
		if MINE_ONLY.has(model.kind()):
			return "the stick reached %s at the base" % model.kind()
	model.place = DevMenuPlaces.MINE
	model.open("centre", "")
	shown.clear()
	for row: int in model.rows.rows():
		shown.append(DevMenu.row_text(model, row, false))
	return "" if shown.has("Mine") else "the mine's top list lost its Mine section: %s" % [shown]


func test_a_section_opened_at_the_base_lists_only_base_entries() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var model: DevMenuModel = DevMenuModel.new(spec, [])
	model.place = DevMenuPlaces.BASE
	model.open("centre", "")
	for index: int in spec.sections.size():
		model.rows.open_section(index)
		for row: int in model.rows.rows():
			if row >= 0 and not DevMenuPlaces.shows(spec.entries[row], DevMenuPlaces.BASE):
				return "section %s lists %s at the base" % [spec.sections[index]["label"], spec.entries[row]["kind"]]
		model.rows.back()
	return ""
