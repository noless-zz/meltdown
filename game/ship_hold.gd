class_name ShipHold
extends RefCounted

## Whether this player's ship is on held or neutral input this frame (#819):
## the dev menu is open (decision record 0009), the flight test holds the ship
## for an answer, the session is paused for lost focus, or the ship is lost or
## an end screen (destroyed or escaped) is up. Swivel-chair yaw adds nothing
## then (CMF-7, CMF-8).
##
## Read only: it asks the wirings and a copy of the ship; it writes nothing
## (ARC-3, MP-2). Any argument but `session` may be null.


static func is_held(dev_menu: DevMenuWiring, flight_test: FlightTestWiring, session: LocalSession,
		destroyed: DestroyedWiring) -> bool:
	if dev_menu != null and dev_menu.is_open():
		return true
	if flight_test != null and flight_test.holding():
		return true
	if session.paused or session.current_ship().hull <= 0.0:
		return true
	if destroyed == null:
		return false
	return destroyed.fade_alpha() > 0.0 or destroyed.sequence.line_shown() \
		or destroyed.escape.sequence.line_shown()
