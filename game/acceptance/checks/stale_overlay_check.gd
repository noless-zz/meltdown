extends RefCounted

## The `no_stale_overlay` check (#1439, DEV-6, CMF-3, CMF-8, ARC-3), lane-a's
## file under `acceptance/checks/`. In `suites/m1.json`, after the comfort and
## hit steps:
##
##     {"id": "no_stale_overlay", "checks": ["no_stale_overlay", "no_script_errors"]}
##
## On the headset the view lay under a brown, low-contrast veil from some m1
## step on. Whatever draws over the whole view must be gone once nothing that
## needs it is happening. The check restarts the flight from the start, as the
## end screen's press does (the hit steps leave the ship destroyed), and flies
## `SECONDS` of idle frames through the scene's own `advance_frame`. After
## `GRACE_SECONDS`, in which a fade or vignette may still be easing out, every
## frame on which no pause, fade, end screen, menu, base, hit or turn is in
## progress must show each full-view overlay at zero opacity: the scene's fade
## quad (reset, end screens, dev menu and the launch fade, #1396), the base
## room's launch fade, the comfort vignette and the hit flash's edge strips.
## A fault names the overlay and its opacity. There is no separate pause dim:
## a solo pause only holds the picture still (PLT-7).
##
## The cockpit glass (#1306) is part of the cockpit, not an overlay; its tint
## is #1459's to judge. Nothing here writes simulation state (MP-2).

const CHECK: String = "no_stale_overlay"
const FRAME: float = 1.0 / 72.0
const SECONDS: float = 3.0
## Longer than any fade or vignette ease that may still run when the flight restarts.
const GRACE_SECONDS: float = 1.0
## Opacities below this are float noise, not anything a player could see.
const VISIBLE: float = 0.001


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return judge_scene(runner.main, measurements)


## Restarts `main`'s flight and judges its idle frames; [result, message].
static func judge_scene(main: Node, measurements: Dictionary) -> Array:
	if main.get("fade_overlay") == null:
		# Only a scene whose `_ready` never ran lacks it; the game always attaches it.
		return [AcceptanceReport.RESULT_SKIPPED, "the scene was not set up: it draws no overlay to judge"]
	main.call("restart_level")
	var frames: int = ceili(SECONDS / FRAME)
	var grace: int = ceili(GRACE_SECONDS / FRAME)
	var judged: int = 0
	var busy: Dictionary = {}
	var highest: Dictionary = {}
	for frame: int in frames:
		main.call("advance_frame", FRAME)
		var shown: Dictionary = overlays(main)
		for overlay: String in shown:
			highest[overlay] = maxf(float(highest.get(overlay, 0.0)), float(shown[overlay]))
		if frame < grace:
			continue
		var happening: Array[String] = in_progress(main)
		for what: String in happening:
			busy[what] = int(busy.get(what, 0)) + 1
		if not happening.is_empty():
			continue
		judged += 1
		var stale: String = stale_overlays(shown)
		if stale != "":
			_measure(measurements, judged, busy, highest)
			return [AcceptanceReport.RESULT_FAIL, "%.2f s after the restart, with no pause, fade, end screen, " % (
				float(frame + 1) * FRAME) + "menu, base, hit or turn in progress: %s" % stale]
	_measure(measurements, judged, busy, highest)
	if judged == 0:
		return [AcceptanceReport.RESULT_FAIL, "no idle frame to judge: still in progress %s" % busy]
	return [AcceptanceReport.RESULT_PASS, "%d idle frames, every full-view overlay at 0 (highest during the restart %s)" % [
		judged, highest]]


## Each full-view overlay's opacity now, 0..1, by name; one the scene lacks is left out.
static func overlays(main: Node) -> Dictionary:
	var shown: Dictionary = {}
	var fade: FadeOverlay = main.get("fade_overlay") as FadeOverlay
	if fade != null:
		shown["fade"] = fade.get_alpha()
	var hub: HubWiring = main.get("hub") as HubWiring
	if hub != null and hub.launching.room_overlay != null:
		shown["base_room_fade"] = hub.launching.room_overlay.get_alpha()
	var rig: Node = main.get_node_or_null(^"XRRig")
	var vignette: Vignette = rig.get_node_or_null(VignetteWiring.NODE_PATH) as Vignette if rig != null else null
	if vignette != null:
		shown["vignette"] = vignette.get_strength()
	var combat: CombatWiring = main.get("combat") as CombatWiring
	if combat != null and combat.hit_overlay != null:
		shown["hit_flash"] = combat.hit_overlay.opacity()
	return shown


## What is happening now that may rightly put an overlay over the view.
static func in_progress(main: Node) -> Array[String]:
	var happening: Array[String] = []
	var session: LocalSession = main.get("session")
	if session.paused:
		happening.append("pause")
	var reset_hold: ResetHold = main.get("reset_hold") as ResetHold
	if reset_hold != null and reset_hold.phase != ResetHold.Phase.IDLE:
		happening.append("reset fade")
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	if destroyed != null and (destroyed.end_screen_up() or destroyed.fade_alpha() > 0.0):
		happening.append("end screen")
	var dev_menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring
	if dev_menu != null and (dev_menu.is_open() or dev_menu.alpha > 0.0):
		happening.append("dev menu")
	var hub: HubWiring = main.get("hub") as HubWiring
	if hub != null and (hub.is_open() or hub.alpha() > 0.0):
		happening.append("base or launch fade")
	var combat: CombatWiring = main.get("combat") as CombatWiring
	if combat != null and combat.hit_flash != null and combat.hit_flash.edge_opacity() > 0.0:
		happening.append("hit")
	var vignette: VignetteWiring = main.get("vignette") as VignetteWiring
	if vignette != null and vignette.target > 0.0:
		happening.append("turn")
	return happening


## "name at opacity" for every overlay still visible in `shown`, or "".
static func stale_overlays(shown: Dictionary) -> String:
	var stale: PackedStringArray = []
	for overlay: String in shown:
		if float(shown[overlay]) >= VISIBLE:
			stale.append("%s at opacity %.3f" % [overlay, float(shown[overlay])])
	return ", ".join(stale)


static func _measure(measurements: Dictionary, judged: int, busy: Dictionary, highest: Dictionary) -> void:
	measurements["idle_frames_judged"] = judged
	measurements["frames_in_progress"] = busy
	measurements["highest_opacity"] = highest
