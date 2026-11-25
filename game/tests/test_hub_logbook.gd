extends RefCounted

## The hub's Logbook page (CRW-2, ARC-4, NAM-3, #1095): the profile's seven
## lifetime counters as information lines from `data/hub/hub.json`, zeros for an
## old profile, in the file's page order and with nothing to select.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _hub(profile: Profile) -> HubText:
	return HubText.new(HubModel.create(
		HubConfig.load_shipped(),
		profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		Fitting.new(),
		JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))))


## A profile with a different known value in every counter.
static func _flown_profile() -> Profile:
	var profile: Profile = Profile.new()
	profile.stats = ProfileStats.from_dict({
		"runs_started": 7, "runs_won": 1, "runs_lost": 5, "levels_escaped": 12,
		"deepest_level": 4, "miners_rescued": 9, "components_banked": 31,
	})
	return profile


static func _to_page(hub: HubText, id: String) -> void:
	for i: int in hub.model.pages().size():
		if hub.page_id() == id:
			return
		hub.turn_page(1)


func test_every_counter_has_a_line_in_the_file() -> String:
	var words: HubWords = HubConfig.load_shipped().words
	for key: String in ProfileStats.KEYS:
		var row: String = HubWords.STATS_ROW_PREFIX + key
		if not words.rows.has(row) or HubWords.PLACEHOLDERS[row] != ["count"]:
			return "no text.%s with {count}" % row
	if words.row("stats_empty") == "":
		return "no empty-profile line"
	return ""


func test_the_model_returns_the_seven_counters() -> String:
	var hub: HubText = _hub(_flown_profile())
	var counters: Dictionary = hub.model.stats()
	if counters.keys() != (ProfileStats.KEYS as Array) or counters["miners_rescued"] != 9 or counters["components_banked"] != 31:
		return "stats are %s" % counters
	return ""


func test_a_flown_profile_shows_each_counter_line() -> String:
	var hub: HubText = _hub(_flown_profile())
	var words: HubWords = hub.model.config.words
	_to_page(hub, HubConfig.STATS)
	var expected: Array[String] = [hub.model.page_title(HubConfig.STATS)]
	var counts: Dictionary = _flown_profile().stats.to_dict()
	for key: String in ProfileStats.KEYS:
		expected.append(words.row(HubWords.STATS_ROW_PREFIX + key, {"count": counts[key]}))
	if hub.lines() != expected:
		return "logbook is %s, expected %s" % [hub.lines(), expected]
	if not hub.lines().has("Rescued 9"):
		return "the miners line does not read its count: %s" % [hub.lines()]
	return ""


## The rows are selectable only so the page scrolls (#1300); none does anything.
func test_the_logbook_rows_do_nothing() -> String:
	var hub: HubText = _hub(_flown_profile())
	_to_page(hub, HubConfig.STATS)
	hub.move(3)
	if hub.selected_line() != 4 or hub.selected() != {} or hub.note() != "":
		return "row %d does %s, note \"%s\"" % [hub.selected_line(), hub.selected(), hub.note()]
	if hub.press() != "" or hub.model.stats() != _flown_profile().stats.to_dict():
		return "pressing on the logbook changed something"
	return ""


func test_old_profile_files_show_zeros_and_the_empty_line() -> String:
	for text: String in [
		"{\"version\": 1, \"banked\": {}, \"crafted\": []}",
		"{\"version\": 2, \"banked\": {}, \"crafted\": [], \"crew\": []}",
	]:
		var profile: Profile = Profile.parse_json(text)
		if profile.error != "":
			return profile.error
		var hub: HubText = _hub(profile)
		var words: HubWords = hub.model.config.words
		_to_page(hub, HubConfig.STATS)
		var lines: Array[String] = hub.lines()
		if lines.size() != 1 + ProfileStats.KEYS.size() or hub.note() != words.row("stats_empty"):
			return "old profile logbook is %s, note \"%s\"" % [lines, hub.note()]
		for i: int in ProfileStats.KEYS.size():
			if lines[i + 1] != words.row(HubWords.STATS_ROW_PREFIX + ProfileStats.KEYS[i], {"count": 0}):
				return "line %s is not zero" % lines[i + 1]
		hub.move(1)
		if hub.note() != "":
			return "the empty-logbook note shows under the second row too"
	var stripped: Profile = Profile.new()
	stripped.stats = null
	if _hub(stripped).model.stats() != ProfileStats.new().to_dict():
		return "a profile without stats did not read as zeros"
	return ""


func test_turning_pages_reaches_the_logbook_in_the_file_order() -> String:
	var hub: HubText = _hub(Profile.new())
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	var order: Array[String] = []
	for entry: Dictionary in data["pages"]:
		order.append(entry["id"])
	var seen: Array[String] = []
	for i: int in order.size():
		seen.append(hub.page_id())
		hub.turn_page(1)
	if seen != order or order.find(HubConfig.STATS) != order.find(HubConfig.CREW) + 1:
		return "pages turned %s, file lists %s" % [seen, order]
	if hub.model.page_title(HubConfig.STATS) != data["pages"][order.find(HubConfig.STATS)]["title"]:
		return "logbook title is not the file's"
	return ""
