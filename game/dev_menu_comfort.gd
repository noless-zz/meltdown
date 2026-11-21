class_name DevMenuComfort
extends DevMenuEntry

## The dev menu's Comfort entry (#805, #806, #837, CMF-4). Split from
## `DevMenuWiring` (#892).
##
## A choice goes through `ComfortWiring.set_preset`, the path the preset button
## takes, so the cockpit, filter and status panel change as they do for the
## button, and `FlightTestWiring` saves it in `ComfortChoice` on the next frame
## as it saves a button change. It changes only this player's view and input
## handling, never the ship (CMF-6). The entry opens on the active preset, so it
## follows a button change. With an accepted custom file it also offers the
## custom mode after preset 4, and opens on it when it is active.

## The comfort preset the entry shows and sets; null in tests without one.
var comfort: ComfortWiring = null


func _init(p_comfort: ComfortWiring) -> void:
	super([DevMenuSpec.KIND_COMFORT], [DevMenuModel.COMFORT_PREFIX])
	comfort = p_comfort


## The preset the entry opens on: the active one, the custom mode included.
func shown() -> int:
	return comfort.number if comfort != null else ComfortPresetFiles.START_NUMBER


## The custom file's base preset when the custom mode is offered, else 0.
func custom_base() -> int:
	return comfort.custom().base if comfort != null and comfort.custom_available() else 0


func choose(result: String) -> void:
	var number: int = int(result.substr(DevMenuModel.COMFORT_PREFIX.length()))
	if comfort != null and comfort.number != number:
		comfort.set_preset(number)
