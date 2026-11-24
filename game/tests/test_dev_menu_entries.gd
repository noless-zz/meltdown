extends RefCounted

## The dev menu's entry helpers (#892, ARC-4): every entry in the shipped
## `dev_menu.json`, and every kind the menu knows, resolves to exactly one
## helper, and the result it confirms is taken by that helper alone.

## A result `DevMenuModel.press` gives for each kind when confirmed.
const SAMPLE_RESULTS: Dictionary = {
	DevMenuSpec.KIND_UPDATE: DevMenuModel.UPDATE,
	DevMenuSpec.KIND_CORNER: DevMenuModel.CORNER_PREFIX + "top_left",
	DevMenuSpec.KIND_COMFORT: DevMenuModel.COMFORT_PREFIX + "2",
	DevMenuSpec.KIND_BREAK: DevMenuModel.BREAK_PREFIX + DevMenuModel.BREAK_OFF,
	DevMenuSpec.KIND_REFRESH: DevMenuModel.REFRESH_PREFIX + DevMenuModel.REFRESH_HIGH,
	DevMenuSpec.KIND_SWIVEL: DevMenuModel.SWIVEL_PREFIX + DevMenuModel.SWIVEL_ON,
	DevMenuSpec.KIND_AUTO_LEVEL: DevMenuModel.AUTO_LEVEL_PREFIX + DevMenuModel.AUTO_LEVEL_ON,
	DevMenuSpec.KIND_CONTROLS: DevMenuModel.CONTROLS_PREFIX + "gripped",
	DevMenuSpec.KIND_HANDS: DevMenuModel.HANDS_PREFIX + "left",
	DevMenuSpec.KIND_PITCH: DevMenuModel.PITCH_PREFIX + "inverted",
	DevMenuSpec.KIND_FOVEATION: DevMenuModel.FOVEATION_PREFIX + "2:on",
	DevMenuSpec.KIND_LEVEL: DevMenuModel.LEVEL_PREFIX + "seed:42",
	DevMenuSpec.KIND_RESTART: DevMenuModel.RESTART,
	DevMenuSpec.KIND_FLIGHT_TEST: DevMenuModel.FLIGHT_TEST,
	DevMenuSpec.KIND_RETURN: DevMenuModel.RETURN,
	DevMenuSpec.KIND_CLOSE: DevMenuModel.CLOSE,
	DevMenuSpec.KIND_MAP_PLACE: MapChoice.PLACE_PREFIX + MapChoice.PLACE_COCKPIT,
	DevMenuSpec.KIND_MAP_TURN: MapChoice.TURN_PREFIX + MapChoice.TURN_FOLLOWS,
}


static func _kinds_resolve(wiring: DevMenuWiring, kinds: Array[String]) -> String:
	for kind: String in kinds:
		var entry: DevMenuEntry = wiring.entry_for(kind)
		if entry == null:
			return "no helper for the %s entry" % kind
		if not SAMPLE_RESULTS.has(kind):
			return "the test has no sample result for %s" % kind
		var result: String = SAMPLE_RESULTS[kind]
		var takers: int = 0
		for other: DevMenuEntry in wiring.entries:
			if other.takes(result):
				takers += 1
		if not entry.takes(result) or takers != 1:
			return "%s: its helper takes %s: %s, helpers taking it: %d" \
				% [kind, result, entry.takes(result), takers]
	return ""


func test_every_entry_in_the_shipped_file_resolves_to_a_helper() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	if spec.error != "":
		return "the shipped dev_menu.json was rejected: %s" % spec.error
	var kinds: Array[String] = []
	for entry: Dictionary in spec.entries:
		kinds.append(str(entry["kind"]))
	var with_rate: DevMenuWiring = DevMenuWiring.new(null, null, null, null, RefreshRate.new())
	var without: DevMenuWiring = DevMenuWiring.new()
	var problem: String = _kinds_resolve(with_rate, kinds)
	if problem == "":
		problem = _kinds_resolve(without, kinds)
	return problem


func test_every_kind_the_menu_knows_has_one_helper() -> String:
	var wiring: DevMenuWiring = DevMenuWiring.new()
	for kind: String in DevMenuSpec.KINDS:
		var serving: int = 0
		for entry: DevMenuEntry in wiring.entries:
			if entry.kinds.has(kind):
				serving += 1
		if serving != 1:
			return "%d helpers serve %s" % [serving, kind]
	return _kinds_resolve(wiring, DevMenuSpec.KINDS)


func test_the_wiring_and_its_helpers_stay_under_the_size_guide() -> String:
	for path: String in ["res://dev_menu_wiring.gd", "res://dev_menu_entry.gd", "res://dev_menu_corner.gd",
			"res://dev_menu_controls.gd", "res://dev_menu_comfort.gd", "res://dev_menu_break.gd",
			"res://dev_menu_refresh.gd", "res://dev_menu_swivel.gd", "res://dev_menu_update.gd",
			"res://dev_menu_restart.gd", "res://dev_menu_foveation.gd", "res://dev_menu_auto_level.gd"]:
		var lines: int = FileAccess.get_file_as_string(path).split("\n").size() - 1
		if lines >= 300:
			return "%s has %d lines" % [path, lines]
	return ""
