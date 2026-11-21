extends RefCounted

## Stands in for `OpenXRInterface` in the foveation switch tests (#738): the two
## members `FoveationSwitch` uses, with every write recorded. Not a test file,
## so the runner does not load it.

var writes: Array[String] = []
var foveation_level: int = 0:
	set(value):
		writes.append("level=%d" % value)
		foveation_level = value
var foveation_dynamic: bool = false:
	set(value):
		writes.append("dynamic=%s" % value)
		foveation_dynamic = value


func _init(p_level: int = 0, p_dynamic: bool = false) -> void:
	foveation_level = p_level
	foveation_dynamic = p_dynamic
	writes.clear()
