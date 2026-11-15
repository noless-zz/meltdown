class_name ComfortPresetFiles
extends RefCounted

## Where the four comfort presets live and how a run picks one (CMF-1, CMF-4).
## Kept out of `main.gd` so the scene script stays short.

## The comfort preset a run starts with until the first-launch flight test
## (CMF-4) picks one. `--comfort-preset=1..4` overrides it.
const START_NUMBER: int = 2
## Preset files in the numbering of the comfort table (CMF-1): index 0 is preset 1.
const PATHS: Array[String] = [
	"res://xr/presets/comfort_anchored.tres", "res://xr/presets/comfort_guided.tres",
	"res://xr/presets/comfort_pilot.tres", "res://xr/presets/comfort_unrestricted.tres",
]
const ARG: String = "--comfort-preset="


## Preset `number` (1..4).
static func load_number(number: int) -> ComfortPreset:
	return load(PATHS[number - 1]) as ComfortPreset


## 1 > 2 > 3 > 4 > 1.
static func next_number(number: int) -> int:
	return number % PATHS.size() + 1


## The last `--comfort-preset=N` with N in 1..4, else `START_NUMBER`.
static func number_from_args(args: PackedStringArray) -> int:
	var number: int = START_NUMBER
	for arg: String in args:
		if not arg.begins_with(ARG):
			continue
		var value: String = arg.substr(ARG.length())
		var valid: bool = value.is_valid_int() and int(value) >= 1 and int(value) <= PATHS.size()
		number = int(value) if valid else START_NUMBER
	return number
