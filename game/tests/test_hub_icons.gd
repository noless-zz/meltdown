extends RefCounted

## The home base's icon set (#1365, CRW-2, CRF-1, CRF-3, GFX-2, ARC-4, NAM-3):
## every id the data files ship has an icon, a missing one falls back to a
## plain marker with a warning, the icons of a group differ in colour and stand
## out from the dark screens, the component icons share the in-mine colours,
## and the icons are as large as the words beside them. Drawing them is in
## `test_hub_icon_widgets.gd`.

const COMPONENTS_DIR: String = "res://data/components"
const WEAPONS_DIR: String = "res://data/weapons"
const PARTS_DIR: String = "res://data/ship_parts"
const UTILITY_DIR: String = "res://data/utility"
const ROLES_PATH: String = "res://data/crew/roles.json"
## The attributes the ship summary shows (#1357): the issue's seven, and the
## map reveal the Surveyor changes.
const ATTRIBUTES: Array[String] = ["hull", "shield", "energy", "thrust", "boost", "salvage_slots",
	"meltdown_seconds", "map_reveal"]
## #1359: the stations are read from the seat at 1.4 m, and the smallest word
## must stand at least 0.9 degrees tall; an icon is no smaller than a word.
const SEAT_DISTANCE_M: float = 1.4
const MIN_ICON_DEG: float = 0.9


static func _json_files(dir: String) -> Dictionary:
	var found: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			found[file.get_basename()] = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
	return found


## Group to the ids the data files ship for it.
static func _shipped_ids() -> Dictionary:
	var ids: Dictionary = {"component": [], "weapon": [], "part_family": [], "utility": [], "crew": [],
		"attribute": ATTRIBUTES.duplicate()}
	var components: Dictionary = _json_files(COMPONENTS_DIR)
	for name: String in components:
		if typeof(components[name]) == TYPE_DICTIONARY and (components[name] as Dictionary).has("map_colour"):
			ids["component"].append(name)
	ids["weapon"].append_array(_json_files(WEAPONS_DIR).keys())
	var parts: Dictionary = _json_files(PARTS_DIR)
	for name: String in parts:
		var kind: String = parts[name]["kind"]
		if not ids["part_family"].has(kind):
			ids["part_family"].append(kind)
		if kind == "module":
			ids["utility"].append(name)
	for name: String in _json_files(UTILITY_DIR):
		if not ids["utility"].has(name):
			ids["utility"].append(name)
	for role: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(ROLES_PATH))["roles"]:
		ids["crew"].append(role["id"])
	return ids


func test_the_shipped_file_is_read() -> String:
	var icons: HubIcons = HubIcons.load_file()
	if icons.error != "":
		return icons.error
	for group: String in HubIcons.GROUPS:
		if icons.ids(group).is_empty():
			return "no icons in %s" % group
	return ""


func test_every_shipped_id_has_an_icon() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var shipped: Dictionary = _shipped_ids()
	if shipped["component"].size() != 4 or shipped["part_family"].size() != 4 or shipped["weapon"].size() < 8:
		return "the data files changed shape: %s" % [shipped]
	for group: String in shipped:
		for id: String in shipped[group]:
			if not icons.has_icon(group, id):
				return "no %s icon for %s" % [group, id]
	return ""


func test_component_icons_have_the_in_mine_colours() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var components: Dictionary = _json_files(COMPONENTS_DIR)
	for id: String in icons.ids("component"):
		var mine: Color = Color.html(components[id]["map_colour"])
		var drawn: Color = icons.icon("component", id)["color"]
		if HubIcons.color_distance(mine, drawn) > 0.01:
			return "%s is drawn %s, in the mine %s" % [id, drawn.to_html(false), mine.to_html(false)]
	return ""


func test_the_icons_of_a_group_differ_in_colour() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var least: float = icons.numbers["min_color_distance"]
	if least < 0.25:
		return "the file asks only %s apart" % least
	for group: String in HubIcons.GROUPS:
		if HubIcons.SHAPE_ONLY_GROUPS.has(group):
			continue  # The menu's icons stand beside their labels in the menu's colour (#1458).
		var ids: Array[String] = icons.ids(group)
		for i: int in ids.size():
			for j: int in range(i + 1, ids.size()):
				var apart: float = HubIcons.color_distance(icons.icon(group, ids[i])["color"],
					icons.icon(group, ids[j])["color"])
				if apart < least:
					return "%s %s and %s are only %.2f apart" % [group, ids[i], ids[j], apart]
	return ""


func test_every_icon_stands_out_from_the_dark_screen() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var backdrop: Color = icons.colors["backdrop_color"]
	var screen: Color = HubScreenLook.load_file()["screen_color"]
	if not backdrop.is_equal_approx(screen):
		return "backdrop_color %s is not the screens' face %s" % [backdrop, screen]
	if icons.numbers["min_contrast"] < 3.0:
		return "the file asks only %s:1" % icons.numbers["min_contrast"]
	for group: String in HubIcons.GROUPS:
		for id: String in icons.ids(group):
			var ratio: float = HubIcons.contrast(icons.icon(group, id)["color"], backdrop)
			if ratio < icons.numbers["min_contrast"]:
				return "%s %s is %.1f:1 on the screen" % [group, id, ratio]
	for key: String in ["count_color", "short_color"]:
		if HubIcons.contrast(icons.colors[key], backdrop) < 7.0:
			return "the %s number is under 7:1 on the screen" % key
	return ""


func test_icons_are_as_large_as_the_words() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var degrees: float = rad_to_deg(2.0 * atan(icons.numbers["size_m"] * 0.5 / SEAT_DISTANCE_M))
	if degrees < MIN_ICON_DEG:
		return "an icon stands %.2f degrees from the seat, under %s" % [degrees, MIN_ICON_DEG]
	var cap_m: float = icons.numbers["count_font_size"] * icons.numbers["pixel_size"] * 0.7
	if rad_to_deg(2.0 * atan(cap_m * 0.5 / SEAT_DISTANCE_M)) < MIN_ICON_DEG * 0.5:
		return "the count's letters are too small to read from the seat"
	return ""


func test_a_missing_id_falls_back_with_one_warning_record() -> String:
	var icons: HubIcons = HubIcons.load_file()
	var marker: Dictionary = icons.icon("weapon", "not_a_weapon")
	icons.icon("weapon", "not_a_weapon")
	icons.icon("no_such_group", "pulse_cannon")
	if marker != icons.fallback or marker.is_empty() or (marker["parts"] as Array).is_empty():
		return "a missing weapon did not draw the fallback"
	if icons.fell_back != ["weapon/not_a_weapon", "weapon/not_a_weapon", "no_such_group/pulse_cannon"]:
		return "fell back: %s" % [icons.fell_back]
	return ""


func test_a_refused_or_missing_file_still_draws_markers() -> String:
	for icons: HubIcons in [HubIcons.parse("[]"), HubIcons.load_file("res://data/hub/no_such_icons.json")]:
		if icons.error == "":
			return "a bad file was not refused"
		if icons.icon("component", "scrap_alloy").is_empty() or icons.numbers["size_m"] <= 0.0:
			return "a refused file gave no marker: %s" % icons.error
	return ""


func test_bad_icons_are_refused_naming_the_place() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubIcons.DEFAULT_FILE))
	var cases: Array = [
		["groups.weapon.pulse_cannon.parts[0] shape", {"shape": "star", "size": [0.2, 0.2], "at": [0, 0]}],
		["groups.weapon.pulse_cannon.parts[0] reaches", {"shape": "rect", "size": [0.6, 0.2], "at": [0.3, 0]}],
		["groups.weapon.pulse_cannon.parts[0] has an unknown key", {"shape": "rect", "size": [0.2, 0.2],
			"at": [0, 0], "glow": true}],
		["groups.weapon.pulse_cannon.parts[0] color", {"shape": "rect", "size": [0.2, 0.2], "at": [0, 0],
			"color": [2, 0, 0]}],
	]
	for case: Array in cases:
		var data: Dictionary = shipped.duplicate(true)
		data["groups"]["weapon"]["pulse_cannon"]["parts"][0] = case[1]
		var icons: HubIcons = HubIcons.parse(JSON.stringify(data))
		if not icons.error.begins_with(case[0]):
			return "expected \"%s...\", got \"%s\"" % [case[0], icons.error]
	var unknown: Dictionary = shipped.duplicate(true)
	unknown["groups"]["robots"] = {}
	if not HubIcons.parse(JSON.stringify(unknown)).error.begins_with("groups.robots"):
		return "an unknown group was not refused"
	var small: Dictionary = shipped.duplicate(true)
	small["size_m"] = 0.001
	if not HubIcons.parse(JSON.stringify(small)).error.contains("size_m"):
		return "a tiny icon size was not refused"
	return ""


func test_a_new_id_is_an_entry_in_the_file() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubIcons.DEFAULT_FILE))
	data["groups"]["weapon"]["test_blaster"] = {"color": [0.5, 0.5, 0.5], "parts": [
		{"shape": "disc", "size": [0.5, 0.5], "at": [0, 0]}]}
	var icons: HubIcons = HubIcons.parse(JSON.stringify(data))
	if icons.error != "" or not icons.has_icon("weapon", "test_blaster") or not icons.fell_back.is_empty():
		return "a new weapon's icon was not read: %s" % icons.error
	return ""
