class_name DevMenuValueFoveation
extends DevMenuValue

## The Foveation entry's value (#871, #908): a `FoveationSwitch.MENU_STEPS`
## setting, the level in `x` and dynamic (non-zero) in `y`.

var prefix: String
var off_text: String
var dynamic_text: String
var note_text: String
var setting: Vector2i = Vector2i.ZERO


func _init(p_prefix: String, p_off_text: String, p_dynamic_text: String,
		p_note_text: String) -> void:
	prefix = p_prefix
	off_text = p_off_text
	dynamic_text = p_dynamic_text
	note_text = p_note_text


## Off or the level, "dynamic" after it when on, then the note that the
## choice lasts this session only.
func value_text() -> String:
	var text: String = off_text if setting.x == 0 else str(setting.x)
	if setting.y != 0:
		text = "%s %s" % [text, dynamic_text]
	return "%s %s" % [text, note_text]


func step(direction: int) -> void:
	setting = FoveationSwitch.menu_step(setting, direction)


func confirmed() -> String:
	return "%s%d:%s" % [prefix, setting.x, "on" if setting.y != 0 else "off"]
