extends RefCounted

## The destroyed ship in the real main scene (#616, RUN-7, CMF-8, MP-2): zero
## hull fades the view and shows SHIP DESTROYED, the prompt follows the hold,
## and a press restarts the level with a fresh ship through the loading path.

const FRAME: float = 1.0 / 90.0


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


func _fly(main: Node, seconds: float, buttons: Dictionary = {}) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	for i: int in ceili(seconds / FRAME):
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)


func test_zero_hull_fades_shows_the_line_and_restarts_on_a_press() -> String:
	var main: Node = _main()
	var result: String = _check(main)
	main.free()
	return result


func _check(main: Node) -> String:
	_fly(main, 0.1)
	var wiring: DestroyedWiring = main.get("destroyed")
	var fade: FadeOverlay = main.get("fade_overlay")
	if wiring.screen == null or wiring.screen.get_parent() != main.get_node("XRRig"):
		return "the destroyed screen is not under the rig"
	if wiring.screen.line_visible() or fade.get_alpha() != 0.0:
		return "the destroyed screen shows on a whole ship"
	var old: LocalSession = main.get("session")
	old.sim.ships[0].hull = 0.0
	_fly(main, 1.2)
	if not wiring.screen.line_visible():
		return "SHIP DESTROYED is not shown after the hull reached zero"
	if fade.get_alpha() < 0.99:
		return "the view is not dark a second after death (alpha %.2f)" % fade.get_alpha()
	if wiring.screen.prompt_visible():
		return "the restart prompt shows before the hold time"
	_fly(main, 2.0, {DestroyedWiring.KEYBOARD_BUTTON: true})
	if main.get("session") != old:
		return "a press before the prompt restarted the level"
	_fly(main, 0.1)
	if not wiring.screen.prompt_visible() or not wiring.screen.prompt_text().contains("Enter"):
		return "the flat build's prompt is not shown after the hold: '%s'" % wiring.screen.prompt_text()
	_fly(main, 5.0)
	if main.get("session") != old:
		return "the level restarted without a press"
	_fly(main, FRAME, {DestroyedWiring.KEYBOARD_BUTTON: true})
	var fresh: LocalSession = main.get("session")
	if fresh == old:
		return "Enter did not restart the level"
	var ship: ShipState = fresh.current_ship()
	if ship.hull != ship.max_hull or ship.hull <= 0.0:
		return "the restarted ship has hull %.1f of %.1f" % [ship.hull, ship.max_hull]
	if wiring.screen.line_visible():
		return "SHIP DESTROYED is still shown after the restart"
	if old.sim.ships[0].hull != 0.0:
		return "the restart wrote into the old session"
	_fly(main, 1.2)
	if fade.get_alpha() != 0.0:
		return "the view did not fade back in (alpha %.2f)" % fade.get_alpha()
	var panel: StatusPanel = main.get("status_panel")
	if panel.hull_bar_scale() < 0.99 or panel.hull_warning_shown():
		return "the panel still shows a lost hull after the restart"
	return ""


func test_a_restart_keeps_the_level_the_launch_flew() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	(main.get("level_start") as LevelStart).source = "res://data/levels/g2_level.json"
	main.call("restart_level")
	var session: LocalSession = main.get("session")
	var has_view: bool = main.get_node_or_null(LevelView.NODE_NAME) != null
	var has_tunnel: bool = main.get_node_or_null("TestTunnel") != null
	main.free()
	if not has_view or has_tunnel:
		return "restarting a level file did not draw that level"
	if session.sim.reactor == null:
		return "the restarted G2 session has no reactor"
	return ""
