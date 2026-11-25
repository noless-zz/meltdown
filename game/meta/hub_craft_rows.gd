class_name HubCraftRows
extends RefCounted

## The Workbench page's rows (CRF-3, CRF-6, CRW-2, #1317): under each upgrade
## that can be built or is out of reach, what it costs beside what is held of
## each component, what it does in numbers from its part file, and what it
## unlocks next, all by name. A locked row says why in words, in its note
## under it while it is selected (#1300). Every word comes
## from `data/hub/hub.json` (ARC-4); the rules of crafting stay `UpgradeTree`'s,
## so a row is locked exactly when `HubModel.locked` lists it.


## Every row of the Workbench page, shaped as `HubText` rows.
static func rows(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	var ready: Array[String] = model.craftable()
	if not ready.is_empty():
		out.append(_shown(words.row("ready_header")))
	for id: String in ready:
		out.append(_acting(words.row("ready_row", {"name": upgrade_name(model, id)}), id))
		out.append_array(_details(model, id))
	var locked: Array[Dictionary] = model.locked()
	if not locked.is_empty():
		out.append(_shown(words.row("locked_header")))
	for entry: Dictionary in locked:
		var id: String = entry["id"]
		var row: Dictionary = _acting(words.row("locked_row", {"name": upgrade_name(model, id)}), id)
		row["note"] = words.row("locked_note", {"reason": reason(model, id)})  # Only while selected (#1300).
		out.append(row)
		out.append_array(_details(model, id))
	var built: Array[String] = model.crafted()
	if not built.is_empty():
		out.append(_shown(words.row("built_header")))
	for id: String in built:
		out.append({"text": words.row("built_row", {"name": upgrade_name(model, id)}), "action": {}, "selectable": true})
	return out


## Why upgrade `id` cannot be built now, in words: the first upgrade it needs
## built first, else every component it is short of. "" when it can be built.
static func reason(model: HubModel, id: String) -> String:
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	if upgrade == null or model.tree.missing(id, model.profile.crafted, model.profile.banked) == "":
		return ""
	var words: HubWords = model.config.words
	for required: String in upgrade.requires:
		if not model.profile.crafted.has(required):
			return words.row("locked_needs", {"name": upgrade_name(model, required)})
	var short: Array[String] = []
	for component: String in upgrade.cost:
		var lacking: int = upgrade.cost[component] - int(model.profile.banked.get(component, 0))
		if lacking > 0:
			short.append(words.row("locked_short", {"count": lacking, "name": component_name(model, component)}))
	return words.row("list_join").join(short)


## The cost row's text: each component of the cost with what is held of it.
static func cost_text(model: HubModel, id: String) -> String:
	var words: HubWords = model.config.words
	var items: Array[String] = []
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	if upgrade == null:
		return ""
	for component: String in upgrade.cost:
		items.append(words.row("cost_item", {"name": component_name(model, component),
			"have": int(model.profile.banked.get(component, 0)), "need": upgrade.cost[component]}))
	return words.row("cost_row", {"cost": words.row("list_join").join(items)})


## The effect row's text, or "" when no part file gives a number the hub file names.
static func effect_text(model: HubModel, id: String) -> String:
	var words: HubWords = model.config.words
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	if upgrade == null:
		return ""
	var items: Array[String] = []
	for entry: Dictionary in model.parts.effects(upgrade):
		var shown: String = words.effect(entry["key"], _number(entry["value"], entry["multiplier"]))
		if shown != "":
			items.append(shown)
	return words.row("effect_row", {"effect": words.row("list_join").join(items)}) if not items.is_empty() else ""


## The unlocks row's text, or "" when nothing requires upgrade `id`.
static func unlocks_text(model: HubModel, id: String) -> String:
	var names: Array[String] = []
	for upgrade: UpgradeDef in model.ordered_upgrades():
		if upgrade.requires.has(id):
			names.append(upgrade.display_name)
	if names.is_empty():
		return ""
	var words: HubWords = model.config.words
	return words.row("unlocks_row", {"names": words.row("list_join").join(names)})


## The upgrade's name from its data file, or "" when the tree lacks it, so an
## id never stands in for a name.
static func upgrade_name(model: HubModel, id: String) -> String:
	return model.tree.get_upgrade(id).display_name if model.tree.has_upgrade(id) else ""


## The component's name from its data file, or "" when no file describes it.
static func component_name(model: HubModel, id: String) -> String:
	var kind: ComponentDef = model.components.get_kind(id)
	return kind.display_name if kind != null else ""


## A multiplier as a signed whole percent ("+40%", "-15%"); any other number
## whole when it is, else to one decimal.
static func _number(value: float, multiplier: bool) -> String:
	if multiplier:
		var percent: int = roundi((value - 1.0) * 100.0)
		return ("+%d%%" if percent >= 0 else "%d%%") % percent
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value


static func _details(model: HubModel, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for text: String in [cost_text(model, id), effect_text(model, id), unlocks_text(model, id)]:
		if text != "":
			var detail: Dictionary = _shown(text)
			detail["detail_of"] = id  # `HubText` shows it only while `id` is selected (#1300).
			out.append(detail)
	return out


static func _acting(text: String, id: String) -> Dictionary:
	return {"text": text, "action": {"action": HubText.ACTION_CRAFT, "id": id}, "selectable": true}


static func _shown(text: String) -> Dictionary:
	return {"text": text, "action": {}, "selectable": false}
