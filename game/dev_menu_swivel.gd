class_name DevMenuSwivel
extends DevMenuEntry

## The dev menu's Swivel chair entry (#853, CMF-7, CMF-1): what it shows and
## what choosing a value does. One of `DevMenuWiring`'s entry helpers
## (`DevMenuEntry`, #892).
##
## `start` applies the choice saved in `SwivelChoice` when the game starts, and
## choosing On or Off saves it and applies it at once through
## `ComfortWiring.set_swivel_choice`, on top of whichever preset is active, so
## the status panel's swivel tag (#792) follows. The menu is open then, so the
## ship is held and the swivel adds nothing; it recentres on the head when the
## menu closes (#819). In the custom mode the custom file's `swivel_enabled`
## wins: the entry shows it, marked, and a choice there is not saved, so the
## menu never writes over the file. Only this player's yaw input can change,
## never the simulation (CMF-6, ARC-3, MP-2).

const LOG_PREFIX: String = "Meltdown: swivel chair"

## The comfort wiring whose presets the choice switches; null in tests without one.
var comfort: ComfortWiring = null
## Where the choice is saved; tests point it at a temporary file.
var store: SwivelChoice = SwivelChoice.new()


func _init(p_comfort: ComfortWiring) -> void:
	super([DevMenuSpec.KIND_SWIVEL], [DevMenuModel.SWIVEL_PREFIX])
	comfort = p_comfort


## Applies the saved choice; called once when the game starts.
func start() -> void:
	if comfort == null:
		return
	var on: bool = store.load_saved()
	comfort.set_swivel_choice(on)
	if on:
		print("%s on (saved)" % LOG_PREFIX)


## Whether the custom mode is active, so the custom file decides the swivel.
func custom_active() -> bool:
	return comfort != null and comfort.number == ComfortPresetFiles.CUSTOM_NUMBER


## Whether the active preset has the swivel on now.
func on() -> bool:
	return comfort != null and comfort.preset != null and comfort.preset.swivel_enabled


## Shows the swivel in use on `model`, marked when the custom file decides it.
func show_on(model: DevMenuModel) -> void:
	model.set_swivel(on(), custom_active())


## Once a frame while the menu is open: a Comfort choice into or out of the
## custom mode changes what the entry may show, so it follows then.
func follow(model: DevMenuModel) -> void:
	if custom_active() or model.swivel_locked:
		show_on(model)


## Applies a `swivel:<on|off>` result: saved and applied at once, unless the
## custom file decides.
func choose(result: String) -> void:
	if comfort == null:
		return
	if custom_active():
		print("%s left to the custom comfort file" % LOG_PREFIX)
		return
	var chosen: bool = result == DevMenuModel.SWIVEL_PREFIX + DevMenuModel.SWIVEL_ON
	store.save(chosen)
	comfort.set_swivel_choice(chosen)
	print("%s %s (menu)" % [LOG_PREFIX, "on" if chosen else "off"])
