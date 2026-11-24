class_name DevMenuValueLevel
extends DevMenuValue

## The Level entry's value (#908): the shape `DevMenuModel` expects, over the
## choices and seed `DevMenuLevels` keeps.

var prefix: String
var levels: DevMenuLevels
var spec: DevMenuSpec


func _init(p_prefix: String, p_levels: DevMenuLevels, p_spec: DevMenuSpec) -> void:
	prefix = p_prefix
	levels = p_levels
	spec = p_spec


func plain_text() -> String:
	return levels.text(spec)


func step(direction: int) -> void:
	levels.step(direction)


func confirmed() -> String:
	return prefix + levels.source()
