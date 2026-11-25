extends RefCounted

## The hub's rows after the owner's playtest of 23 Nov (#1336, CRF-3, CRF-4,
## CRF-5, CRW-1, CRW-2, ARC-4): the Fitting Bay offers a fitted upgrade
## elsewhere only as a move that says where it is now, Crew Quarters shows one
## row per role with the total, and the Parts Locker says what each component
## is for.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _roles() -> CrewRoles:
	return CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH))


static func _hub(profile: Profile) -> HubText:
	return HubText.new(HubModel.create(HubConfig.load_shipped(), profile, _roles(),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)), UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		Fitting.new(), JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))))


static func _to_page(hub: HubText, id: String) -> void:
	while hub.page_id() != id:
		hub.turn_page(1)


## Every action of the current page's rows.
static func _actions(hub: HubText) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	hub.move(-1000)
	for i: int in 200:
		out.append(hub.selected())
		var before: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == before:
			break
	return out


static func _crew(roles: Array[String]) -> Profile:
	var profile: Profile = Profile.new()
	for i: int in roles.size():
		profile.crew.append({"id": "crew-%d" % i, "role": roles[i]})
	return profile


func test_a_fitted_weapon_is_offered_elsewhere_only_as_a_move() -> String:
	var profile: Profile = Profile.new()
	profile.crafted.append("needle_gun")
	var hub: HubText = _hub(profile)
	_to_page(hub, HubConfig.FIT)
	var mount_1: Dictionary = {"action": HubText.ACTION_FIT, "slot": "primary[1]", "id": "needle_gun"}
	if not _actions(hub).has(mount_1):
		return "before mounting, Primary 2 offers no mount: %s" % [hub.lines()]
	if hub.model.fit("primary[0]", "needle_gun") != "":
		return "mount refused"
	var actions: Array[Dictionary] = _actions(hub)
	for action: Dictionary in actions:
		if action.get("action") == HubText.ACTION_FIT and action.get("id") == "needle_gun":
			return "a fitted weapon is still offered as a mount: %s" % action
	if not actions.has({"action": HubText.ACTION_MOVE, "slot": "primary[1]", "id": "needle_gun"}):
		return "Primary 2 offers no move: %s" % [hub.lines()]
	var words: HubWords = hub.model.config.words
	var row: String = words.row("move_option_row", {"name": "Needle Gun"})
	if not hub.lines().has(row):
		return "no line \"%s\" in %s" % [row, hub.lines()]
	hub.move(-1000)
	for i: int in 200:
		if hub.selected().get("action") == HubText.ACTION_MOVE:
			break
		hub.move(1)
	var where: String = words.row("move_note", {"from": words.slot_name("primary", 0)})
	return "" if hub.note() == where else "the move row's note is \"%s\", expected \"%s\"" % [hub.note(), where]


func test_pressing_the_move_row_moves_the_weapon() -> String:
	var profile: Profile = Profile.new()
	profile.crafted.append("needle_gun")
	var hub: HubText = _hub(profile)
	_to_page(hub, HubConfig.FIT)
	if hub.model.fit("primary[0]", "needle_gun") != "":
		return "mount refused"
	hub.move(-1000)
	for i: int in 200:
		if hub.selected().get("action") == HubText.ACTION_MOVE:
			break
		hub.move(1)
	if hub.selected() != {"action": HubText.ACTION_MOVE, "slot": "primary[1]", "id": "needle_gun"}:
		return "no move row selected: %s" % hub.selected()
	var reason: String = hub.press()
	if reason != "" or hub.model.fitting.primary != (["", "needle_gun"] as Array[String]):
		return "the press gave \"%s\", primary %s" % [reason, hub.model.fitting.primary]
	return ""


func test_crew_groups_count_each_role_once_with_the_total() -> String:
	var groups: Array[Dictionary] = CrewGroups.of(
		_crew(["reactor_hand", "cargo_rigger", "reactor_hand"] as Array[String]), _roles())
	if groups.size() != 2 or groups[0]["role"] != "reactor_hand" or groups[1]["role"] != "cargo_rigger":
		return "groups are %s" % [groups]
	if groups[0]["count"] != 2 or groups[0]["total"] != 10 or groups[0]["capped"]:
		return "reactor hands are %s" % groups[0]
	if groups[1]["count"] != 1 or groups[1]["total"] != 1:
		return "the rigger is %s" % groups[1]
	return ""


func test_a_group_past_its_cap_shows_the_capped_total() -> String:
	var groups: Array[Dictionary] = CrewGroups.of(
		_crew(["cargo_rigger", "cargo_rigger", "cargo_rigger"] as Array[String]), _roles())
	if groups.size() != 1 or groups[0]["count"] != 3 or groups[0]["total"] != 2 or not groups[0]["capped"]:
		return "riggers are %s" % [groups]
	var totals: Dictionary = CrewBenefits.totals(_crew(["cargo_rigger", "cargo_rigger", "cargo_rigger"] as Array[String]), _roles())
	return "" if totals.get("salvage_slots") == groups[0]["total"] else "the run gets %s" % [totals]


func test_crew_quarters_shows_one_row_per_role_with_the_total_as_its_note() -> String:
	var hub: HubText = _hub(_crew(["cargo_rigger", "shield_tech", "cargo_rigger", "cargo_rigger"] as Array[String]))
	_to_page(hub, HubConfig.CREW)
	var words: HubWords = hub.model.config.words
	var riggers: String = words.row("crew_capped_row", {"role": "Cargo Rigger", "count": 3})
	var tech: String = words.row("crew_row", {"role": "Shield Technician", "count": 1})
	var expected: Array[String] = [hub.model.page_title(HubConfig.CREW), riggers, tech]
	if hub.lines() != expected:
		return "crew page is %s, expected %s" % [hub.lines(), expected]
	var capped: String = words.row("crew_note", {"amount": 2, "stat": words.stat_name("salvage_slots")})
	if hub.note() != capped:
		return "the riggers' note is \"%s\", expected \"%s\"" % [hub.note(), capped]
	hub.move(1)
	var shield: String = words.row("crew_note", {"amount": 5, "stat": words.stat_name("shield_max")})
	return "" if hub.note() == shield else "the technician's note is \"%s\"" % hub.note()


func test_the_shipped_crew_row_reads_as_the_issue_asks() -> String:
	var words: HubWords = HubConfig.load_shipped().words
	var line: String = "%s: %s" % [words.row("crew_row", {"role": "Cargo Rigger", "count": 3}),
		words.row("crew_note", {"amount": 3, "stat": "salvage slots"})]
	return "" if line == "Cargo Rigger ×3: +3 salvage slots" else "the row and note read \"%s\"" % line


func test_component_uses_name_the_upgrades_that_cost_it() -> String:
	var tree: UpgradeTree = UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR))
	var names: Array[String] = ComponentUses.names(tree.upgrades, "core_glass")
	var expected: Array[String] = []
	for upgrade: UpgradeDef in tree.upgrades:
		if upgrade.cost.has("core_glass"):
			expected.append(upgrade.display_name)
	if names.is_empty() or names != expected:
		return "core_glass is used by %s, expected %s" % [names, expected]
	return "" if ComponentUses.names(tree.upgrades, "nothing_costs_this").is_empty() else "an unused id has uses"


func test_the_parts_locker_note_says_what_each_component_is_for() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 3, "mystery_ore": 1})
	var hub: HubText = _hub(profile)
	_to_page(hub, HubConfig.STORE)
	var words: HubWords = hub.model.config.words
	var used: Array[String] = ComponentUses.names(hub.model.ordered_upgrades(), "scrap_alloy")
	if used.size() <= ComponentUses.SHOWN:
		return "scrap alloy has only %d uses; the test expects more than %d" % [used.size(), ComponentUses.SHOWN]
	var scrap: String = words.row("store_uses_more", {"names": words.row("list_join").join(used.slice(0, ComponentUses.SHOWN)),
		"count": used.size() - ComponentUses.SHOWN})
	var notes: Dictionary[String, String] = {}
	hub.move(-1000)
	for i: int in 10:
		notes[hub.lines()[hub.selected_line()]] = hub.note()
		hub.move(1)
	var row: String = words.row("store_row", {"name": "Scrap Alloy", "count": 3})
	if notes.get(row, "") != scrap:
		return "the Scrap Alloy note is \"%s\", expected \"%s\" (%s)" % [notes.get(row, ""), scrap, notes]
	if notes.get(words.row("store_row", {"name": "mystery_ore", "count": 1}), "") != words.row("store_unused"):
		return "the unknown component's note is not the unused words: %s" % [notes]
	return ""
