class_name MapChoice
extends RefCounted

## Where the map hologram is and how it turns (#1321, MAP-1, PLT-5), kept
## between starts in its own small file, the way `PanelCorner` keeps the
## status panel's corner:
##
##     {"place": "hand" | "cockpit", "turn": "fixed" | "follows_ship"}
##
## `PLACE_HAND` and `TURN_FIXED` are the map as it was before the choice and
## stay the defaults until the owner has tried the others in the headset. A
## missing file (an older install) gives both defaults; a file with an unknown
## key or value gives them with one warning, so it never stops the game.
##
## Presentation only: the file holds these two words and nothing else, and
## `current_place` and `current_turn` are read by `MapPlacement` alone, so no
## choice here can reach the simulation (ARC-3, CMF-6).

const DEFAULT_PATH: String = "user://meltdown_map.json"
const FIELD_PLACE: String = "place"
const FIELD_TURN: String = "turn"
## The map held in the hand that clicks `show_map`, as before #1321.
const PLACE_HAND: String = "hand"
## The map mounted at the cockpit file's `map_mount` spot (`CockpitMapMount`).
const PLACE_COCKPIT: String = "cockpit"
const PLACES: Array[String] = [PLACE_HAND, PLACE_COCKPIT]
## The map's level axes fixed to its holder, as before #1321.
const TURN_FIXED: String = "fixed"
## The map turned against the ship, so ahead on the map is always ahead.
const TURN_FOLLOWS: String = "follows_ship"
const TURNS: Array[String] = [TURN_FIXED, TURN_FOLLOWS]
## What the dev menu's two rows return on a confirm, before the choice.
const PLACE_PREFIX: String = "map_place:"
const TURN_PREFIX: String = "map_turn:"
const LOG_PREFIX: String = "Meltdown: map"

## The place and turn in use now, for `MapPlacement`. Set by `load_saved` and `choose_*`.
static var current_place: String = PLACE_HAND
static var current_turn: String = TURN_FIXED

## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()

var _path: String
var _place: String = PLACE_HAND
var _turn: String = TURN_FIXED


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## The choice of this launch: the saved one, or the defaults.
static func from_launch(path: String = DEFAULT_PATH) -> MapChoice:
	var store: MapChoice = MapChoice.new(path)
	store.load_saved()
	return store


func place() -> String:
	return _place


func turn() -> String:
	return _turn


## Puts the map in `place_name` (one of `PLACES`) and saves it. An unknown
## name is ignored with one warning; returns whether it was taken.
func choose_place(place_name: String) -> bool:
	if not PLACES.has(place_name):
		_warn("place \"%s\" ignored, expected one of %s" % [place_name, ", ".join(PLACES)])
		return false
	_place = place_name
	_turn = current_turn  # Another store may have changed the turn since this one read it.
	current_place = place_name
	_save()
	return true


## Turns the map by `turn_name` (one of `TURNS`) and saves it. An unknown name
## is ignored with one warning; returns whether it was taken.
func choose_turn(turn_name: String) -> bool:
	if not TURNS.has(turn_name):
		_warn("turn \"%s\" ignored, expected one of %s" % [turn_name, ", ".join(TURNS)])
		return false
	_turn = turn_name
	_place = current_place  # Likewise for the place.
	current_turn = turn_name
	_save()
	return true


## Reads the saved choice. A missing file gives the defaults; an unreadable
## or wrong one gives them with a warning.
func load_saved() -> void:
	_place = PLACE_HAND
	_turn = TURN_FIXED
	if FileAccess.file_exists(_path):
		var json: JSON = JSON.new()
		var parsed: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK
		var saved: Variant = json.data if parsed else null
		if _valid(saved):
			_place = str((saved as Dictionary)[FIELD_PLACE])
			_turn = str((saved as Dictionary)[FIELD_TURN])
		else:
			_warn("%s ignored: expected {\"%s\": %s, \"%s\": %s}" % [_path, FIELD_PLACE,
				" | ".join(PLACES), FIELD_TURN, " | ".join(TURNS)])
	current_place = _place
	current_turn = _turn


static func _valid(saved: Variant) -> bool:
	if not saved is Dictionary:
		return false
	var data: Dictionary = saved
	return data.size() == 2 and data.has(FIELD_PLACE) and data.has(FIELD_TURN) \
		and PLACES.has(str(data[FIELD_PLACE])) and TURNS.has(str(data[FIELD_TURN]))


func _save() -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({FIELD_PLACE: _place, FIELD_TURN: _turn}))
	file.close()


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
