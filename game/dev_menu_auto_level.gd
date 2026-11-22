class_name DevMenuAutoLevel
extends DevMenuEntry

## The dev menu's Auto-level entry (#1247, CMF-1, CMF-5): what it shows and
## what choosing a value does. One of `DevMenuWiring`'s entry helpers
## (`DevMenuEntry`, #892).
##
## `start` applies the choice saved in `AutoLevelChoice` when the game starts;
## with nothing saved the presets decide, and presets 3 and 4 do not level.
## Choosing On or Off saves it and applies it at once through
## `ComfortWiring.set_auto_level_choice`, on top of whichever preset is active,
## the custom mode included. On presets 1 and 2 the roll always levels: the
## entry shows On, marked as the preset's, and a choice there changes nothing
## and is not saved. Only this player's roll input can change, never the
## simulation (CMF-6, ARC-3, MP-2).

const LOG_PREFIX: String = "Meltdown: auto-level"

## The comfort wiring whose presets the choice switches; null in tests without one.
var comfort: ComfortWiring = null
## Where the choice is saved; tests point it at a temporary file.
var store: AutoLevelChoice = AutoLevelChoice.new()


func _init(p_comfort: ComfortWiring) -> void:
	super([DevMenuSpec.KIND_AUTO_LEVEL], [DevMenuModel.AUTO_LEVEL_PREFIX])
	comfort = p_comfort


## A helper for `p_comfort` with the saved choice already applied.
static func started(p_comfort: ComfortWiring) -> DevMenuAutoLevel:
	var entry: DevMenuAutoLevel = DevMenuAutoLevel.new(p_comfort)
	entry.start()
	return entry


## Applies the saved choice; called once when the game starts.
func start() -> void:
	if comfort == null:
		return
	var saved: int = store.load_saved()
	if saved == AutoLevelChoice.UNSET:
		return
	comfort.set_auto_level_choice(saved == AutoLevelChoice.ON)
	print("%s %s (saved)" % [LOG_PREFIX, "on" if saved == AutoLevelChoice.ON else "off"])


## Whether the active preset always levels, so the entry cannot switch it.
func fixed() -> bool:
	return comfort != null and AutoLevelChoice.fixed_by(comfort.preset)


## Whether the active preset levels the roll now.
func on() -> bool:
	return comfort != null and comfort.preset != null and comfort.preset.levels_roll()


## Shows auto-level in use on `model`, marked while the preset decides it.
func show_on(model: DevMenuModel) -> void:
	var toggle: DevMenuValueToggle = model.value(DevMenuSpec.KIND_AUTO_LEVEL) as DevMenuValueToggle
	toggle.on = on()
	toggle.locked = fixed()


## Once a frame while the menu is open: a Comfort choice into or out of
## presets 1 and 2 changes what the entry may show, so it follows then.
func follow(model: DevMenuModel) -> void:
	var toggle: DevMenuValueToggle = model.value(DevMenuSpec.KIND_AUTO_LEVEL) as DevMenuValueToggle
	if fixed() or toggle.locked:
		show_on(model)


## Applies an `auto_level:<on|off>` result: saved and applied at once, unless
## the preset always levels.
func choose(result: String) -> void:
	if comfort == null:
		return
	if fixed():
		print("%s left to preset %d" % [LOG_PREFIX, comfort.number])
		return
	var chosen: bool = result == DevMenuModel.AUTO_LEVEL_PREFIX + DevMenuModel.AUTO_LEVEL_ON
	store.save(chosen)
	comfort.set_auto_level_choice(chosen)
	print("%s %s (menu)" % [LOG_PREFIX, "on" if chosen else "off"])
