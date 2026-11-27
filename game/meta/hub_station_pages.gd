class_name HubStationPages
extends RefCounted

## Which rows of the hub's pages each station of the home base room shows
## (#1299, decision record 0012). The ids are the room's stations
## (`HubRoomSpec.STATION_IDS`; `meta/` cannot read `view/`, so a test keeps the
## two lists equal). The Fitting Bay page holds the ways into the mine as well
## as the slots; its resume and launch rows carry a group and have stations of
## their own. The Parts Locker sits on the Workbench, under what can be built
## from it, or, when the hub file draws it (#1413), on the Workbench's second
## face (`HubLocker`), switched to by a row at the top of the first.

## Row groups of the Fitting Bay page.
const GROUP_LAUNCH: String = "launch"
const GROUP_RESUME: String = "resume"
## Station id to the pages whose rows it shows, in order, and the row group it
## keeps ("" for rows of no group). The first page's title is the station's.
const STATIONS: Dictionary[String, Dictionary] = {
	"crew": {"pages": [HubConfig.CREW], "group": ""},
	"logbook": {"pages": [HubConfig.STATS], "group": ""},
	"craft": {"pages": [HubConfig.CRAFT, HubConfig.STORE], "group": ""},
	"fit": {"pages": [HubConfig.FIT], "group": ""},
	"resume": {"pages": [HubConfig.FIT], "group": GROUP_RESUME},
	"launch": {"pages": [HubConfig.FIT], "group": GROUP_LAUNCH},
}


## Station `station`'s rows: its pages' rows of its group, a later page
## starting under its title. A station with no row of its group shows the
## group's empty line. The Workbench draws its tree in place of the Workbench
## page's rows when the hub file has one (#1367); the Parts Locker stays under it.
static func rows(model: HubModel, station: String) -> Array[Dictionary]:
	var spec: Dictionary = STATIONS[station]
	var out: Array[Dictionary] = []
	var pages: Array = spec["pages"]
	if HubLocker.shows(model, station):
		out.append(HubLocker.switch_row(model, HubLocker.TREE))
		pages = pages.filter(func(page: Variant) -> bool: return str(page) != HubConfig.STORE)
	for i: int in pages.size():
		var kept: Array[Dictionary] = []
		var page: String = str(pages[i])
		var page_rows_of: Array[Dictionary] = HubCraftTree.rows(model) \
			if page == HubConfig.CRAFT and HubCraftTree.shows(model, station) else page_rows(model, page)
		for entry: Dictionary in page_rows_of:
			if str(entry.get("group", "")) == str(spec["group"]):
				kept.append(entry)
		if i > 0 and not kept.is_empty():
			out.append(HubRows.shown(model.page_title(page)))
		out.append_array(kept)
	if out.is_empty() and spec["group"] == GROUP_RESUME:
		out.append(HubRows.shown(model.config.words.row("resume_none")))
	return HubBoard.trim(model, station, out)


## Page `id`'s rows, as the flat panel shows them.
static func page_rows(model: HubModel, id: String) -> Array[Dictionary]:
	match id:
		HubConfig.CREW:
			return HubRows.crew(model) + HubSummaryRows.rows(model)
		HubConfig.STATS:
			return HubRows.stats(model)
		HubConfig.STORE:
			return HubRows.store(model)
		HubConfig.CRAFT:
			return HubCraftRows.rows(model)  # Costs, numbers and unlocks (#1317).
	return HubFitRows.rows(model)


## Rows a screen shows at once (`max_rows_visible` in the hub file): fewer
## while picking a slot on the bay's drawn ship (`fit_slot` ""), so the ship has
## the face, and where a drawing takes the rest of it: a mount's bars (#1385),
## the Workbench's `tree` (#1367) or `locker` (#1413), a board (#1368).
static func rows_shown(model: HubModel, station: String, fit_slot: String, tree: bool, locker: bool) -> int:
	if station == HubFitBay.STATION and fit_slot == "" and model.config.fit_layout.has_ship():
		return model.config.fit_layout.slot_rows_visible
	if station == HubFitBay.STATION and HubFitBoard.rows_shown(model, fit_slot) > 0:
		return HubFitBoard.rows_shown(model, fit_slot)
	if locker:
		return model.config.locker.rows_visible
	if tree:
		return model.config.craft_tree.rows_visible
	if HubBoard.shows(model, station):
		return model.config.boards.rows_visible
	return model.config.max_rows_visible
