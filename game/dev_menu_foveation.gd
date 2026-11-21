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

## The launch's foveation switch; null in tests without one, which show Off.
var switch: FoveationSwitch = null


func _init(p_switch: FoveationSwitch) -> void:
	super([DevMenuSpec.KIND_FOVEATION], [DevMenuModel.FOVEATION_PREFIX])
	switch = p_switch


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
	switch.choose(level, parts[1] == "on")
