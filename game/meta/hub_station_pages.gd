class_name HubStationPages
extends RefCounted

## Which rows of the hub's pages each station of the home base room shows
## (#1299, decision record 0012). The ids are the room's stations
## (`HubRoomSpec.STATION_IDS`; `meta/` cannot read `view/`, so a test keeps the
## two lists equal). The Fitting Bay page holds the ways into the mine as well
## as the slots; its resume and launch rows carry a group and have stations of
## their own. The Parts Locker sits on the Workbench, under what can be built
## from it.

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
	return out


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
