extends RefCounted

## The `hub_stations` check's Workbench walk (#1394, #1317, CRF-3, CRW-2,
## DEV-6): it asks for what the Workbench shows since #1351 (a cost under the
## selected upgrade only), on the shipped data files through a bare `HubText`.

const Fixtures: GDScript = preload("res://tests/test_hub_model.gd")


static func _model(profile: Profile) -> HubModel:
	var model: HubModel = Fixtures.new_model(profile, Fitting.new())
	model.parts = HubPartInfo.load_shipped()
	return model


static func _workbench(model: HubModel) -> HubText:
	var text: HubText = HubText.new(model)
	text.page = model.pages().find(HubConfig.CRAFT)
	return text


## Banked enough for some upgrades and not others, so the Workbench lists both
## buildable and locked ones.
static func _profile() -> Profile:
	var profile: Profile = Profile.new()
	profile.bank({"cell_salts": 2, "scrap_alloy": 5})
	return profile


static func _walk(text: HubText) -> Dictionary[String, Array]:
	return AcceptanceWorkbenchCosts.walk(text, text.lines, func(delta: int) -> void: text.move(delta))


func test_the_walk_selects_every_buildable_and_locked_upgrade() -> String:
	var model: HubModel = _model(_profile())
	if model.craftable().is_empty() or model.locked().size() < 1 or model.craftable().size() + model.locked().size() < 2:
		return "the fixture needs buildable and locked upgrades: %s, %s" % [model.craftable(), model.locked()]
	var text: HubText = _workbench(model)
	text.move(3)  # The walk starts from wherever the selection is.
	var seen: Dictionary[String, Array] = _walk(text)
	for id: String in model.craftable():
		if not seen.has(id):
			return "the walk never selected buildable %s: %s" % [id, seen.keys()]
	for entry: Dictionary in model.locked():
		if not seen.has(str(entry["id"])):
			return "the walk never selected locked %s: %s" % [entry["id"], seen.keys()]
	return ""


func test_the_shipped_workbench_passes_the_walk() -> String:
	var model: HubModel = _model(_profile())
	var verdict: String = AcceptanceWorkbenchCosts.judge(model, _walk(_workbench(model)))
	return "" if verdict == "" else "the shipped Workbench fails the walk: %s" % verdict


func test_only_the_selected_upgrade_shows_its_cost() -> String:
	# Why the old check failed (#1394): with details under the selected row only,
	# all costs never show at once, yet each shows in turn.
	var model: HubModel = _model(_profile())
	var seen: Dictionary[String, Array] = _walk(_workbench(model))
	var ids: Array[String] = model.craftable()
	for entry: Dictionary in model.locked():
		ids.append(entry["id"])
	var first: Array = seen[ids[0]]
	var other: String = AcceptanceWorkbenchCosts.cost_line(model, ids[1])
	if AcceptanceWorkbenchCosts.cost_line(model, ids[0]) == other:
		return "the fixture's first two upgrades cost the same: %s" % other
	if first.has(other):
		return "%s's cost shows while %s is selected: %s" % [ids[1], ids[0], first]
	return ""


func test_a_missing_cost_is_named() -> String:
	var model: HubModel = _model(_profile())
	var seen: Dictionary[String, Array] = _walk(_workbench(model))
	var id: String = model.craftable()[0]
	seen[id] = ["Workbench"]
	var verdict: String = AcceptanceWorkbenchCosts.judge(model, seen)
	var name: String = HubCraftRows.upgrade_name(model, id)
	if not verdict.contains("no cost for %s" % name):
		return "a cost left off the screen reads \"%s\"" % verdict
	return ""


func test_an_upgrade_never_selected_is_named() -> String:
	var model: HubModel = _model(_profile())
	var seen: Dictionary[String, Array] = _walk(_workbench(model))
	var id: String = str(model.locked()[0]["id"])
	seen.erase(id)
	var verdict: String = AcceptanceWorkbenchCosts.judge(model, seen)
	if not verdict.contains("never selects %s" % HubCraftRows.upgrade_name(model, id)):
		return "an unselected upgrade reads \"%s\"" % verdict
	return ""


func test_built_upgrades_are_not_asked_for_a_cost() -> String:
	var profile: Profile = _profile()
	var model: HubModel = _model(profile)
	var built: String = model.craftable()[0]
	if model.craft(built) != "":
		return "could not build %s for the fixture" % built
	var seen: Dictionary[String, Array] = _walk(_workbench(model))
	if seen.has(built):
		return "the walk asked built %s for a cost" % built
	var verdict: String = AcceptanceWorkbenchCosts.judge(model, seen)
	return "" if verdict == "" else "after one build the walk fails: %s" % verdict
