class_name HubFitRows
extends RefCounted

## The Fitting Bay page's rows (CRF-4, CRW-2, RUN-8), kept apart from
## `HubText` so each file stays small. Each slot with what it holds, the
## crafted upgrades of its kind it could take, and a row to empty a fitted
## slot. One crafted upgrade is one item (#1336): one fitted nowhere is offered
## as a mount, one fitted in another slot as a move that names where it is now.
## Under a mount or move, while it is selected, the attributes it would change
## as before and after (#1357). Then one row strips the whole ship to stock
## and the ship summary follows (#1357).
## While a suspended run waits, a row to resume it (#1106) sits directly above
## the launch row, so the two ways into the mine are side by side (owner's
## decision, #1172); the launch row's note says launching discards the waiting run.


static func rows(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	var waiting: Dictionary = model.waiting()
	var built: Array[String] = model.crafted()
	for slot: Dictionary in model.fit_slots():
		out.append(HubRows.info(slot_line(model, slot)))
		out.append_array(choices(model, slot, built))
	out.append_array(strip_rows(model))
	out.append_array(HubSummaryRows.rows(model))
	if not waiting.is_empty():
		out.append(HubRows.grouped(HubRows.noted(HubRows.acting(words.row("resume_row", waiting), {"action": HubText.ACTION_RESUME}),
			words.row("resume_note", waiting)), HubStationPages.GROUP_RESUME))
	var launch: Dictionary = HubRows.acting(words.row("launch_row"), {"action": HubText.ACTION_LAUNCH})
	if not waiting.is_empty():
		HubRows.noted(launch, words.row("launch_discard_note"))
	out.append(HubRows.grouped(launch, HubStationPages.GROUP_LAUNCH))
	return out


## "Primary 1: Pulse Cannon": the slot's name and what is in it (`fit_slots` row).
static func slot_line(model: HubModel, slot: Dictionary) -> String:
	var words: HubWords = model.config.words
	var fitted: String = words.row("slot_empty")
	if slot["upgrade"] != "":
		fitted = words.row("slot_upgrade", {"name": _name(model, slot["upgrade"])})
	elif slot["part"] != "":
		var part: String = model.parts.weapon_name(slot["part"])
		fitted = words.row("slot_part", {"part": part}) if part != "" else words.row("slot_stock")
	elif Fitting.PART_KEYS.has(slot["kind"]):
		fitted = words.row("slot_stock")
	return words.row("slot_row", {"slot": words.slot_name(slot["kind"], slot["index"]), "fitted": fitted})


## What `slot` (a `fit_slots` row) can take, given the crafted upgrades
## `built`: a mount or move row per upgrade of its kind not already in it, each
## followed by its before and after, then a row to empty it when it holds one.
static func choices(model: HubModel, slot: Dictionary, built: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in built:
		if id != slot["upgrade"] and model.tree.get_upgrade(id).kind == HubText.FITS.get(slot["kind"], ""):
			var option: Dictionary = _option(model, slot["slot"], id)
			out.append(option)
			out.append_array(HubSummaryRows.change_rows(model, option["action"]))
	if slot["upgrade"] != "":
		out.append(HubRows.acting(model.config.words.row("clear_row"), {"action": HubText.ACTION_FIT, "slot": slot["slot"], "id": ""}))
	return out


## The row that strips the ship to stock, while anything is fitted.
static func strip_rows(model: HubModel) -> Array[Dictionary]:
	if model.fitting.is_empty():
		return []
	var words: HubWords = model.config.words
	return [HubRows.noted(HubRows.acting(words.row("strip_row"), {"action": HubText.ACTION_STRIP}), words.row("strip_note"))]


## The row offering upgrade `id` for `slot`: a mount, or a move whose note
## says where it is now.
static func _option(model: HubModel, slot: String, id: String) -> Dictionary:
	var words: HubWords = model.config.words
	var now: String = model.fitting.slot_of(id)
	if now == "":
		return HubRows.acting(words.row("fit_option_row", {"name": _name(model, id)}), {"action": HubText.ACTION_FIT, "slot": slot, "id": id})
	return HubRows.noted(HubRows.acting(words.row("move_option_row", {"name": _name(model, id)}),
		{"action": HubText.ACTION_MOVE, "slot": slot, "id": id}), words.row("move_note", {"from": words.named_slot(now)}))


## The upgrade's name from its data file, or its id when the tree lacks it.
static func _name(model: HubModel, id: String) -> String:
	return model.tree.get_upgrade(id).display_name if model.tree.has_upgrade(id) else id
