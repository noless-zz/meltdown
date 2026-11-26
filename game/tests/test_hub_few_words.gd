extends RefCounted

## Fewer words at the home base (#1300, CRW-2, CRF-3, CRF-4, CMF-8, DEV-7,
## decision record 0012): short rows that fit `max_row_chars`, at most
## `max_rows_visible` on a screen scrolling with the selection, and a row's
## longer explanation only while it is selected. Apart from `test_hub_text.gd`
## so neither file grows past the size limit.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"
## Numbers that fill a row in the length test: wider than any a run reaches.
const WIDE_COUNT: int = 999
const WIDE_LEVEL: int = 99
const WIDE_TIER: int = 9
const WIDE_SEED: int = 2147483647
## Wider than any number a part file gives an upgrade's effect.
const WIDE_EFFECT: String = "-100%"
## Rows whose length is not the hub file's to bound: none since the Workbench
## shows one fact per line (#1367, #1353).
const LIST_ROWS: Array[String] = []


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _ship() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))


static func _roles() -> CrewRoles:
	return CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH))


static func _hub(profile: Profile) -> HubText:
	return HubText.new(HubModel.create(HubConfig.load_shipped(), profile, _roles(),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)), UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		Fitting.new(), _ship()))


## Lots of everything: every component, crew of every role, some upgrades built.
static func _rich_profile() -> Profile:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 20, "cell_salts": 20, "circuit_shards": 20, "core_glass": 20})
	var roles: CrewRoles = _roles()
	for i: int in roles.ids.size():
		profile.crew.append({"id": "crew-%d" % i, "role": roles.ids[i]})
	return profile


static func _longest(names: Array[String]) -> String:
	var best: String = ""
	for name: String in names:
		best = name if name.length() > best.length() else best
	return best


func test_the_file_sets_the_screen_limits() -> String:
	var shipped: HubConfig = HubConfig.load_shipped()
	if shipped.error != "" or shipped.max_rows_visible != 5 or shipped.max_row_chars != 28:
		return "shipped limits are %d rows, %d chars (%s)" % [shipped.max_rows_visible, shipped.max_row_chars, shipped.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	data.erase(HubConfig.KEY_MAX_ROWS)
	data.erase(HubConfig.KEY_MAX_CHARS)
	var bare: HubConfig = HubConfig.parse_json(JSON.stringify(data))
	if bare.error != "" or bare.max_rows_visible != HubConfig.DEFAULT_MAX_ROWS or bare.max_row_chars != HubConfig.DEFAULT_MAX_CHARS:
		return "a file without limits gives %d rows, %d chars (%s)" % [bare.max_rows_visible, bare.max_row_chars, bare.error]
	for bad: Variant in [0, 2.5, "5", -1]:
		data[HubConfig.KEY_MAX_ROWS] = bad
		if not HubConfig.parse_json(JSON.stringify(data)).error.contains(HubConfig.KEY_MAX_ROWS):
			return "max_rows_visible %s was accepted" % str(bad)
	return ""


## Every text the hub file holds, filled with the longest names the shipped
## data can put in it, fits `max_row_chars`. A slot row is filled per slot
## kind with the longest thing that kind can hold, since only that can show.
## The Workbench's rows hold one fact each (#1367): one component's cost, one
## number, one unlock, one reason, each filled with the longest the data gives.
func test_every_shipped_text_fits_a_row() -> String:
	var hub: HubText = _hub(Profile.new())
	var config: HubConfig = hub.model.config
	var words: HubWords = config.words
	var upgrades: Array[String] = []
	for upgrade: UpgradeDef in hub.model.tree.upgrades:
		upgrades.append(upgrade.display_name)
	var components: Array[String] = []
	for kind: ComponentDef in hub.model.components.kinds:
		components.append(kind.display_name)
	var roles: CrewRoles = _roles()
	var role_names: Array[String] = []
	var amounts: Array[int] = []
	for id: String in roles.ids:
		role_names.append(roles.role_name(id))
		amounts.append(roles.cap(roles.benefit_stat(id)))
	var slot_names: Array[String] = []
	for kind: String in HubWords.SLOT_KINDS:
		slot_names.append(words.slot_name(kind, 8))
	var stats: Array[String] = []
	stats.assign(words.stat_names.values())
	var filled: Dictionary[String, String] = {
		"name": _longest(upgrades), "role": _longest(role_names), "stat": _longest(stats),
		"amount": str(amounts.max()), "count": str(WIDE_COUNT), "tier": str(WIDE_TIER),
		"level": str(WIDE_LEVEL), "seed": str(WIDE_SEED), "part": _longest(_part_names(hub)),
		"have": str(WIDE_COUNT), "need": str(WIDE_COUNT),
		# A locker note names one upgrade, a move note one slot (#1336).
		"names": _longest(upgrades), "from": _longest(slot_names),
		# Ship summary numbers (#1357): wider than any ship file value or crew total.
		"current": str(WIDE_COUNT), "stock": str(WIDE_COUNT), "before": str(WIDE_COUNT), "after": str(WIDE_COUNT),
		"change": "+%d" % amounts.max(),
	}
	# One fact per Workbench line (#1367): one component's cost, one number, one reason.
	filled["cost"] = words.row("cost_item", {"name": _longest(components), "have": WIDE_COUNT, "need": WIDE_COUNT})
	var effects: Array[String] = []
	for key: String in words.effect_names:
		effects.append(words.effect(key, WIDE_EFFECT))
	filled["effect"] = _longest(effects)
	filled["reason"] = _longest([words.row("locked_needs", filled), words.row("locked_short", {"count": WIDE_COUNT,
		"name": _longest(components)})])
	var texts: Dictionary[String, String] = {"empty_crew": config.empty_crew, "empty_store": config.empty_store}
	for id: String in config.pages:
		texts["title " + id] = config.title(id)
	for key: String in HubWords.PLACEHOLDERS:
		if not LIST_ROWS.has(key) and key != "slot_row":
			texts[key] = words.row(key, filled)
	texts["store_row"] = words.row("store_row", {"name": _longest(components), "count": WIDE_COUNT})
	for slot: Dictionary in hub.model.fit_slots():
		texts["slot_row " + slot["slot"]] = _longest_slot_row(hub, slot, filled)
	for key: String in texts:
		if texts[key].length() > config.max_row_chars:
			return "%s \"%s\" has %d characters, more than %d" % [key, texts[key], texts[key].length(), config.max_row_chars]
	return ""


## The ship file's part ids, the way a slot row shows them.
static func _part_names(hub: HubText) -> Array[String]:
	var names: Array[String] = []
	var loadout: Dictionary = hub.model.ship_data.get(ShipTuning.LOADOUT_KEY, {})
	for kind: Variant in loadout:
		for part: Variant in loadout[kind]:
			names.append(str(part))
	return names


static func _longest_slot_row(hub: HubText, slot: Dictionary, filled: Dictionary) -> String:
	var words: HubWords = hub.model.config.words
	var fitted: Array[String] = [words.row("slot_empty"), words.row("slot_stock"),
		words.row("slot_part", {"part": filled["part"]})]
	for upgrade: UpgradeDef in hub.model.tree.upgrades:
		if upgrade.kind == HubText.FITS.get(slot["kind"], ""):
			fitted.append(words.row("slot_upgrade", {"name": upgrade.display_name}))
	var slot_name: String = words.slot_name(slot["kind"], slot["index"])
	return words.row("slot_row", {"slot": slot_name, "fitted": _longest(fitted)})


func test_only_the_selected_row_shows_its_explanation() -> String:
	var hub: HubText = _hub(Profile.new())
	while hub.page_id() != HubConfig.CRAFT:
		hub.turn_page(1)
	var locked: Array[Dictionary] = hub.model.locked()
	if locked.size() < 2 or hub.selected() != {"action": HubText.ACTION_CRAFT, "id": locked[0]["id"]}:
		return "an empty profile's Workbench does not start on a locked row: %s" % hub.selected()
	var first: String = hub.model.config.words.row("locked_note", {"reason": HubCraftRows.reason(hub.model, locked[0]["id"])})
	if hub.note() != first:
		return "the first locked row's note is \"%s\", expected \"%s\"" % [hub.note(), first]
	hub.move(1)
	var second: String = hub.model.config.words.row("locked_note", {"reason": HubCraftRows.reason(hub.model, locked[1]["id"])})
	if hub.note() == first or hub.note() != second:
		return "after a step down the note is \"%s\"" % hub.note()
	for line: String in hub.lines():
		if line.contains(first) or line.contains(second):
			return "a reason is a row of its own: \"%s\"" % line
	var cost: String = HubCraftRows.texts(HubCraftRows.cost_lines(hub.model, locked[0]["id"]))[0]
	var second_cost: String = HubCraftRows.texts(HubCraftRows.cost_lines(hub.model, locked[1]["id"]))[0]
	if (hub.lines().has(cost) and cost != second_cost) or not hub.lines().has(second_cost):
		return "the cost rows shown are not only the selected upgrade's: %s" % [hub.lines()]
	return ""


## Down through every page and station and back up: the selected row is always
## inside the shown window, the window never holds more than the limit, and
## stepping inside the window does not move it.
func test_scrolling_keeps_the_selection_on_screen() -> String:
	var hub: HubText = _hub(_rich_profile())
	var places: Array[String] = []
	for i: int in hub.model.pages().size():
		places.append("page")
	places.append_array(HubStationPages.STATIONS.keys())
	for i: int in places.size():
		if places[i] == "page":
			hub.leave_station()
			hub.page = i
			hub.move(-1000)
		else:
			hub.choose_station(places[i])
		var shown: int = hub.rows_shown()  # The bay's ship leaves fewer rows (#1366).
		var count: int = hub.lines().size() - 1
		for step: int in count * 2:
			var before: int = hub.first_shown()
			var was: int = hub.selected_line() - 1
			hub.move(1 if step < count else -1)
			var now: int = hub.selected_line() - 1
			var first: int = hub.first_shown()
			var rows_now: int = hub.lines().size() - 1  # Detail rows come and go with the selection.
			if now >= 0 and (now < first or now >= first + shown):
				return "%s %d: row %d selected, rows %d..%d shown" % [places[i], i, now, first, first + shown - 1]
			if first < 0 or (rows_now > shown and first > rows_now - shown) or (rows_now <= shown and first != 0):
				return "%s %d: window starts at %d of %d rows" % [places[i], i, first, rows_now]
			# The selection includes the detail rows under it (#1357).
			var end: int = hub.selection_end()
			if now >= before and end < before + shown and was >= before and was < before + shown and first != before:
				return "%s %d: the window moved from %d to %d inside it" % [places[i], i, before, first]
	if HubWindow.scrolled(0, 29, _flags(30, []), 8) != 22 or HubWindow.scrolled(22, 0, _flags(30, []), 8) != 0:
		return "the window does not follow the selection to the ends"
	if HubWindow.scrolled(10, 9, _flags(30, [8]), 5) != 8:
		return "the header above the selected row does not come into view"
	return ""


static func _flags(count: int, headers: Array[int]) -> Array[bool]:
	var flags: Array[bool] = []
	for i: int in count:
		flags.append(not headers.has(i))
	return flags


func test_rows_that_are_numbers_show_numbers() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"cell_salts": 7})
	profile.stats.runs_started = 12
	var hub: HubText = _hub(profile)
	var words: HubWords = hub.model.config.words
	while hub.page_id() != HubConfig.STATS:
		hub.turn_page(1)
	var runs: String = hub.lines()[1 + ProfileStats.KEYS.find("runs_started")]
	if runs != words.row("stats_runs_started", {"count": 12}) or not runs.ends_with("12") or runs.length() > 10:
		return "the runs row reads \"%s\"" % runs
	while hub.page_id() != HubConfig.STORE:
		hub.turn_page(1)
	var name: String = hub.model.components.get_kind("cell_salts").display_name
	if not hub.lines()[1].begins_with(name) or not hub.lines()[1].ends_with("7"):
		return "the locker row reads \"%s\", not the count beside \"%s\"" % [hub.lines()[1], name]
	return ""


## Shorter words, same actions: the Workbench still crafts every upgrade the
## model lists, the Fitting Bay still mounts, strips and launches, and the
## other pages do nothing when pressed.
func test_each_page_still_leads_to_the_same_actions() -> String:
	var profile: Profile = _rich_profile()
	var hub: HubText = _hub(profile)
	var crafted: Array[String] = hub.model.craftable()
	hub.model.craft(crafted[0])
	for i: int in hub.model.pages().size():
		hub.page = i
		hub.move(-1000)
		var actions: Array[Dictionary] = []
		for step: int in hub.lines().size():
			if hub.selected() != {} and not actions.has(hub.selected()):
				actions.append(hub.selected())
			hub.move(1)
		var expected: Array[Dictionary] = []
		match hub.page_id():
			HubConfig.CRAFT:
				var ids: Array[String] = hub.model.craftable()
				for entry: Dictionary in hub.model.locked():
					ids.append(entry["id"])
				for id: String in ids:
					expected.append({"action": HubText.ACTION_CRAFT, "id": id})
			HubConfig.FIT:
				for slot: Dictionary in hub.model.fit_slots():
					if HubText.FITS.get(slot["kind"], "") == hub.model.tree.get_upgrade(crafted[0]).kind:
						expected.append({"action": HubText.ACTION_FIT, "slot": slot["slot"], "id": crafted[0]})
				expected.append({"action": HubText.ACTION_LAUNCH})
		if actions != expected:
			return "page %s acts %s, expected %s" % [hub.page_id(), actions, expected]
	return ""
