class_name DevMenuCorner
extends DevMenuEntry

## The dev menu's Panel corner entry (#763): choosing a corner saves it in
## `PanelCorner`, and the menu opens on the current corner. Split from
## `DevMenuWiring` (#892). View only (CMF-6).

## Saves the chosen corner; tests point it at a temporary file.
var store: PanelCorner = PanelCorner.new()


func _init() -> void:
	super([DevMenuSpec.KIND_CORNER], [DevMenuModel.CORNER_PREFIX])


func choose(result: String) -> void:
	store.choose(result.substr(DevMenuModel.CORNER_PREFIX.length()))
