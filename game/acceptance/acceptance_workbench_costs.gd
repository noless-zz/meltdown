class_name AcceptanceWorkbenchCosts
extends RefCounted

## What the Workbench promises about costs since #1351 (#1300): the cost of an
## upgrade shows under it while it is selected, not under every row at once
## (#1394, #1317, CRF-3, CRW-2, DEV-6). The `hub_stations` check walks the
## selection over the craft station's rows with the stick, as a pilot would,
## and every upgrade that can be built or is locked must show its own cost on
## the screen while it is selected. Built upgrades have no cost to show.
##
## The walk and the verdict take the screen and the stick as callables, so the
## unit tests run them on a bare `HubText` and the check on the room's stations.

## Stick moves tried before the walk gives up; above any Workbench's rows.
const MAX_MOVES: int = 200


## The screen's lines while each upgrade is selected, by upgrade id, walking
## from the first selectable row to the last. `screen` returns the lines the
## station shows now; `step` moves the selection by its int argument (the
## stick up for -1, down for 1).
static func walk(text: HubText, screen: Callable, step: Callable) -> Dictionary[String, Array]:
	for i: int in MAX_MOVES:
		var before: int = text.selected_line()
		step.call(-1)
		if text.selected_line() == before:
			break
	var seen: Dictionary[String, Array] = {}
	for i: int in MAX_MOVES:
		var chosen: Dictionary = text.selected()
		if chosen.get("action", "") == HubText.ACTION_CRAFT:
			var lines: Array = screen.call()
			seen[str(chosen["id"])] = lines.duplicate()
		var line: int = text.selected_line()
		step.call(1)
		if text.selected_line() == line:
			break
	return seen


## "" when every upgrade the Workbench can build or lists as locked showed its
## own cost while selected in `seen` (from `walk`), else the first one that did
## not, by name.
static func judge(model: HubModel, seen: Dictionary[String, Array]) -> String:
	var ids: Array[String] = model.craftable()
	for entry: Dictionary in model.locked():
		ids.append(entry["id"])
	if ids.is_empty():
		return "the Workbench offers no upgrade to walk over"
	for id: String in ids:
		var name: String = HubCraftRows.upgrade_name(model, id)
		if not seen.has(id):
			return "the stick never selects %s on the Workbench" % name
		if not (seen[id] as Array).has(cost_line(model, id)):
			return "the Workbench shows no cost for %s while it is selected: %s" % [name, seen[id]]
	return ""


## The line that states upgrade `id`'s cost with what is held. The one place
## this check reads how a cost is worded, so a new cost layout (#1367) changes
## only this function.
## Since the tree (#1367) a cost is one component per line; the first is asked for.
static func cost_line(model: HubModel, id: String) -> String:
	var lines: Array[String] = HubCraftRows.texts(HubCraftRows.cost_lines(model, id))
	return lines[0] if not lines.is_empty() else ""
