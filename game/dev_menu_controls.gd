class_name DevMenuControls
extends DevMenuEntry

## The dev menu's Controls, Hands and Pitch entries (#778, #790). Split from
## `DevMenuWiring` (#892).
##
## A Controls choice switches `ControlSchemeSwitch` for the rest of the
## session and saves it in `ControlsChoice`. The menu is open at that moment,
## so the ship is already on neutral input, and the switch lets go of any grip
## the gripped scheme held. A Hands or Pitch choice sets `mapping`, the one both
## schemes fly through, for the rest of the session and saves it in the same
## file; the labels, haptics and gripped models read the mapping, so they
## follow at once. Input handling only, never the simulation (MP-2, CMF-6).

## Saves the chosen control scheme, hands and pitch; tests point it at a temporary file.
var store: ControlsChoice = ControlsChoice.new()
## The scheme the ship flies through and the mapping whose hand setting it
## prints; null in tests that do not switch schemes.
var scheme: ControlSchemeSwitch = null
var mapping: ThumbstickMapping = null


func _init(p_scheme: ControlSchemeSwitch, p_mapping: ThumbstickMapping) -> void:
	super([DevMenuSpec.KIND_CONTROLS, DevMenuSpec.KIND_HANDS, DevMenuSpec.KIND_PITCH],
		[DevMenuModel.CONTROLS_PREFIX, DevMenuModel.HANDS_PREFIX, DevMenuModel.PITCH_PREFIX])
	scheme = p_scheme
	mapping = p_mapping


## The scheme the Controls entry opens on; "" without one.
func scheme_shown() -> String:
	return scheme.scheme if scheme != null else ""


func left_handed() -> bool:
	return mapping != null and mapping.left_handed


func invert_pitch() -> bool:
	return mapping != null and mapping.invert_pitch


func choose(result: String) -> void:
	if result.begins_with(DevMenuModel.CONTROLS_PREFIX):
		_switch_controls(result.substr(DevMenuModel.CONTROLS_PREFIX.length()))
	else:
		_set_hands(result)


## Only called while the menu is open, so the ship is on neutral input now.
func _switch_controls(to: String) -> void:
	if scheme == null:
		return
	if scheme.switch_to(to, left_handed(), invert_pitch()):
		store.save(to)


## Only called while the menu is open: the ship is on neutral input, so the
## flip never reaches a tick mid-push.
func _set_hands(result: String) -> void:
	if mapping == null:
		return
	if result.begins_with(DevMenuModel.HANDS_PREFIX):
		mapping.left_handed = result == DevMenuModel.HANDS_PREFIX + "left"
	else:
		mapping.invert_pitch = result == DevMenuModel.PITCH_PREFIX + "inverted"
	store.save_hands(mapping.left_handed, mapping.invert_pitch)
	if scheme != null:
		scheme.announce_hands(mapping)
