class_name DevMenuMap
extends DevMenuEntry

## The dev menu's Map place and Map turn entries (#1321, MAP-1): the menu opens
## on the choice in use, and choosing a value saves it in `MapChoice`, which
## `MapPlacement` reads on the next frame, so the map moves while the menu is
## still open. One of `DevMenuWiring`'s entry helpers (`DevMenuEntry`). View
## only: the map's place and turn never reach the simulation (ARC-3, CMF-6).

## Saves the choice; tests point it at a temporary file.
var store: MapChoice = MapChoice.new()


func _init() -> void:
	super([DevMenuSpec.KIND_MAP_PLACE, DevMenuSpec.KIND_MAP_TURN],
		[MapChoice.PLACE_PREFIX, MapChoice.TURN_PREFIX])


## Shows the place and turn in use on `model`.
func show_on(model: DevMenuModel) -> void:
	model.values.map_place.on = MapChoice.current_place == MapChoice.PLACE_COCKPIT
	model.values.map_turn.on = MapChoice.current_turn == MapChoice.TURN_FOLLOWS


func choose(result: String) -> void:
	if result.begins_with(MapChoice.PLACE_PREFIX):
		store.choose_place(result.substr(MapChoice.PLACE_PREFIX.length()))
	else:
		store.choose_turn(result.substr(MapChoice.TURN_PREFIX.length()))
