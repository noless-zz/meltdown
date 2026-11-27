class_name HubStationSelect
extends RefCounted

## Takes a home base station into use by pressing the stick and A as the
## pilot would (#1408, DEV-7, ARC-3): stick left until no station is in use,
## stick right along the room's order until the station is highlighted, then
## A. Each press goes through `HubStations.update` with a release after it, so
## the station rules, refusals and drawings are exactly the player's. Moving
## between stations changes no profile, fitting or simulation state (MP-2);
## A on a station only takes it into use. Used by the test checklist's
## `station` step action.


## Takes station `id` into use; true when it is. False, pressing nothing, for
## an unknown id or closed stations.
static func select(stations: HubStations, id: String) -> bool:
	if stations == null or not stations.visible or stations.hub == null or not stations.ids.has(id):
		return false
	if stations.in_use == id:
		return true
	stations.update({})  # Lets go of anything the last frame held, so the first press counts.
	# Stick left steps back inside a station that has depth (the Fitting Bay) before it leaves it.
	for i: int in stations.ids.size() * 4:
		if stations.in_use == "":
			break
		_press(stations, DevMenuModel.LEFT)
	for i: int in stations.ids.size():
		if stations.highlighted_id() == id:
			break
		_press(stations, DevMenuModel.RIGHT)
	if stations.in_use == "" and stations.highlighted_id() == id:
		_press(stations, DevMenuModel.CONFIRM)
	return stations.in_use == id


## One press of `action` and its release, as two frames of the stick or A.
static func _press(stations: HubStations, action: String) -> void:
	stations.update({action: true})
	stations.update({})
