class_name DevMenuFoveation
extends DevMenuEntry

## The dev menu's Foveation entry (#871, PRF-1, PRF-2, DEV-6): steps through
## the foveation settings in the headset, so finding the one that collapses
## the picture (#734) takes one session instead of one launch per setting.
## One of `DevMenuWiring`'s entry helpers (`DevMenuEntry`, #892).
##
## Choosing goes through `FoveationSwitch.choose`, the launch switches' apply
## path, and is never saved: the next launch starts with foveation off, or
## with the launch switch. Without an OpenXR interface (the flat build, tests)
## the entry still shows and steps, and applying does nothing. Display only:
## the simulation never hears of it (ARC-3, CMF-6).
##
## A change waits for a long press of A and otherwise reverts by itself
## (`FoveationKeep`, #1523); the wiring hands it each frame through `update`.

## The launch's foveation switch; null in tests without one, which show Off.
var switch: FoveationSwitch = null
## The keep-or-revert of a change; null without a switch.
var keep: FoveationKeep = null
## Its tone and pulse, under the rig's camera once `attach` has run.
var cue: FoveationKeepCue = null
var _reverts_shown: int = 0


func _init(p_switch: FoveationSwitch) -> void:
	super([DevMenuSpec.KIND_FOVEATION], [DevMenuModel.FOVEATION_PREFIX])
	switch = p_switch
	keep = FoveationKeep.new(p_switch) if p_switch != null else null


## Hangs the keep's cue under `rig`'s camera (none in some tests) and, in a
## headset session, reverts when focus is lost (headset off, system menu).
## Connected here rather than in `main.gd`, which is at its line limit.
func attach(rig: Node3D) -> void:
	if cue != null:
		return
	cue = FoveationKeepCue.attach_to(rig, keep)
	var openxr: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if openxr != null and openxr.is_initialized() and keep != null:
		openxr.session_visible.connect(cancel)


## One frame: A held, whether the menu is open, the steady clock.
func update(confirm_held: bool, menu_open: bool, now: float) -> void:
	if keep != null:
		keep.update(confirm_held, menu_open, now)


## Focus lost: a change not yet kept reverts now.
func cancel() -> void:
	if keep != null:
		keep.cancel()


## After a revert, the open menu shows the setting back in use.
func follow(model: DevMenuModel) -> void:
	if keep != null and keep.reverts != _reverts_shown:
		_reverts_shown = keep.reverts
		model.foveation = switch.in_use()


## Opens the entry on the setting in use.
func show_on(model: DevMenuModel) -> void:
	model.foveation = switch.in_use() if switch != null else Vector2i.ZERO


## Applies a `foveation:<0..3>:<on|off>` result; one it cannot read is ignored.
func choose(result: String) -> void:
	var parts: PackedStringArray = result.trim_prefix(DevMenuModel.FOVEATION_PREFIX).split(":")
	if switch == null or parts.size() != 2:
		return
	var level: int = FoveationSwitch.level_from(parts[0])
	if level < 0 or not ["on", "off"].has(parts[1]):
		return
	keep.choose(level, parts[1] == "on")
