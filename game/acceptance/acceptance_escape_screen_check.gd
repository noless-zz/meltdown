class_name AcceptanceEscapeScreenCheck
extends RefCounted

## The `escape_screen` acceptance check (#751, RUN-3, RUN-7): when the replay
## ends on an escape, the main scene shows the escape's end screen, `ESCAPED`
## with the meltdown time left, and not the destroyed ship's. Kept out of
## `AcceptanceRunner` so that file stays short. While the screen shows, the
## status panel and the held map are hidden, and the fade never went down on
## the way there (#1228, CMF-8).


## [result, message] for the check on `main`, the game scene, after its replay
## (`flown`), adding the time line shown to `measurements`. A scene without a
## rig (tests that fly the runner headless) has no screen node, so what the
## screen is told to show is judged: the sequences' state and the time line.
static func run(main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var wiring: DestroyedWiring = main.get("destroyed")
	if wiring == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene has no end screens"]
	var end: EscapeEndWiring = wiring.escape
	var time: String = EscapeScreenLook.time_line(end.look, EscapeEndWiring.seconds_left(main.get("session")))
	measurements["escape_time_text"] = time
	if not end.sequence.line_shown() or (end.screen != null and not end.screen.line_visible()):
		return [AcceptanceReport.RESULT_FAIL, "the escape screen is not shown"]
	if wiring.sequence.line_shown():
		return [AcceptanceReport.RESULT_FAIL, "the destroyed screen shows after an escape"]
	if wiring.fade_dropped:
		return [AcceptanceReport.RESULT_FAIL, "the fade went down while the escape screen showed"]
	var rig: Node3D = main.get_node_or_null("XRRig") as Node3D
	var panel: Node3D = rig.get_node_or_null(StatusPanel.NODE_NAME) as Node3D if rig != null else null
	if panel != null and panel.visible:
		return [AcceptanceReport.RESULT_FAIL, "the status panel shows over the escape screen"]
	var map: Node3D = rig.find_child(MapHologram.NODE_NAME, true, false) as Node3D if rig != null else null
	if map != null and map.visible:
		return [AcceptanceReport.RESULT_FAIL, "the map shows over the escape screen"]
	return [AcceptanceReport.RESULT_PASS, "%s, %s" % [end.look["line_text"], time]]
