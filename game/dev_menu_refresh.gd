class_name DevMenuRefresh
extends DevMenuEntry

## The dev menu's Refresh entry (#852, PRF-1, CMF-1, CMF-4): what it shows
## and what choosing a value does. One of `DevMenuWiring`'s entry helpers
## (`DevMenuEntry`, #892).
##
## Choosing saves the value through `RefreshChoice.save`, the file read at
## start, and sets the session's choice so `RefreshRate.apply` asks for the
## new rate at once, as the saved choice is applied at start. The rate asked
## for stays the preset's own unless the preset allows 120 Hz (#838's rule),
## so the menu never asks for a rate the preset forbids. A launch switch
## decides the value the session starts with and the entry opens on it; a
## later menu choice is the pilot's newer word, so it changes the rate now and
## the saved choice for the next start. Display only: the simulation keeps its
## 60 Hz tick (ARC-3, CMF-6).

## The rate the headset is asked for; its `choice` is the session's 120 Hz option.
var rate: RefreshRate = null
## The active comfort preset; null in tests without one, which count as allowing 120 Hz.
var comfort: ComfortWiring = null
## Where the choice is saved; tests point it at a temporary file.
var path: String = RefreshChoice.DEFAULT_PATH


func _init(p_rate: RefreshRate, p_comfort: ComfortWiring) -> void:
	super([DevMenuSpec.KIND_REFRESH], [DevMenuModel.REFRESH_PREFIX])
	rate = p_rate
	comfort = p_comfort


## The session's 120 Hz option, loaded from the launch if the XR session has
## not begun yet, so the menu shows what the session will use.
func choice() -> RefreshChoice:
	if rate.choice == null:
		rate.choice = RefreshChoice.from_launch(path)
	return rate.choice


## Whether the active preset allows 120 Hz; without a preset, it does.
func allowed() -> bool:
	return comfort == null or comfort.preset == null or comfort.preset.allow_120_hz


## Shows the option in use and the preset's note on `model`.
func show_on(model: DevMenuModel) -> void:
	model.set_refresh(choice().on, allowed())


## Once a frame while the menu is open: the note follows a Comfort choice.
func follow(model: DevMenuModel) -> void:
	model.refresh_allowed = allowed()


## Applies a `refresh:<90|120>` result: saves it and asks for the rate now.
func choose(result: String) -> void:
	var high: bool = result == DevMenuModel.REFRESH_PREFIX + DevMenuModel.REFRESH_HIGH
	var chosen: RefreshChoice = choice()
	chosen.on = high
	chosen.save(high, path)
	if comfort != null and comfort.preset != null:
		rate.apply(comfort.preset)
