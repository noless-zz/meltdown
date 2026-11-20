class_name FakeJavaException
extends RefCounted

## A Java exception as `JavaClassWrapper.get_exception()` gives it: only its
## `toString` is read.

var text: String = ""


func _init(p_text: String) -> void:
	text = p_text


func toString() -> String:
	return text
