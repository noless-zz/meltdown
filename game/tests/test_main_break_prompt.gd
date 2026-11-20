extends RefCounted

## The take-a-break prompt in the real main scene (#716, CMF-10, CMF-6, CMF-8):
## it hangs under the rig, shows when due, never pauses the simulation or
## moves the view, and a menu tap (Backspace in the flat build) dismisses it.

const FRAME: float = 1.0 / 90.0


static func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["right_stick"] = Vector2(0.4, 0.2)
	values["left_stick"] = Vector2(0.0, 0.8)
	values["buttons"] = buttons
	return values


static func _fly(main: Node, frames: int, buttons: Dictionary = {}) -> void:
	for i: int in frames:
		main.call("apply_controls", _values(buttons))
		main.call("advance_frame", FRAME)


func test_the_prompt_never_pauses_the_simulation_or_moves_the_view() -> String:
	var plain: Node = _main()
	var prompted: Node = _main()
	var wiring: BreakPromptWiring = prompted.get("break_prompt")
	wiring.reminder.advance(30.0 * 60.0, true)
	_fly(plain, 90)
	_fly(prompted, 90)
	var message: String = _compare(plain, prompted, wiring)
	plain.free()
	prompted.free()
	return message


func _compare(plain: Node, prompted: Node, wiring: BreakPromptWiring) -> String:
	if wiring.prompt == null or wiring.prompt.get_parent() != prompted.get_node("XRRig"):
		return "the prompt is not under the rig"
	if not wiring.shown():
		return "the prompt is not shown when due"
	var session: LocalSession = prompted.get("session")
	var plain_session: LocalSession = plain.get("session")
	if session.paused:
		return "the prompt paused the session"
	if session.current_ship().position != plain_session.current_ship().position \
			or session.current_ship().orientation != plain_session.current_ship().orientation:
		return "the ship flew differently while the prompt showed"
	if session.current_ship().position == Vector3.ZERO and plain_session.current_ship().position == Vector3.ZERO:
		return "the ship did not fly at all, so the comparison shows nothing"
	var rig: Node3D = prompted.get_node("XRRig") as Node3D
	var plain_rig: Node3D = plain.get_node("XRRig") as Node3D
	if not rig.transform.is_equal_approx(plain_rig.transform):
		return "the view moved differently while the prompt showed"
	var fade: FadeOverlay = prompted.get("fade_overlay")
	if fade.get_alpha() != 0.0:
		return "the view dimmed while the prompt showed"
	return ""


func test_a_menu_tap_dismisses_it() -> String:
	var main: Node = _main()
	var wiring: BreakPromptWiring = main.get("break_prompt")
	wiring.reminder.advance(30.0 * 60.0, true)
	_fly(main, 2)
	var shown: bool = wiring.shown()
	_fly(main, 2, {ResetHold.KEYBOARD_BUTTON: true})
	_fly(main, 2)
	var after_tap: bool = wiring.shown()
	var flown: float = wiring.reminder.flown_seconds()
	main.free()
	if not shown:
		return "the prompt is not shown when due"
	if after_tap:
		return "a menu tap did not dismiss the prompt"
	if flown > 1.0:
		return "the dismissal did not restart the count (%.1f s)" % flown
	return ""
