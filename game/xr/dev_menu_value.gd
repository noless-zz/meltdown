class_name DevMenuValue
extends RefCounted

## One development menu entry's value (#908): what it shows, how left and right
## step it, and what confirming it returns. `DevMenuModel` keeps one per value
## entry kind, so a new entry adds one helper and one registration line rather
## than new fields and branches in the model (ARC-4, files under about 300 lines).
##
## Each helper only holds the menu's own choice; none reads or writes the
## simulation (MP-2, ARC-3).


## The words after the entry's label, the note included.
func value_text() -> String:
	var note: String = note_text()
	return "%s %s" % [plain_text(), note] if note != "" else plain_text()


## The value alone: what every row shows (#1301).
func plain_text() -> String:
	return ""


## A note such as "(this session)", shown only on the highlighted row (#1301); "" for none.
func note_text() -> String:
	return ""


## Steps the value once: `direction` is -1 for left, 1 for right.
func step(_direction: int) -> void:
	pass


## What confirming the entry returns, prefix included (`corner:centre`, ...).
func confirmed() -> String:
	return ""
