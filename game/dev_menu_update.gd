class_name DevMenuUpdate
extends DevMenuEntry

## The dev menu's update entry (#763): shown while a newer build waits, and
## choosing it does what the tap did before (`UpdateWiring.choose_waiting`).
## Split from `DevMenuWiring` (#892).

## The update wiring; null in tests without one.
var update: UpdateWiring = null


func _init() -> void:
	super([DevMenuSpec.KIND_UPDATE], [DevMenuModel.UPDATE], true)


func choose(_result: String) -> void:
	if update != null:
		update.choose_waiting()
