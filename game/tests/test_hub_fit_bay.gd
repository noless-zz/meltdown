extends RefCounted

## The Fitting Bay as a ship with slots (#1366, CRF-4, CRF-5, CMB-1, CRW-2,
## ARC-3, ARC-4): slots placed on the drawn ship from `data/hub/hub.json`,
## fitting and removing by choosing a slot and then an item, an item fitted in
## one slot offered elsewhere as a move, at most five choices at once, and the
## same `HubModel` calls as the flat panel. The drawing is in
## `test_hub_fitting_view.gd`.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")


## A hub on the fit station whose profile has built every weapon and part it can.
static func _built_hub() -> HubText:
	var hub: HubText = Stations._hub(Stations._rich_profile())
	hub.model.parts = HubPartInfo.load_shipped()  # As the hub wiring sets them, so fits have numbers.
	hub.model.profile.bank({"scrap_alloy": 400, "cell_salts": 400, "circuit_shards": 400, "core_glass": 400})
	var more: bool = true
	while more:
		more = false
		for id: String in hub.model.craftable():
			if hub.model.craft(id) == "":
				more = true
	hub.choose_station(HubFitBay.STATION)
	return hub


## A weapon the profile has built, or "".
static func _weapon(hub: HubText) -> String:
	for id: String in hub.model.crafted():
		if hub.model.tree.get_upgrade(id).kind == "weapon":
			return id
	return ""


## Selects the row whose action is `want`; false when none is.
static func _select(hub: HubText, want: Dictionary) -> bool:
	hub.move(-1000)
	for i: int in 300:
		if hub.selected() == want:
			return true
		var line: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == line:
			return false
	return false


## Chooses `slot` on the ship, then presses the item row doing `want`.
static func _fit(hub: HubText, slot: String, want: Dictionary) -> String:
	if not _select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": slot}):
		return "no row chooses %s: %s" % [slot, hub.lines()]
	hub.press()
	if hub.fit_slot != slot:
		return "pressing %s chose \"%s\"" % [slot, hub.fit_slot]
	if not _select(hub, want):
		return "%s does not offer %s: %s" % [slot, want, hub.lines()]
	return hub.press()


func test_the_shipped_file_places_every_slot_on_the_ship() -> String:
	var hub: HubText = _built_hub()
	var layout: HubFitLayout = hub.model.config.fit_layout
	if not layout.has_ship():
		return "the hub file draws no ship: %s" % layout.error
	var outline: PackedVector2Array = PackedVector2Array(layout.outline)
	var placed: Array[Vector2] = []
	for slot: Dictionary in hub.model.fit_slots():
		var at: Variant = layout.position_of(slot["kind"], slot["index"])
		if at == null:
			return "%s has no place on the ship" % slot["slot"]
		if not Geometry2D.is_point_in_polygon(at, outline):
			return "%s at %s is off the ship" % [slot["slot"], at]
		for other: Vector2 in placed:
			if other.distance_to(at) < layout.slot_size_m:
				return "%s at %s overlaps a slot at %s" % [slot["slot"], at, other]
		placed.append(at)
	var drawn: Array = hub.drawing()["slots"]
	if drawn.size() != hub.model.fit_slots().size():
		return "the drawing has %d slots, the ship %d" % [drawn.size(), hub.model.fit_slots().size()]
	return ""


func test_a_bad_ship_section_is_refused_by_name() -> String:
	var cases: Dictionary = {
		"unknown key": {"wings": 2},
		"outline": {"outline": [[0.0, 0.0], [0.1, 0.0]]},
		"slots.turret": {"slots": {"turret": [[0.0, 0.0]]}},
		"hull_color": {"hull_color": [2.0, 0.0, 0.0]},
		"further than": {"slots": {"engine": [[0.9, 0.0]]}},
	}
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))[HubFitLayout.KEY]
	if HubFitLayout.parse(good).error != "":
		return "the shipped section is refused: %s" % HubFitLayout.parse(good).error
	for want: String in cases:
		var section: Dictionary = good.duplicate(true)
		section.merge(cases[want], true)
		var layout: HubFitLayout = HubFitLayout.parse(section)
		if layout.error.find(want) < 0 or layout.has_ship():
			return "a section with %s gives \"%s\"" % [cases[want], layout.error]
	return ""


func test_fitting_is_a_slot_then_an_item_through_the_same_model() -> String:
	var hub: HubText = _built_hub()
	var weapon: String = _weapon(hub)
	var direct: HubModel = _built_hub().model
	if weapon == "" or direct.fit("primary[1]", weapon) != "":
		return "no weapon to fit"
	var reason: String = _fit(hub, "primary[1]", {"action": HubText.ACTION_FIT, "slot": "primary[1]", "id": weapon})
	if reason != "":
		return "mounting gave \"%s\"" % reason
	if hub.model.fitting.to_json() != direct.fitting.to_json():
		return "the bay fitted %s, the model's own fit %s" % [hub.model.fitting.to_json(), direct.fitting.to_json()]
	if hub.fit_slot != "" or str(hub.selected().get("slot", "")) != "primary[1]":
		return "after the mount the bay is on \"%s\" with %s selected" % [hub.fit_slot, hub.selected()]
	var drawn: Dictionary = _drawn_slot(hub, "primary[1]")
	if drawn.get("icon", {}) != HubFitBay.upgrade_icon(hub.model, weapon) or not drawn.get("selected", false):
		return "the ship draws primary[1] as %s" % [drawn]
	return ""


func test_removing_goes_back_to_an_empty_mark() -> String:
	var hub: HubText = _built_hub()
	var weapon: String = _weapon(hub)
	hub.model.fit("primary[1]", weapon)
	hub.choose_station(HubFitBay.STATION)
	var reason: String = _fit(hub, "primary[1]", {"action": HubText.ACTION_FIT, "slot": "primary[1]", "id": ""})
	if reason != "" or hub.model.fitting.primary[1] != "":
		return "emptying gave \"%s\", leaving %s" % [reason, hub.model.fitting.primary]
	if not (_drawn_slot(hub, "primary[1]").get("icon", {"x": 1}) as Dictionary).is_empty():
		return "the emptied slot still draws %s" % [_drawn_slot(hub, "primary[1]")]
	return ""


func test_an_item_fitted_in_one_slot_is_offered_elsewhere_as_a_move() -> String:
	var hub: HubText = _built_hub()
	var weapon: String = _weapon(hub)
	hub.model.fit("primary[0]", weapon)
	hub.choose_station(HubFitBay.STATION)
	_select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "primary[1]"})
	hub.press()
	if _select(hub, {"action": HubText.ACTION_FIT, "slot": "primary[1]", "id": weapon}):
		return "%s is offered as a second mount" % weapon
	hub.choose_station(HubFitBay.STATION)
	var reason: String = _fit(hub, "primary[1]", {"action": HubText.ACTION_MOVE, "slot": "primary[1]", "id": weapon})
	if reason != "" or hub.model.fitting.primary != (["", weapon] as Array[String]):
		return "the move gave \"%s\", leaving %s" % [reason, hub.model.fitting.primary]
	return ""


func test_stick_left_steps_back_to_the_ship_on_the_chosen_slot() -> String:
	var hub: HubText = _built_hub()
	if hub.back():
		return "back() on the ship claims to have stepped back"
	_select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "utility[0]"})
	hub.press()
	if hub.fit_slot != "utility[0]" or not hub.back() or hub.fit_slot != "" \
			or str(hub.selected().get("slot", "")) != "utility[0]":
		return "back from utility[0] left \"%s\" with %s selected" % [hub.fit_slot, hub.selected()]
	return ""


func test_at_most_five_choices_show_and_the_rest_scroll() -> String:
	var hub: HubText = _built_hub()
	_select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "primary[0]"})
	hub.press()
	var offered: int = 0
	for entry: Dictionary in HubFitBay.rows(hub.model, "primary[0]"):
		offered += 1 if entry["selectable"] else 0
	if offered <= 5:
		return "the profile offers only %d weapons, too few to scroll" % offered
	if hub.rows_shown() > 5:
		return "the item list shows %d rows" % hub.rows_shown()
	for i: int in offered:
		var first: int = hub.first_shown()
		var at: int = hub.selected_line() - 1
		if at < first or at >= first + hub.rows_shown():
			return "item %d is selected but rows %d..%d show" % [i, first, first + hub.rows_shown() - 1]
		hub.move(1)
	return ""


func test_the_highlighted_item_shows_its_before_and_after() -> String:
	var hub: HubText = _built_hub()
	var engine: String = ""
	var changes: Array[Dictionary] = []
	for id: String in hub.model.crafted():
		if engine == "" and hub.model.tree.get_upgrade(id).kind == "engine":
			changes = hub.model.preview({"action": HubText.ACTION_FIT, "slot": "engine", "id": id})
			engine = id if not changes.is_empty() else ""
	var mount: Dictionary = {"action": HubText.ACTION_FIT, "slot": "engine", "id": engine}
	if engine == "" or changes.is_empty():
		return "no engine part changes anything"
	_select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "engine"})
	hub.press()
	_select(hub, mount)
	var shown: Array[String] = []
	shown.assign(hub.lines().slice(1 + hub.first_shown(), 1 + hub.first_shown() + hub.rows_shown()))
	var want: String = HubSummaryRows.change_text(hub.model.config.words, changes[0])
	if not shown.has(want):
		return "with %s highlighted the screen shows %s, not \"%s\"" % [engine, shown, want]
	if hub.model.fitting.parts["engine"] != "":
		return "highlighting fitted the part"
	return ""


func test_pointing_on_the_ship_selects_the_slot_there() -> String:
	var hub: HubText = _built_hub()
	var at: Vector2 = hub.model.config.fit_layout.position_of("utility", 1)
	if hub.point_slot(at + Vector2(0.005, 0.0)) != "utility[1]" or str(hub.selected().get("slot", "")) != "utility[1]":
		return "pointing at utility[1] selected %s" % [hub.selected()]
	if hub.point_slot(Vector2(0.29, 0.29)) != "" or str(hub.selected().get("slot", "")) != "utility[1]":
		return "pointing off the ship changed the selection to %s" % [hub.selected()]
	hub.press()
	if hub.point_slot(at) != "":
		return "pointing while choosing an item picked a slot"
	return ""


## The drawing's entry for `slot`, or {}.
static func _drawn_slot(hub: HubText, slot: String) -> Dictionary:
	for each: Dictionary in hub.drawing().get("slots", []):
		if each["slot"] == slot:
			return each
	return {}
