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
