extends RefCounted

## The home base stations' sounds driven through the real stations (#1401,
## AUD-1, CRW-2, CRF-3, CRF-4, ARC-3, MP-2): choosing, crafting, mounting,
## clearing a slot, a refused launch and stepping back each request their
## sound from the station they happen at; scrolling faster than the gap does
## not tick on every row; the sounds change nothing the hub does.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const FRAME_S: float = 1.0 / 60.0
const SOUND_FILES: Array[String] = ["res://xr/hub_station_sounds.gd", "res://xr/hub_sound_table.gd"]


## One frame as `HubWiring.update` runs it, `seconds` long.
static func _frame(stations: HubStations, sounds: HubStationSounds, held: Dictionary, seconds: float = FRAME_S) -> void:
	var before: Dictionary = HubSoundTable.state(stations)
	var result: Dictionary = stations.update(held)
	sounds.hear(before, result, seconds)


## Presses `action` and lets it go, a quarter second apart, so no gap holds a sound back.
static func _tap(stations: HubStations, sounds: HubStationSounds, action: String) -> void:
	_frame(stations, sounds, {action: true}, 0.25)
	_frame(stations, sounds, {}, 0.25)


static func _use(stations: HubStations, sounds: HubStationSounds, id: String) -> void:
	if stations.in_use != "":
		_tap(stations, sounds, DevMenuModel.LEFT)
	for i: int in stations.ids.size():
		if stations.highlighted_id() == id:
			break
		_tap(stations, sounds, DevMenuModel.RIGHT)
	_tap(stations, sounds, DevMenuModel.CONFIRM)


## Walks the stick from the top row down to the row doing `want` and presses A.
static func _press(stations: HubStations, sounds: HubStationSounds, hub: HubText, want: Dictionary) -> bool:
	for i: int in 200:
		var line: int = hub.selected_line()
		_tap(stations, sounds, DevMenuModel.UP)
		if hub.selected_line() == line:
			break
	for i: int in 200:
		if hub.selected() == want:
			_tap(stations, sounds, DevMenuModel.CONFIRM)
			return true
		var line: int = hub.selected_line()
		_tap(stations, sounds, DevMenuModel.DOWN)
		if hub.selected_line() == line:
			return false
	return false


static func _open(hub: HubText) -> Array:
	var stations: HubStations = Stations._open(hub)
	var sounds: HubStationSounds = HubStationSounds.new(stations)
	sounds.enabled = false
	stations.get_parent().add_child(sounds)
	sounds.opened()
	return [stations, sounds]


func test_crafting_mounting_and_clearing_request_their_sounds_at_their_stations() -> String:
	var hub: HubText = Stations._hub(Stations._rich_profile())
	var opened: Array = _open(hub)
	var stations: HubStations = opened[0]
	var sounds: HubStationSounds = opened[1]
	var weapon: String = AcceptanceCraftAndFitCheck.first_weapon(hub.model)
	var problem: String = "the rich profile builds no weapon" if weapon == "" else ""
	var steps: Array[Array] = [
		["craft", {"action": HubText.ACTION_CRAFT, "id": weapon}, "crafted"],
		["fit", {"action": HubFitBay.ACTION_SLOT, "slot": "primary[0]"}, "select"],
		["fit", {"action": HubText.ACTION_FIT, "slot": "primary[0]", "id": weapon}, "mounted"],
		["fit", {"action": HubFitBay.ACTION_SLOT, "slot": "primary[0]"}, "select"],
		["fit", {"action": HubText.ACTION_FIT, "slot": "primary[0]", "id": ""}, "unmounted"],
	]
	for step: Array in steps:
		if problem != "":
			break
		if stations.in_use != step[0]:
			_use(stations, sounds, step[0])
			if sounds.requested.is_empty() or sounds.requested[-1] != "select":
				problem = "taking %s into use requested %s" % [step[0], sounds.requested]
				break
		if not _press(stations, sounds, hub, step[1]):
			problem = "no row of %s does %s" % [step[0], step[1]]
		elif sounds.requested[-1] != step[2] or sounds.requested_at[-1] != step[0]:
			problem = "%s at %s requested %s at %s, expected %s" % [step[1], step[0], sounds.requested[-1],
				sounds.requested_at[-1], step[2]]
	if problem == "" and not sounds.requested.has("point"):
		problem = "walking the rows never requested point: %s" % [sounds.requested]
	if problem == "":
		_tap(stations, sounds, DevMenuModel.LEFT)  # Clearing put the bay back on its ship, so this leaves.
		if sounds.requested[-1] != "back" or stations.in_use != "":
			problem = "stepping out of the bay requested %s, in use %s" % [sounds.requested[-1], stations.in_use]
	sounds.free()
	Stations._free(stations)
	return problem


func test_a_refused_launch_requests_refused_not_launch() -> String:
	var hub: HubText = Stations._hub(Profile.new())
	hub.model.fitting.primary[0] = "arc_lance"  # Not crafted: the fitting check refuses it.
	var opened: Array = _open(hub)
	var stations: HubStations = opened[0]
	var sounds: HubStationSounds = opened[1]
	_use(stations, sounds, "launch")
	var problem: String = ""
	if not _press(stations, sounds, hub, {"action": HubText.ACTION_LAUNCH}):
		problem = "the launch station has no launch row"
	elif sounds.requested[-1] != "refused" or sounds.requested.has("launch"):
		problem = "a refused launch requested %s" % [sounds.requested]
	sounds.free()
	Stations._free(stations)
	return problem


func test_scrolling_faster_than_the_gap_does_not_tick_every_row() -> String:
	var hub: HubText = Stations._hub(Stations._rich_profile())
	var opened: Array = _open(hub)
	var stations: HubStations = opened[0]
	var sounds: HubStationSounds = opened[1]
	_use(stations, sounds, "craft")
	sounds.opened()
	var moved: int = 0
	for i: int in 6:  # A press and a release a frame each: 30 rows a second.
		var line: int = hub.selected_line()
		_frame(stations, sounds, {DevMenuModel.DOWN: true})
		_frame(stations, sounds, {})
		moved += 1 if hub.selected_line() != line else 0
	var problem: String = ""
	if moved < 4:
		problem = "the craft station has too few rows to scroll (%d moves)" % moved
	elif sounds.requested.count("point") >= moved or sounds.requested.count("point") < 1:
		problem = "%d rows scrolled fast requested %d points" % [moved, sounds.requested.count("point")]
	sounds.free()
	Stations._free(stations)
	return problem


func test_the_sounds_change_nothing_the_hub_does() -> String:
	var heard: HubText = Stations._hub(Stations._rich_profile())
	var opened: Array = _open(heard)
	var stations: HubStations = opened[0]
	var sounds: HubStationSounds = opened[1]
	var silent_hub: HubText = Stations._hub(Stations._rich_profile())
	var silent: HubStations = Stations._open(silent_hub)
	var weapon: String = AcceptanceCraftAndFitCheck.first_weapon(heard.model)
	_use(stations, sounds, "craft")
	_press(stations, sounds, heard, {"action": HubText.ACTION_CRAFT, "id": weapon})
	Stations._use(silent, "craft")
	Stations._press(silent, silent_hub, {"action": HubText.ACTION_CRAFT, "id": weapon})
	var problem: String = ""
	if heard.model.profile.to_json() != silent_hub.model.profile.to_json():
		problem = "the profile differs with sounds: %s / %s" % [heard.model.profile.to_json(), silent_hub.model.profile.to_json()]
	elif stations.texts() != silent.texts():
		problem = "the screens differ with sounds: %s / %s" % [stations.texts(), silent.texts()]
	for path: String in SOUND_FILES:
		var source: String = FileAccess.get_file_as_string(path)
		for forbidden: String in ["Sim", "ShipState", "LocalSession", "Input.", "Comfort", "save(", "Profile", "HubModel"]:
			if problem == "" and source.find(forbidden) >= 0:
				problem = "%s uses %s" % [path, forbidden]
	sounds.free()
	Stations._free(stations)
	Stations._free(silent)
	return problem
