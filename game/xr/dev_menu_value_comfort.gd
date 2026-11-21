class_name DevMenuValueComfort
extends DevMenuValue

## The comfort entry's value (#805, #908): the presets 1 to 4 in order, then
## the custom mode (#837) while a valid custom comfort file names its base.

var prefix: String
## Each preset file's `display_name`, or its number when the file is rejected.
var preset_names: Array[String] = []
## Index into `preset_names`: the preset numbered `index + 1`; one past the
## end is the custom mode, offered only while `custom_base` > 0.
var index: int = 0
## The valid custom comfort file's base preset (1..4), or 0 when there is none.
var custom_base: int = 0
## Shown for the custom mode, with `{base}` naming its base preset.
var custom_text: String


func _init(p_prefix: String, p_custom_text: String) -> void:
	prefix = p_prefix
	custom_text = p_custom_text
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		preset_names.append(preset.display_name if preset != null else str(number))


## Shows preset `number` (1..4, or the custom mode while `base` > 0; another
## number shows the first preset). `base` is the valid custom file's, 0 for none.
func open(number: int, base: int) -> void:
	custom_base = maxi(base, 0)
	index = number - 1 if number >= 1 and number <= preset_names.size() else 0
	if number == ComfortPresetFiles.CUSTOM_NUMBER and custom_base > 0:
		index = preset_names.size()


## The preset number shown, 1..4 or the custom mode's.
func number() -> int:
	if index >= preset_names.size():
		return ComfortPresetFiles.CUSTOM_NUMBER
	return index + 1


func value_text() -> String:
	if index >= preset_names.size():
		return custom_text.replace("{base}", str(custom_base))
	return preset_names[index]


func step(direction: int) -> void:
	var choices: int = preset_names.size() + (1 if custom_base > 0 else 0)
	index = posmod(index + direction, choices)


func confirmed() -> String:
	return prefix + str(number())
