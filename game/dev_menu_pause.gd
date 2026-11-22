class_name DevMenuPause
extends RefCounted

## In solo play an open dev menu pauses the session (#1245, PLT-7, CMF-8):
## no tick runs, so the ship, robots, shots, debris and the meltdown countdown
## all hold, and closing the menu resumes with one tick at most. The menu is
## its own pause reason beside the headset's focus (`LocalSession.PAUSE_MENU`),
## so either order of taking the headset off and closing the menu stays
## paused until both are done. Only the pause reason is written; the view,
## the menu and its choices are untouched (MP-2, ARC-3).
##
## Co-op (M5): the shared simulation cannot stop for one player. There the
## menu does not pause; it only takes the ship's input away, as
## `DevMenuWiring.read` already does (#1206), and the overlay is the safe one
## PLT-7 describes. No co-op session exists yet, so nothing here branches on it.


## Holds or lets go of `session`'s menu pause; the dev menu calls it every
## frame with whether it is open, and the acceptance suite calls it to open
## and close the menu without the controllers. A null session does nothing.
static func hold(session: LocalSession, menu_open: bool) -> void:
	if session != null and session.paused_by(LocalSession.PAUSE_MENU) != menu_open:
		session.set_paused(LocalSession.PAUSE_MENU, menu_open)
