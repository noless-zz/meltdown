class_name DevMenuWhere
extends RefCounted

## Where the pilot sits, for the dev menu (#1450, CRW-2, CMF-6, DEV-8): the
## menu opens everywhere, in the mine, at the home base, at the shaft choice
## and on the destroyed and escape screens, and shows there only the entries
## that name that place (`DevMenuPlaces`). This replaces #1170's "the hub
## closes the dev menu" at the owner's request on #1450; decision record 0009
## (the tap opens the menu) is unchanged.
##
## The tap is still ignored during the first-launch flight test, while the
## view fades between the mine and an end screen (the menu opens once the end
## screen is dark), and while the hub's launch fades out (`blocked`). It also
## hangs the "Update available" sign (`UpdateSign`) in the base room and shows
## it while a newer build waits.
## Split from `DevMenuWiring` so neither it nor `main.gd` grows. It reads the
## flight test, the end screens and the hub; it writes nothing (MP-2, ARC-3).

var flight_test: FlightTestWiring = null
var destroyed: DestroyedWiring = null
## True while the hub is open (`HubWiring.is_open`); unset, there is no hub.
var hub_open: Callable = Callable()
## In the base room once `attach` has run with a hub; null otherwise.
var sign: UpdateSign = null


## Keeps what the place is read from and hangs the sign under the hub's room
## (under `rig` when the room did not load); no sign without a rig or a hub.
func attach(rig: Node3D, p_flight_test: FlightTestWiring, p_destroyed: DestroyedWiring,
		p_hub_open: Callable) -> void:
	flight_test = p_flight_test
	destroyed = p_destroyed
	hub_open = p_hub_open
	var hub: HubWiring = hub_object()
	if rig == null or hub == null or sign != null:
		return
	sign = UpdateSign.new()
	var room: HubRoom = hub.room if hub.room != null and hub.room.is_built() else null
	(room if room != null else rig).add_child(sign)


## The place the pilot sits now, one of `DevMenuPlaces.ALL`.
func place() -> String:
	if hub_is_open():
		return DevMenuPlaces.BASE
	if destroyed != null and destroyed.escape.choice.is_open():
		return DevMenuPlaces.SHAFT
	if destroyed != null and (destroyed.sequence.line_shown() or destroyed.escape.sequence.line_shown()):
		return DevMenuPlaces.END
	return DevMenuPlaces.MINE


## Whether the tap is ignored now: the flight test runs, the view is fading
## between the mine and an end screen, or the hub's launch is fading out.
func blocked() -> bool:
	if flight_test != null and flight_test.running():
		return true
	var hub: HubWiring = hub_object()
	if hub != null and hub.launching.is_launching():
		return true
	var alpha: float = destroyed.fade_alpha() if destroyed != null else 0.0
	return alpha > 0.0 and (alpha < 1.0 or place() == DevMenuPlaces.MINE)  # Opens once the screen is dark.


func hub_is_open() -> bool:
	return hub_open.is_valid() and bool(hub_open.call())


## The hub behind `hub_open`, or null when it is another callable (tests) or unset.
func hub_object() -> HubWiring:
	return hub_open.get_object() as HubWiring if hub_open.is_valid() else null


## Once a frame: the sign names `version` at the base, and hides elsewhere or for "".
func show_sign(version: String) -> void:
	if sign != null:
		sign.show_version(version if place() == DevMenuPlaces.BASE else "")
