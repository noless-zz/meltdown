class_name HubCraftRows
extends RefCounted

## The Workbench page's rows (CRF-3, CRF-6, CRW-2, #1317): under each upgrade
## that can be built or is out of reach, what it costs beside what is held of
## each component, what it does in numbers from its part file, and what it
## unlocks next, all by name, one fact per line (#1367). A locked row says why in words, in its note
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
		out.append_array(details(model, id))
	var locked: Array[Dictionary] = model.locked()
	if not locked.is_empty():
		out.append(_shown(words.row("locked_header")))
	for entry: Dictionary in locked:
		var id: String = entry["id"]
		var row: Dictionary = _acting(words.row("locked_row", {"name": upgrade_name(model, id)}), id)
		row["note"] = words.row("locked_note", {"reason": reason(model, id)})  # Only while selected (#1300).
		out.append(row)
		out.append_array(details(model, id))
	var built: Array[String] = model.crafted()
	if not built.is_empty():
		out.append(_shown(words.row("built_header")))
	for id: String in built:
		out.append({"text": words.row("built_row", {"name": upgrade_name(model, id)}), "action": {}, "selectable": true})
	return out


## Why upgrade `id` cannot be built now, in words, one fact (#1367): the first
## upgrade it needs built first, else the first component it is short of; its
## cost lines say the rest. "" when it can be built.
static func reason(model: HubModel, id: String) -> String:
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	if upgrade == null or model.tree.missing(id, model.profile.crafted, model.profile.banked) == "":
		return ""
	var words: HubWords = model.config.words
	for required: String in upgrade.requires:
		if not model.profile.crafted.has(required):
			return words.row("locked_needs", {"name": upgrade_name(model, required)})
	for component: String in upgrade.cost:
		var lacking: int = upgrade.cost[component] - int(model.profile.banked.get(component, 0))
		if lacking > 0:
			return words.row("locked_short", {"count": lacking, "name": component_name(model, component)})
	return ""


## The cost, one line per component with what is held of it (#1367: one fact
## per line), each with the component's icon (`HubIcons` group and id).
static func cost_lines(model: HubModel, id: String) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	if upgrade == null:
		return out
	for component: String in upgrade.cost:
		var item: String = words.row("cost_item", {"name": component_name(model, component),
			"have": int(model.profile.banked.get(component, 0)), "need": upgrade.cost[component]})
		out.append({"text": words.row("cost_row", {"cost": item}), "icon": {"group": "component", "id": component}})
	return out


## What the upgrade does, one line per number a part file gives and the hub
## file names, each with the icon `HubTreeLayout.effect_icons` gives its key,
## else the upgrade's own.
static func effect_lines(model: HubModel, id: String) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	var upgrade: UpgradeDef = model.tree.get_upgrade(id)
	if upgrade == null:
		return out
	var icons: Dictionary[String, String] = model.config.craft_tree.effect_icons
	for entry: Dictionary in model.parts.effects(upgrade):
		var shown: String = words.effect(entry["key"], _number(entry["value"], entry["multiplier"]))
		if shown != "":
			var icon: Dictionary = {"group": "attribute", "id": icons[entry["key"]]} if icons.has(entry["key"]) \
				else HubFitBay.upgrade_icon(model, id)
			out.append({"text": words.row("effect_row", {"effect": shown}), "icon": icon})
	return out


## What building it unlocks, one line per upgrade that requires it, with its icon.
static func unlocks_lines(model: HubModel, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for upgrade: UpgradeDef in model.ordered_upgrades():
		if upgrade.requires.has(id):
			out.append({"text": model.config.words.row("unlocks_row", {"names": upgrade.display_name}),
				"icon": HubFitBay.upgrade_icon(model, upgrade.id)})
	return out


## The detail rows under upgrade `id`: its cost, effect and unlocks lines,
## shown only while it is selected (`detail_of`, #1300), each with its `icon`.
static func details(model: HubModel, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: Dictionary in cost_lines(model, id) + effect_lines(model, id) + unlocks_lines(model, id):
		var detail: Dictionary = _shown(line["text"])
		detail["detail_of"] = id  # `HubText` shows it only while `id` is selected (#1300).
		detail["icon"] = line["icon"]
		out.append(detail)
	return out


## The texts of `lines` (`cost_lines`, `effect_lines`, `unlocks_lines`).
static func texts(lines: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for line: Dictionary in lines:
		out.append(line["text"])
	return out


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


static func _acting(text: String, id: String) -> Dictionary:
	return {"text": text, "action": {"action": HubText.ACTION_CRAFT, "id": id}, "selectable": true}


static func _shown(text: String) -> Dictionary:
	return {"text": text, "action": {}, "selectable": false}
