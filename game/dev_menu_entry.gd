class_name DevMenuEntry
extends RefCounted

## The shape every dev menu entry helper shares (#892, ARC-4): the kinds in
## `res://xr/dev_menu.json` it serves, the results of `DevMenuModel.press` it
## takes, and what it shows and does. `DevMenuWiring` holds one helper per
## kind and hands each confirmed result to the helper that takes it, so a new
## entry is one helper file and one line in the wiring's list.
##
## A plain `DevMenuEntry` takes its results and does nothing: the Close entry,
## and the Refresh entry when there is no refresh rate to set.

## The `dev_menu.json` kinds this helper serves.
var kinds: Array[String] = []
## The results it takes: one ending in ":" takes every result beginning with
## it, any other only itself.
var results: Array[String] = []
## Whether choosing closes the menu first (a level, restart or update); a
## setting leaves it open so the change can be seen.
var closes: bool = false


func _init(p_kinds: Array[String] = [], p_results: Array[String] = [], p_closes: bool = false) -> void:
	kinds = p_kinds
	results = p_results
	closes = p_closes


func takes(result: String) -> bool:
	for taken: String in results:
		if result == taken or (taken.ends_with(":") and result.begins_with(taken)):
			return true
	return false


## Before the menu opens: shows this entry's current value on `model`.
func show_on(_model: DevMenuModel) -> void:
	pass


## Once a frame while the menu is open, for a value another entry can change.
func follow(_model: DevMenuModel) -> void:
	pass


## Acts on a result this helper `takes`.
func choose(_result: String) -> void:
	pass
