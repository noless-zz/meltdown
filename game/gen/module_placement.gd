class_name ModulePlacement
extends RefCounted

## One module as `MineGenerator` placed it: which module, how it is turned and
## where it sits, in whole millimetres (GEN-1, ARC-2), and which of the level's
## boxes it owns.

## The module's id.
var module_id: String = ""
## Index into `ModuleTurns.rows()`.
var turn: int = 0
## Where the module's origin sits in the level, millimetres.
var offset_mm: Vector3i = Vector3i.ZERO
## The placement this one was joined to, or -1 for the first module.
var parent: int = -1
## Index into the parent module's connectors of the one joined, or -1.
var parent_connector: int = -1
## Index into this module's connectors of the one joined, or -1.
var connector: int = -1
## The module's boxes in the level's box list: `first_box` up to, not
## including, `end_box`.
var first_box: int = 0
var end_box: int = 0
## The doorway box spanning the joined opening, or -1 for the first module.
var door_box: int = -1


func _init(p_module_id: String = "", p_turn: int = 0, p_offset_mm: Vector3i = Vector3i.ZERO) -> void:
	module_id = p_module_id
	turn = p_turn
	offset_mm = p_offset_mm
