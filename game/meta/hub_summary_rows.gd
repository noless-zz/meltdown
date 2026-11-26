class_name HubSummaryRows
extends RefCounted

## The ship summary's rows on the Fitting Bay and Crew Quarters (CRF-4, CRW-1,
## CRW-2, #1357): one row per attribute with its current value beside the
## stock one ("Speed 22 / 20"), and, while that row is selected, one line per
## source that makes up the difference ("Tuned Thrusters +2"). A fit or move
## row gets the attributes it would change as before and after, under it while
## it is selected. Every word is the hub file's (ARC-4, NAM-3): a ship number is
## named by its `effect_names` pattern, a crew stat by its `stat_names` one, so
## no id reaches a screen; an attribute the file names nowhere is left out.

## Prefix of the key a summary row owns its source lines by (`HubText._rows`).
const OWNS_PREFIX: String = "summary:"


## The header and one row per attribute of `model.summary()`, each followed by
## its source lines, shown only while it is selected.
static func rows(model: HubModel) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	var summary: Array[Dictionary] = model.summary()
	if summary.is_empty():
		return out
	out.append(HubRows.shown(words.row("summary_header")))
	for entry: Dictionary in summary:
		var text: String = value_text(words, entry)
		if text == "":
			continue
		var row: Dictionary = HubRows.info(text)
		row["owns"] = OWNS_PREFIX + str(entry["stat"])
		var sources: Array = entry["sources"]
		if sources.is_empty():
			HubRows.noted(row, words.row("summary_stock_note"))
		out.append(row)
		for source: Dictionary in sources:
			out.append(_detail(source_text(words, source), row["owns"]))
	return out


## The before and after lines of a fit or move `action`, shown only while the
## row doing it is selected (`detail_of` its upgrade id).
static func change_rows(model: HubModel, action: Dictionary) -> Array[Dictionary]:
	var words: HubWords = model.config.words
	var out: Array[Dictionary] = []
	for change: Dictionary in model.preview(action):
		var text: String = change_text(words, change)
		if text != "":
			out.append(_detail(text, str(action.get("id", ""))))
	return out


## A summary row's words: "Speed 22 / 20" for a ship number, "salvage slots +1"
## for a crew stat with no ship number; "" when the hub file names neither.
static func value_text(words: HubWords, entry: Dictionary) -> String:
	if not entry["ship"]:
		if not words.stat_names.has(entry["stat"]):
			return ""
		return words.row("summary_bonus_row", {"stat": words.stat_name(entry["stat"]), "amount": number(entry["current"])})
	return words.effect(entry["stat"], words.row("summary_value",
		{"current": number(entry["current"]), "stock": number(entry["stock"])}))


## One change's words: "Speed 20 to 22", or "" when the hub file names no such number.
static func change_text(words: HubWords, change: Dictionary) -> String:
	var value: String = words.row("change_value", {"before": number(change["before"]), "after": number(change["after"])})
	if change["ship"]:
		return words.effect(change["stat"], value)
	if not words.stat_names.has(change["stat"]):
		return ""
	return "%s %s" % [words.stat_name(change["stat"]), value]


## One source's words: "Tuned Thrusters +2", "Shield Technician ×2 +10".
static func source_text(words: HubWords, source: Dictionary) -> String:
	var change: String = signed(source["change"])
	if source["kind"] == ShipSummary.KIND_CREW:
		return words.row("summary_crew", {"role": source["name"], "count": source["count"], "change": change})
	return words.row("summary_part", {"name": source["name"], "change": change})


## A number as a whole when it is one, else to at most two decimals.
static func number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	var text: String = "%.2f" % value
	return text.rstrip("0").rstrip(".")


## `number` with its sign.
static func signed(value: float) -> String:
	return ("+" if value >= 0.0 else "") + number(value)


static func _detail(text: String, owner: String) -> Dictionary:
	var detail: Dictionary = HubRows.shown(text)
	detail["detail_of"] = owner
	return detail
