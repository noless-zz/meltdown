class_name HubRows
extends RefCounted

## Rows of the hub's simpler pages (crew, Logbook, Parts Locker) and the row
## shapes every page uses, kept apart from `HubText` so each file stays small
## (#1300). A row is {"text", "action", "selectable"}, with an optional
## "group" (Fitting Bay) and "note": its one line of explanation, shown only
## while the row is selected.


static func crew(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var rows: Array[Dictionary] = []
	for member: Dictionary in model.crew():
		var role: String = member["role_name"] if member["role_name"] != "" else member["role"]
		rows.append(noted(info(words.row("crew_row", {"role": role})),
			words.row("crew_note", {"amount": member["amount"], "stat": words.stat_name(member["stat"])})))
	if rows.is_empty():
		rows.append(noted(info(model.config.empty_crew), words.row("empty_crew_note")))
	return rows


## One short row per counter, selectable only so the page scrolls; while every
## counter is still 0 the first row explains the empty logbook.
static func stats(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var rows: Array[Dictionary] = []
	var counters: Dictionary = model.stats()
	var any: bool = false
	for key: String in ProfileStats.KEYS:
		any = any or int(counters.get(key, 0)) != 0
		rows.append(info(words.row(HubWords.STATS_ROW_PREFIX + key, {"count": int(counters.get(key, 0))})))
	if not any:
		noted(rows[0], words.row("stats_empty"))
	return rows


static func store(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var rows: Array[Dictionary] = []
	for kind: Dictionary in model.store():
		rows.append(noted(info(words.row("store_row", {"name": kind["name"], "count": kind["count"]})),
			words.row("store_note", {"tier": kind["tier"]})))
	if rows.is_empty():
		rows.append(noted(info(model.config.empty_store), words.row("empty_store_note")))
	return rows


## A row that can be selected but does nothing.
static func info(text: String) -> Dictionary:
	return {"text": text, "action": {}, "selectable": true}


## A row that takes `action` when pressed.
static func acting(text: String, action: Dictionary) -> Dictionary:
	return {"text": text, "action": action, "selectable": true}


## `entry` with `text` as its explanation under it while selected.
static func noted(entry: Dictionary, text: String) -> Dictionary:
	entry["note"] = text
	return entry


static func grouped(entry: Dictionary, group: String) -> Dictionary:
	entry["group"] = group
	return entry


## A header or empty-page text, skipped by the selection.
static func shown(text: String) -> Dictionary:
	return {"text": text, "action": {}, "selectable": false}
