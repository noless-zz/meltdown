extends RefCounted

## The end screens drawn once over a fade that only goes one way (#1228,
## RUN-3, CMF-8, ARC-3): from the frame the fade starts until the press, the
## end screen's line is the only text in the rig, the status panel and the
## held map are hidden, and the fade's opacity never goes down. The panel is
## back after the press.

const FRAME: float = 1.0 / 90.0


func _main(source: String) -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	(main.get("level_start") as LevelStart).source = source
	main.call("restart_level")
	return main


func _frame(main: Node, buttons: Dictionary = {}) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)


func _panel(main: Node) -> StatusPanel:
	return main.get_node("XRRig").get_node_or_null(StatusPanel.NODE_NAME) as StatusPanel


func _map(main: Node) -> Node3D:
	return main.get_node("XRRig").find_child(MapHologram.NODE_NAME, true, false) as Node3D


func test_an_escape_shows_one_line_over_a_fade_that_never_drops() -> String:
	var main: Node = _main("seed:31")
	var result: String = _check(main, true)
	main.free()
	return result


func test_the_destroyed_screen_shows_one_line_over_a_fade_that_never_drops() -> String:
	var main: Node = _main("seed:31")
	var result: String = _check(main, false)
	main.free()
	return result


## Ends the run (an escape or a destroyed ship), then steps frame by frame
## through the fade, the hold and the prompt to the press.
func _check(main: Node, escape: bool) -> String:
	for i: int in 10:
		_frame(main)
	var session: LocalSession = main.get("session")
	var wiring: DestroyedWiring = main.get("destroyed")
	var fade: FadeOverlay = main.get("fade_overlay")
	var panel: StatusPanel = _panel(main)
	var map: Node3D = _map(main)
	if panel == null or not panel.visible:
		return "the status panel is not shown while flying"
	if map == null:
		return "the main scene has no map"
	map.visible = true  # The pilot holds the map open as the run ends.
	if escape:
		session.sim.reactor.destroyed = true
		session.sim.reactor.meltdown_ticks_left = 27 * ReactorState.TICKS_PER_SECOND
		session.sim.ships[0].escaped = true
	else:
		session.sim.ships[0].hull = 0.0
	var last: float = 0.0
	var frames: int = 0
	# Past the fade, the hold and the prompt's first second.
	while frames < ceili(5.0 / FRAME):
		_frame(main)
		frames += 1
		var alpha: float = fade.get_alpha()
		if alpha < last:
			return "frame %d: the fade went down from %.3f to %.3f" % [frames, last, alpha]
		last = alpha
		var lines: Array[String] = _lines_shown(main, wiring)
		if lines.size() != 1:
			return "frame %d: %d end texts show: %s" % [frames, lines.size(), lines]
		if panel.visible:
			return "frame %d: the status panel shows over the end screen" % frames
		if map.visible:
			return "frame %d: the map shows over the end screen" % frames
	if last < 1.0:
		return "the view is not dark before the press (alpha %.2f)" % last
	var prompt: bool = wiring.escape.screen.prompt_visible() if escape else wiring.screen.prompt_visible()
	if not prompt:
		return "the prompt is not shown after the hold"
	if wiring.fade_dropped:
		return "the wiring saw the fade go down"
	_frame(main, {DestroyedWiring.KEYBOARD_BUTTON: true})
	if main.get("session") == session:
		return "the press did not restart the level"
	if not _lines_shown(main, wiring).is_empty():
		return "an end text is still shown after the press"
	_frame(main)
	if not panel.visible:
		return "the status panel is not back after the press"
	if wiring.cover.covering():
		return "the cover still holds the panel or map after the press"
	return ""


## The end texts visible in the rig: either screen's line and the panel's outcome row.
func _lines_shown(main: Node, wiring: DestroyedWiring) -> Array[String]:
	var shown: Array[String] = []
	if wiring.escape.screen.line_visible():
		shown.append(wiring.escape.screen.line_text())
	if wiring.screen.line_visible():
		shown.append("SHIP DESTROYED")
	var panel: StatusPanel = _panel(main)
	if panel != null and panel.visible and panel.outcome_visible():
		shown.append("panel outcome row")
	return shown


func test_the_cover_puts_back_each_node_as_it_was() -> String:
	var rig: Node3D = Node3D.new()
	var panel: Node3D = Node3D.new()
	panel.name = StatusPanel.NODE_NAME
	rig.add_child(panel)
	var hand: Node3D = Node3D.new()
	hand.name = "LeftHand"
	rig.add_child(hand)
	var map: Node3D = Node3D.new()
	map.name = MapHologram.NODE_NAME
	map.visible = false
	hand.add_child(map)
	var cover: EndScreenCover = EndScreenCover.new()
	cover.attach(rig)
	var result: String = ""
	cover.update(true)
	if panel.visible or map.visible:
		result = "the panel or map is not hidden while covering"
	panel.visible = true  # The dev menu shows the panel again each frame.
	cover.update(true)
	if result == "" and panel.visible:
		result = "the panel shown again by another view is not hidden on the next frame"
	cover.update(false)
	if result == "" and (not panel.visible or map.visible):
		result = "after covering the panel is not shown or the closed map was opened"
	rig.free()
	return result
