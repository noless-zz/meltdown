class_name DevMenuValueList
extends DevMenuValue

## A value that steps through a fixed list of choices, wrapping (#908): the
## panel corner, the control scheme, the hand and the pitch entries.

var prefix: String
var choices: Array[String] = []
## The words shown for each choice, in the same order as `choices`.
var texts: Array[String] = []
## Index into `choices` of the choice shown.
var index: int = 0


## `p_texts` defaults to the choices themselves.
func _init(p_prefix: String, p_choices: Array[String], p_texts: Array[String] = []) -> void:
	prefix = p_prefix
	choices = p_choices
	texts = p_texts if not p_texts.is_empty() else p_choices


## Shows `choice`, or the first choice when it is not offered.
func select(choice: String) -> void:
	index = maxi(choices.find(choice), 0)


func current() -> String:
	return choices[index]


func value_text() -> String:
	return texts[index]


func step(direction: int) -> void:
	index = posmod(index + direction, choices.size())


func confirmed() -> String:
	return prefix + current()
